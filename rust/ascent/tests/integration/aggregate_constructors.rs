use gerbil_ascent::{
    Cancellation, Engine, FactLimits, GraphItem, ObjectInput as Input, ProvenanceLimits,
    ProvenanceStatus, SourceSession, Value,
};
use std::collections::BTreeMap;
const FIXTURE: &str = include_str!("../../../../t/qualification/evidence-api-module.ss");
fn integer(n: i64) -> Input {
    Input::Integer(n.into())
}
fn inputs(values: &[Input]) -> Input {
    Input::List(values.to_vec())
}
fn numeric(value: &Value) -> String {
    match value {
        Value::Integer(n) => n.to_string(),
        Value::Object(v) => match &v.graph().root {
            GraphItem::Number(n) => n.clone(),
            _ => panic!("numeric graph"),
        },
        _ => panic!("numeric value"),
    }
}
fn source(operator: &str) -> String {
    let variables = if operator == "count" { "'()" } else { "'(v)" };
    format!(
        "(define-evidence (make values) (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 (map list values)) (gerbil-ascent-relation 'out 1 '())) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (gerbil-ascent-variable 'result)))) (list (gerbil-ascent-aggregate 'result 'input (list (gerbil-ascent-variable 'v)) {variables} gerbil-ascent-{operator})))) 32 64 96 '(input)))"
    )
}
#[test]
fn original_mean_constructor_preserves_inexact_rounding_empty_groups_and_proof_authority() {
    let engine = Engine::new(1).unwrap();
    engine
        .register_module(":consumer/aggregate", FIXTURE)
        .unwrap();
    let module = engine.module(":consumer/aggregate").unwrap();
    let constructor = module
        .call(
            "make-aggregate",
            &[inputs(&[integer(1), integer(2), integer(4)])],
            None,
        )
        .unwrap();
    let session = constructor.open_session(FactLimits::default()).unwrap();
    module.close();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let result = session.run(None, &limits, &cancel).unwrap();
    let mean = &result.relations["average"][0][0];
    assert!(matches!(mean, Value::Object(_)));
    assert_eq!(
        numeric(mean).parse::<f64>().unwrap().to_bits(),
        (7.0_f64 / 3.0).to_bits()
    );
    let proof = session
        .provenance(
            result.result_handle,
            "average",
            &ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    assert!(
        proof
            .verify(
                &proof.graph().unwrap(),
                &ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
    );
    session
        .replace(
            BTreeMap::from([("number".into(), vec![])]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert!(proof.graph().is_err());
    let result = session.run(None, &limits, &cancel).unwrap();
    assert!(result.relations["average"].is_empty());
    assert_eq!(
        session
            .provenance(
                result.result_handle,
                "average",
                &ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
            .graph()
            .unwrap()
            .status,
        ProvenanceStatus::ClosedAbsent
    );
}
#[test]
fn numeric_aggregate_constructors_and_replacement_preserve_exact_rationals_and_rollback() {
    for (operator, wanted, empty) in [
        ("count", "2", Some("0")),
        ("sum", "2/3", Some("0")),
        ("min", "1/6", None),
        ("max", "1/2", None),
    ] {
        let engine = Engine::new(1).unwrap();
        let module = engine.load_definitions(&source(operator)).unwrap();
        let args = inputs(&[
            Input::Number("1/6".into()),
            Input::Number("1/2".into()),
            Input::Number("1/2".into()),
        ]);
        let value = module.call("make", &[args], None).unwrap();
        let session = value.open_session(FactLimits::default()).unwrap();
        let limits = SourceSession::default_limits();
        let cancel = Cancellation::default();
        let result = session.run(None, &limits, &cancel).unwrap();
        assert_eq!(numeric(&result.relations["out"][0][0]), wanted);
        let proof = session
            .provenance(
                result.result_handle,
                "out",
                &ProvenanceLimits::default(),
                &cancel,
            )
            .unwrap();
        assert!(
            proof
                .verify(
                    &proof.graph().unwrap(),
                    &ProvenanceLimits::default(),
                    &cancel
                )
                .unwrap()
        );
        if operator != "count" {
            assert!(
                session
                    .replace(
                        BTreeMap::from([(
                            "input".into(),
                            vec![vec![Input::Text("invalid".into())]]
                        )]),
                        &limits,
                        &cancel
                    )
                    .is_err()
            );
            assert_eq!(
                numeric(&session.run(None, &limits, &cancel).unwrap().relations["out"][0][0]),
                wanted
            );
            assert!(proof.graph().is_ok());
        }
        session
            .replace(BTreeMap::from([("input".into(), vec![])]), &limits, &cancel)
            .unwrap();
        let observed = session.run(None, &limits, &cancel).unwrap();
        assert_eq!(
            observed.relations["out"]
                .first()
                .map(|row| numeric(&row[0])),
            empty.map(str::to_string)
        );
    }
}
#[test]
fn inexact_folds_are_deterministic_across_hash_orders_and_rayon_workers() {
    let workers: &[usize] = if cfg!(feature = "rayon") {
        &[1, 4, 12]
    } else {
        &[1]
    };
    for &threads in workers {
        for operator in ["sum", "mean"] {
            for _ in 0..3 {
                let engine = Engine::new(threads).unwrap();
                let module = engine.load_definitions(&source(operator)).unwrap();
                let value = module
                    .call(
                        "make",
                        &[inputs(&[
                            Input::Inexact(1e16),
                            Input::Inexact(-1e16),
                            Input::Inexact(1.0),
                        ])],
                        None,
                    )
                    .unwrap();
                let session = value.open_session(FactLimits::default()).unwrap();
                let cancel = Cancellation::default();
                let result = session
                    .run(None, &SourceSession::default_limits(), &cancel)
                    .unwrap();
                assert_eq!(numeric(&result.relations["out"][0][0]), "0.0");
                let proof = session
                    .provenance(
                        result.result_handle,
                        "out",
                        &ProvenanceLimits::default(),
                        &cancel,
                    )
                    .unwrap();
                assert!(
                    proof
                        .verify(
                            &proof.graph().unwrap(),
                            &ProvenanceLimits::default(),
                            &cancel
                        )
                        .unwrap()
                );
            }
        }
    }
}
#[test]
fn native_negation_guard_and_lexically_captured_binding_lower_to_rust_clauses() {
    let source = "(def (make cutoff delta) (ascent-evidence-module (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 '((1) (2) (3) (4))) (gerbil-ascent-relation 'blocked 1 '((4))) (gerbil-ascent-relation 'out 1 '())) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (gerbil-ascent-variable 'y)))) (list (gerbil-ascent-atom 'input (list (gerbil-ascent-variable 'x))) (gerbil-ascent-negation 'blocked (list (gerbil-ascent-variable 'x))) (gerbil-ascent-guard '(x) (lambda (v) (and (> v cutoff) (even? v)))) (gerbil-ascent-binding 'y '(x) (lambda (v) (+ v delta)))))) 32 64 96 '(input blocked)) #f))";
    let engine = Engine::new(1).unwrap();
    let module = engine.load_definitions(source).unwrap();
    let value = module
        .call("make", &[integer(1), integer(10)], None)
        .unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    module.close();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let result = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(result.relations["out"], vec![vec![12.into()].into()]);
    let proof = session
        .provenance(
            result.result_handle,
            "out",
            &ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    assert!(
        proof
            .verify(
                &proof.graph().unwrap(),
                &ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
    );
}

#[test]
fn bundled_execution_evidence_uses_original_native_dsl_and_explicit_source_authority() {
    let engine = Engine::new(1).unwrap();
    let module = engine.module(":gerbil-ascent/evidence/execution").unwrap();
    let value = module.call("make-execution-evidence", &[], None).unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    module.close();
    let descriptors = session.program().unwrap().relations;
    assert!(
        descriptors
            .iter()
            .any(|r| r.name == "required_step" && r.source)
    );
    assert!(
        descriptors
            .iter()
            .any(|r| r.name == "checked_step" && !r.source)
    );
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    session.run(None, &limits, &cancel).unwrap();
    session
        .replace(
            BTreeMap::from([
                (
                    "required_step".into(),
                    vec![
                        vec![Input::Text("finished".into())],
                        vec![Input::Text("missing".into())],
                    ],
                ),
                (
                    "observed_step".into(),
                    vec![vec![
                        Input::Text("finished".into()),
                        Input::Text("PASS".into()),
                        Input::Text("native.test".into()),
                    ]],
                ),
            ]),
            &limits,
            &cancel,
        )
        .unwrap();
    let observed = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(
        observed.relations["checked_step"],
        vec![vec!["finished".into()].into()]
    );
    assert_eq!(
        observed.relations["missing_step"],
        vec![vec!["missing".into()].into()]
    );
    let proof = session
        .provenance(
            observed.result_handle,
            "missing_step",
            &ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    assert!(
        proof
            .verify(
                &proof.graph().unwrap(),
                &ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
    );
    let explanation = session
        .explain(observed.result_handle, "missing_step")
        .unwrap();
    assert!(format!("{:?}", explanation.graph().unwrap()).contains("source refinement"));
    assert!(
        session
            .replace(
                BTreeMap::from([(
                    "checked_step".into(),
                    vec![vec![Input::Text("forged".into())]]
                )]),
                &limits,
                &cancel
            )
            .is_err()
    );
    assert!(proof.graph().is_ok());
}

fn scalar_observation(value: &gerbil_ascent::ModuleValue) -> Option<String> {
    let graph = value.graph().unwrap();
    match &graph.root {
        GraphItem::Null => None,
        GraphItem::Reference(id) => {
            let gerbil_ascent::ObjectNode::Pair(GraphItem::Number(n), GraphItem::Null) =
                &graph.nodes[id]
            else {
                panic!("one numeric result");
            };
            Some(n.clone())
        }
        _ => panic!("aggregate list"),
    }
}
#[test]
fn direct_aggregate_contracts_match_original_scheme_numeric_outputs() {
    use std::io::Write;
    use std::process::{Command, Stdio};
    let cases = aggregate_cases();
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let mut child = Command::new("gxi")
        .arg(root.join("tests/fixtures/aggregate-oracle.ss"))
        .env("GERBIL_PATH", root.join("../../.gerbil"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    {
        let mut input = child.stdin.take().unwrap();
        for (name, tuples, _) in &cases {
            writeln!(input, "({name} {tuples})").unwrap();
        }
    }
    let oracle = child.wait_with_output().unwrap();
    assert!(
        oracle.status.success(),
        "{}",
        String::from_utf8_lossy(&oracle.stderr)
    );
    let oracle = String::from_utf8(oracle.stdout).unwrap();
    let lines = oracle.lines().collect::<Vec<_>>();
    assert_eq!(lines.len(), cases.len());
    let engine = Engine::new(1).unwrap();
    let module = engine.module(":gerbil-ascent/program/aggregators").unwrap();
    for ((name, _, tuples), expected) in cases.iter().zip(lines) {
        let value = module
            .call(
                &format!("gerbil-ascent-{name}"),
                std::slice::from_ref(tuples),
                None,
            )
            .unwrap();
        let actual = scalar_observation(&value);
        if expected == "()" {
            assert!(actual.is_none());
        } else {
            let expected = expected.trim_start_matches('(').trim_end_matches(')');
            let actual = actual.unwrap();
            if let Ok(n) = expected.parse::<f64>() {
                assert_eq!(actual.parse::<f64>().unwrap().to_bits(), n.to_bits());
            } else {
                assert_eq!(actual, expected);
            }
        }
    }
    let malformed = inputs(&[
        inputs(&[Input::Text("not numeric".into())]),
        inputs(&[integer(1), integer(2)]),
    ]);
    assert!(
        matches!(module.call("gerbil-ascent-sum",&[malformed],None),Err(gerbil_ascent::Error::Evaluation(message)) if message.contains("tuple arity"))
    );
}

#[test]
fn native_dsl_initial_expressions_freeze_complex_values_without_implicit_source_authority() {
    let source = "(def (make values) (ascent (relation input (v) (map list values)) (relation out (v)) ((out V) <-- (input V))))";
    let engine = Engine::new(1).unwrap();
    let module = engine.load_definitions(source).unwrap();
    let vector = Input::Vector(vec![integer(1), Input::Number("1/3".into())]);
    let value = module
        .call("make", &[inputs(&[vector.clone(), vector])], None)
        .unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    module.close();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let result = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(result.relations["out"].len(), 1);
    assert!(matches!(result.relations["out"][0][0], Value::Object(_)));
    assert!(
        session
            .replace(BTreeMap::from([("input".into(), vec![])]), &limits, &cancel)
            .is_err()
    );
    let proof = session
        .provenance(
            result.result_handle,
            "out",
            &ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    assert!(
        proof
            .verify(
                &proof.graph().unwrap(),
                &ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
    );
}

fn aggregate_cases() -> Vec<(&'static str, &'static str, Input)> {
    let cases = vec![
        (
            "count",
            "(() ())",
            Input::List(vec![Input::List(vec![]), Input::List(vec![])]),
        ),
        (
            "sum",
            "((1/6) (1/2))",
            inputs(&[
                inputs(&[Input::Number("1/6".into())]),
                inputs(&[Input::Number("1/2".into())]),
            ]),
        ),
        (
            "mean",
            "((1) (2) (4))",
            inputs(&[
                inputs(&[integer(1)]),
                inputs(&[integer(2)]),
                inputs(&[integer(4)]),
            ]),
        ),
        ("mean", "()", Input::List(vec![])),
        ("sum", "()", Input::List(vec![])),
        (
            "min",
            "((0.) (-0.))",
            inputs(&[
                inputs(&[Input::Inexact(0.0)]),
                inputs(&[Input::Inexact(-0.0)]),
            ]),
        ),
        (
            "max",
            "((-0.) (0.))",
            inputs(&[
                inputs(&[Input::Inexact(-0.0)]),
                inputs(&[Input::Inexact(0.0)]),
            ]),
        ),
        (
            "sum",
            "((0) (-0.))",
            inputs(&[inputs(&[integer(0)]), inputs(&[Input::Inexact(-0.0)])]),
        ),
    ];
    cases
}

#[test]
fn closed_callbacks_respect_character_literals_and_reject_side_effects_or_shadowed_operators() {
    let engine = Engine::new(1).unwrap();
    let make = |body: &str, extra: &str| {
        format!(
            "(def counter 0) {extra} (def (counter-value) counter) (define-evidence (make values) (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 (map list values)) (gerbil-ascent-relation 'out 1 '())) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (gerbil-ascent-variable 'x)))) (list (gerbil-ascent-atom 'input (list (gerbil-ascent-variable 'x))) (gerbil-ascent-guard '(x) (lambda (v) {body})))) ) 32 64 96 '(input)))"
        )
    };
    let module = engine
        .load_definitions(&make("(equal? v '#\\a)", ""))
        .unwrap();
    let value = module
        .call(
            "make",
            &[inputs(&[Input::Character('a'), Input::Character('b')])],
            None,
        )
        .unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    let result = session
        .run(
            None,
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(result.relations["out"].len(), 1);
    for (body, extra) in [
        ("(begin (set! counter 1) #t)", ""),
        ("(> v 0)", "(def (> a b) #t)"),
        ("(equal? v '1.5)", ""),
    ] {
        let module = engine.load_definitions(&make(body, extra)).unwrap();
        let value = module.call("make", &[inputs(&[integer(1)])], None).unwrap();
        assert!(value.open_session(FactLimits::default()).is_err());
        let counter = module.call("counter-value", &[], None).unwrap();
        assert!(matches!(counter.graph().unwrap().root,GraphItem::Number(ref value) if value=="0"));
    }
}
