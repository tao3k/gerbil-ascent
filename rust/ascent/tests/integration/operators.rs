use gerbil_ascent::{Cancellation, Engine, Error, Limits, Program, Row, Value};
fn workers() -> &'static [usize] {
    if cfg!(feature = "rayon") {
        &[1, 2, 4, 8, 12]
    } else {
        &[1]
    }
}
fn rows(values: &[i64]) -> Vec<Row> {
    values
        .iter()
        .map(|v| vec![Value::from(*v)].into())
        .collect()
}
fn guarded(expression: &str) -> Program {
    Program::read_sources(&[&format!("(ascent-fragment (relation input ((x integer?))) (relation output ((x integer?))) ((output X) <-- (input X) (if (X) {expression})))")]).unwrap()
}
#[test]
fn native_closed_guards_preserve_short_circuit_boolean_and_rollback_contracts() {
    for &threads in workers() {
        for (expression, expected) in [
            ("(and (>= X 0) (<= (+ X 1) 2))", vec![0, 1]),
            ("(and #f (even? \"invalid\"))", vec![]),
            ("(or #t (even? \"invalid\"))", vec![-1, 0, 1, 2]),
            ("(and)", vec![-1, 0, 1, 2]),
            ("(or)", vec![]),
        ] {
            let mut session = Engine::new(threads)
                .unwrap()
                .open(guarded(expression))
                .unwrap();
            session.replace("input", rows(&[-1, 0, 1, 2])).unwrap();
            assert_eq!(
                session
                    .run(&Limits::default(), &Cancellation::default())
                    .unwrap()
                    .relations["output"],
                rows(&expected)
            );
        }
        let mut session = Engine::new(threads)
            .unwrap()
            .open(guarded("(or 0 (even? \"invalid\"))"))
            .unwrap();
        let first = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        session.replace("input", rows(&[0])).unwrap();
        assert!(
            matches!(session.run(&Limits::default(), &Cancellation::default()), Err(Error::Evaluation(message)) if message == "guard must return a boolean")
        );
        assert_eq!(session.last_completed().unwrap(), first);
        assert_eq!(
            session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap()
                .relations,
            first.relations
        );
    }
}
#[test]
fn exact_integer_compute_and_grouped_reducers_preserve_empty_group_semantics() {
    for &threads in workers() {
        let mut computed = Engine::new(threads).unwrap().open(Program::read_sources(&[
            "(ascent (relation input ((v integer?))) (relation next ((v integer?))) ((next Y) <-- (input X) (guard (X) even?) (let Y (X) (+ X 1))))"
        ]).unwrap()).unwrap();
        let huge = "340282366920938463463374607431768211456"
            .parse::<num_bigint::BigInt>()
            .unwrap();
        computed
            .replace(
                "input",
                vec![
                    vec![Value::from(huge.clone())].into(),
                    vec![Value::from(-3)].into(),
                ],
            )
            .unwrap();
        assert_eq!(
            computed
                .run(&Limits::default(), &Cancellation::default())
                .unwrap()
                .relations["next"],
            vec![vec![Value::from(huge + 1)].into()]
        );
        for (operator, expected) in [
            ("count", vec![("a", 2), ("b", 1), ("empty", 0)]),
            ("sum", vec![("a", 7), ("b", 9), ("empty", 0)]),
            ("min", vec![("a", 2), ("b", 9)]),
            ("max", vec![("a", 5), ("b", 9)]),
        ] {
            let input = if operator == "count" { "" } else { "V" };
            let source = format!(
                "(ascent-fragment (relation group ((g symbol?))) (relation n ((g symbol?) (v integer?))) (relation out ((g symbol?) (v integer?))) ((out G T) <-- (group G) (aggregate T gerbil-ascent-{operator} ({input}) (n G V))))"
            );
            let mut session = Engine::new(threads)
                .unwrap()
                .open(Program::read_sources(&[&source]).unwrap())
                .unwrap();
            session
                .replace(
                    "group",
                    ["a", "b", "empty"]
                        .map(|v| vec![Value::Symbol(v.into())].into())
                        .to_vec(),
                )
                .unwrap();
            session
                .replace(
                    "n",
                    [("a", 2), ("a", 5), ("b", 9)]
                        .map(|(g, v)| vec![Value::Symbol(g.into()), Value::from(v)].into())
                        .to_vec(),
                )
                .unwrap();
            let snapshot = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            let expected: Vec<Row> = expected
                .into_iter()
                .map(|(g, v)| vec![Value::Symbol(g.into()), Value::from(v)].into())
                .collect();
            assert_eq!(snapshot.relations["out"], expected);
            session.replace("n", vec![]).unwrap();
            let snapshot = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            assert_eq!(
                snapshot.relations["out"].len(),
                if matches!(operator, "count" | "sum") {
                    3
                } else {
                    0
                }
            );
        }
    }
}
#[test]
fn unsupported_operators_unbound_guards_and_recursive_reducers_fail_admission() {
    for body in [
        "(if (X Y) (< X Y))",
        "(if (X) (< X Y))",
        "(if (X X) (even? X))",
        "(compute Y (+ X))",
        "(compute Y (system X))",
        "(reduce Y (sum) (input X))",
        "(reduce Y (count X) (input X))",
        "(reduce Y (count) (output X))",
    ] {
        let text = format!(
            "(ascent (relation input ((x integer?))) (relation output ((x integer?))) ((output Y) <-- (input X) {body}))"
        );
        assert!(Program::read_sources(&[&text]).is_err(), "{body}");
    }
}

#[test]
fn directly_constructed_expressions_cannot_bypass_dsl_structure_limits() {
    use gerbil_ascent::{Clause, Expression, Operator, Term};
    let mut program = guarded("(even? X)");
    let mut expression = Expression::Term(Term::Variable(0));
    for _ in 0..130 {
        expression = Expression::Call(Operator::Not, vec![expression]);
    }
    program.rules[0].body.push(Clause::Guard {
        inputs: vec![0],
        expression,
    });
    assert!(
        matches!(Engine::new(1).unwrap().open(program),Err(Error::InvalidProgram(message)) if message=="expression structure bound")
    );
}
