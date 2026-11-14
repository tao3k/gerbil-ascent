use gerbil_ascent::{
    Atom, Cancellation, Clause, Engine, Error, Limits, Program, Relation, Row, Rule, Term, Type,
    Value,
};
use std::{collections::BTreeMap, sync::Arc, time::Duration};

fn var(id: u32) -> Term {
    Term::Variable(id)
}
fn atom(name: &str, vars: &[u32]) -> Atom {
    Atom::new(name, vars.iter().copied().map(var).collect())
}
fn positive(name: &str, vars: &[u32]) -> Clause {
    Clause::positive(atom(name, vars))
}
fn rows(values: &[[i64; 2]]) -> Vec<Row> {
    values
        .iter()
        .map(|pair| {
            pair.iter()
                .copied()
                .map(Value::from)
                .collect::<Vec<_>>()
                .into()
        })
        .collect()
}
fn closure() -> Program {
    Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![
            Relation::new("edge", vec![Type::Integer; 2], true),
            Relation::new("reach", vec![Type::Integer; 2], false),
        ],
        rules: vec![
            Rule {
                head: atom("reach", &[0, 1]),
                body: vec![positive("edge", &[0, 1])],
            },
            Rule {
                head: atom("reach", &[0, 2]),
                body: vec![positive("reach", &[0, 1]), positive("edge", &[1, 2])],
            },
        ],
    }
}
#[test]
fn recursion_replacement_and_immutable_completed_observations() {
    for engine in [
        Engine::serial().unwrap(),
        Engine::new(1).unwrap(),
        Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 }).unwrap(),
    ] {
        let mut session = engine.open(closure()).unwrap();
        session
            .replace("edge", rows(&[[1, 2], [2, 3], [1, 2]]))
            .unwrap();
        let first = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        assert_eq!(first.relations["reach"], rows(&[[1, 2], [1, 3], [2, 3]]));
        assert!(Arc::ptr_eq(
            &first,
            &session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap()
        ));
        session.replace("edge", rows(&[[4, 5]])).unwrap();
        let second = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        assert_eq!(second.relations["reach"], rows(&[[4, 5]]));
        assert!(second.generation > first.generation);
        assert_eq!(first.relations["reach"].len(), 3);
    }
}
#[test]
fn failed_multi_source_transaction_publishes_nothing() {
    let engine = Engine::new(if cfg!(feature = "rayon") { 2 } else { 1 }).unwrap();
    let mut session = engine.open(closure()).unwrap();
    session.replace("edge", rows(&[[1, 2]])).unwrap();
    let before = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    assert!(
        session
            .replace_sources(BTreeMap::from([
                ("edge".into(), rows(&[[3, 4]])),
                ("reach".into(), rows(&[[7, 8]]))
            ]))
            .is_err()
    );
    assert_eq!(
        session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap(),
        before
    );
    assert!(
        session
            .replace(
                "edge",
                vec![vec![Value::Boolean(false), Value::from(0)].into()]
            )
            .is_err()
    );
}
#[test]
fn exhausted_work_and_cancellation_never_publish_partial_results() {
    let engine = Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 }).unwrap();
    let mut session = engine.open(closure()).unwrap();
    session.replace("edge", rows(&[[1, 2]])).unwrap();
    let before = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    session.replace("edge", rows(&[[3, 4], [4, 5]])).unwrap();
    let limits = Limits {
        max_states: 0,
        ..Limits::default()
    };
    assert_eq!(
        session.run(&limits, &Cancellation::default()),
        Err(Error::StateLimit)
    );
    assert_eq!(session.last_completed(), Some(before.clone()));
    assert_eq!(
        session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap()
            .relations,
        before.relations
    );
    let cancel = Cancellation::default();
    cancel.cancel();
    assert_eq!(
        session.run(&Limits::default(), &cancel),
        Err(Error::Canceled)
    );
    assert_eq!(
        session.run(
            &Limits {
                timeout: Duration::ZERO,
                ..Limits::default()
            },
            &Cancellation::default()
        ),
        Err(Error::Timeout)
    );
    session.replace("edge", rows(&[[3, 4], [4, 5]])).unwrap();
    assert_eq!(
        session.run(
            &Limits {
                max_facts: 2,
                ..Limits::default()
            },
            &Cancellation::default()
        ),
        Err(Error::FactLimit)
    );
}
#[test]
fn stratified_negation_literals_repeated_variables_and_nullary_rows() {
    for engine in [
        Engine::serial().unwrap(),
        Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 }).unwrap(),
    ] {
        let mut program = closure();
        program.relations.extend([
            Relation::new("safe", vec![Type::Integer; 2], false),
            Relation::new("blocked", vec![Type::Integer], true),
            Relation::new("self", vec![Type::Integer], false),
            Relation::new("enabled", vec![], true),
            Relation::new("present", vec![], false),
        ]);
        program.rules.extend([
            Rule {
                head: atom("safe", &[0, 1]),
                body: vec![
                    positive("reach", &[0, 1]),
                    Clause::negative(atom("blocked", &[1])),
                ],
            },
            Rule {
                head: atom("self", &[0]),
                body: vec![positive("edge", &[0, 0])],
            },
            Rule {
                head: atom("present", &[]),
                body: vec![positive("enabled", &[])],
            },
            Rule {
                head: Atom::new("self", vec![Term::Literal(Value::from(-42))]),
                body: vec![],
            },
        ]);
        let mut session = engine.open(program).unwrap();
        session
            .replace("edge", rows(&[[1, 2], [2, 3], [4, 4]]))
            .unwrap();
        session
            .replace("blocked", vec![vec![Value::from(3)].into()])
            .unwrap();
        session.replace("enabled", vec![Vec::new().into()]).unwrap();
        let result = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        assert_eq!(result.relations["safe"], rows(&[[1, 2], [4, 4]]));
        assert_eq!(
            result.relations["self"],
            vec![vec![Value::from(-42)].into(), vec![Value::from(4)].into()]
        );
        assert_eq!(result.relations["present"], vec![Vec::new().into()]);
    }
}
#[test]
fn reject_negative_cycles_unsafe_variables_and_mixed_types() {
    let engine = Engine::new(if cfg!(feature = "rayon") { 2 } else { 1 }).unwrap();
    let mut program = closure();
    program.rules[1].body[0] = Clause::negative(Atom::new("reach", vec![var(0), var(1)]));
    assert!(engine.open(program).is_err());
    let mut program = closure();
    program.rules[0].head.terms[0] = var(99);
    assert!(engine.open(program).is_err());
    let mut program = closure();
    program.relations[1].columns[0] = Type::Text;
    assert!(engine.open(program).is_err());
    assert!(Engine::new(0).is_err());
    #[cfg(not(feature = "rayon"))]
    assert!(Engine::new(2).is_err());
}

#[test]
fn typed_values_preserve_false_zero_text_and_named_symbols() {
    let columns = vec![Type::Boolean, Type::Integer, Type::Text, Type::Symbol];
    let program = Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![
            Relation::new("input", columns.clone(), true),
            Relation::new("output", columns, false),
        ],
        rules: vec![Rule {
            head: atom("output", &[0, 1, 2, 3]),
            body: vec![positive("input", &[0, 1, 2, 3])],
        }],
    };
    let mut session = Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 })
        .unwrap()
        .open(program)
        .unwrap();
    let row: Row = vec![
        Value::Boolean(false),
        Value::from(0),
        Value::from("中文"),
        Value::Symbol("中文".into()),
    ]
    .into();
    session.replace("input", vec![row.clone()]).unwrap();
    assert_eq!(
        session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap()
            .relations["output"],
        vec![row]
    );
}

#[test]
fn upstream_rust_ascent_is_only_a_development_oracle() {
    ascent::ascent! {
        struct Oracle;
        relation edge(i64,i64);
        relation reach(i64,i64);
        reach(x,y) <-- edge(x,y);
        reach(x,z) <-- reach(x,y),edge(y,z);
    }
    for &workers in if cfg!(feature = "rayon") {
        &[1, 2, 4][..]
    } else {
        &[1][..]
    } {
        let engine = Engine::new(workers).unwrap();
        for seed in 0_u64..64 {
            let edges: Vec<[i64; 2]> = (0_i64..25)
                .filter(|bit| {
                    ((seed.wrapping_mul(6_364_136_223_846_793_005).rotate_left(13) >> bit) & 1) == 1
                })
                .map(|bit| [bit / 5, bit % 5])
                .collect();
            let mut oracle = Oracle {
                edge: edges.iter().map(|e| (e[0], e[1])).collect(),
                ..Default::default()
            };
            oracle.run();
            oracle.reach.sort_unstable();
            let mut session = engine.open(closure()).unwrap();
            session.replace("edge", rows(&edges)).unwrap();
            let result = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            let expected = oracle
                .reach
                .into_iter()
                .map(|(a, b)| [a, b])
                .collect::<Vec<_>>();
            assert_eq!(
                result.relations["reach"],
                rows(&expected),
                "workers={workers} seed={seed}"
            );
        }
    }
}
