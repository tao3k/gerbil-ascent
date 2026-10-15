//! Matched Scheme/Rayon constructor semantics, including initial occurrences.
use gerbil_ascent::{Cancellation, FactLimits, ProvenanceLimits, Row, SourceSession};
fn sources() -> Vec<String> {
    let structure = "(def (make) (let ((x (gerbil-ascent-variable 'x))) (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 (list (list (vector 1)) (list (vector 1)) (list (vector 2)))) (gerbil-ascent-relation 'out 1 [])) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list x))) (list (gerbil-ascent-atom 'input (list x))))) 32 64 96 '(input))))";
    let mut result = vec![structure.into()];
    for reducer in ["count", "sum", "mean"] {
        let variables = if reducer == "count" { "'()" } else { "'(v)" };
        result.push(format!("(def (make) (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 '((1/6) (1/2) (1/2))) (gerbil-ascent-relation 'out 1 [])) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (gerbil-ascent-variable 'result)))) (list (gerbil-ascent-aggregate 'result 'input (list (gerbil-ascent-variable 'v)) {variables} gerbil-ascent-{reducer})))) 32 64 96 '(input)))"));
    }
    result
}
fn sorted(mut rows: Vec<Row>) -> Vec<Row> {
    rows.sort();
    rows
}
#[test]
fn original_constructors_match_owned_rayon_with_duplicates_complex_values_and_checked_proofs() {
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    for workers in [1, 2, 4, 8, 12] {
        for source in sources() {
            let engine = ascent_scheme::Engine::new(workers).unwrap();
            let module = engine.load_definitions(&source).unwrap();
            let value = module.call("make", &[], None).unwrap();
            let native = value.open_session(FactLimits::default()).unwrap();
            let mut owned = value.project_session(FactLimits::default()).unwrap();
            let native_receipt = native.run(None, &limits, &cancellation).unwrap();
            let native_handle = u64::try_from(
                native_receipt
                    .field("resultHandle")
                    .unwrap()
                    .index()
                    .unwrap(),
            )
            .unwrap();
            let native_result = native.result(native_handle).unwrap();
            let receipt = owned.run(None, &limits, &cancellation).unwrap();
            let result = owned.result(receipt.result_handle).unwrap();
            for relation in ["input", "out"] {
                let expected =
                    crate::support::rows(&native_result.rows(relation).unwrap(), native_handle)
                        .unwrap();
                assert_eq!(
                    sorted(result.rows(relation).unwrap().to_vec()),
                    sorted(expected),
                    "{workers} workers: {relation}"
                );
            }
            let proof = owned
                .provenance(
                    receipt.result_handle,
                    "out",
                    &ProvenanceLimits::default(),
                    &cancellation,
                )
                .unwrap();
            assert!(
                proof
                    .verify(
                        &proof.graph().unwrap(),
                        &ProvenanceLimits::default(),
                        &cancellation
                    )
                    .unwrap()
            );
            let native_proof = native
                .provenance(
                    native_handle,
                    "out",
                    &ProvenanceLimits::default(),
                    &cancellation,
                )
                .unwrap();
            assert!(
                native_proof
                    .verify(
                        &native_proof.graph().unwrap(),
                        &ProvenanceLimits::default(),
                        &cancellation
                    )
                    .unwrap()
            );
        }
    }
}
#[test]
fn registered_call_module_retains_export_locations_and_caller_value_authority() {
    let engine = ascent_scheme::Engine::new(1).unwrap();
    engine.register_module(":example/counter","(export inc echo) (def counter 0) (def (inc) (set! counter (+ counter 1)) counter) (def (echo value) value)").unwrap();
    let target = engine.module(":example/counter").unwrap();
    let caller = engine.load_definitions("(def (value) (vector 7))").unwrap();
    let value = caller.call("value", &[], None).unwrap();
    for wanted in ["1", "2"] {
        let answer = caller
            .call_module(":example/counter", "inc", &[])
            .unwrap()
            .graph()
            .unwrap();
        assert!(
            matches!(&gerbil_ascent::ObjectGraph::read_native(&answer).unwrap().root,gerbil_ascent::GraphItem::Number(n) if n==wanted)
        );
    }
    let echo = caller
        .call_module(
            ":example/counter",
            "echo",
            &[gerbil_ascent::ObjectInput::Reference(
                value.reference(None).unwrap(),
            )],
        )
        .unwrap();
    assert!(
        !echo
            .graph()
            .unwrap()
            .field("nodes")
            .unwrap()
            .list()
            .unwrap()
            .is_empty()
    );
    target.close();
    assert!(value.graph().is_ok());
}

#[test]
fn checked_native_proofs_revalidate_current_mutable_source_support() {
    let engine = ascent_scheme::Engine::new(1).unwrap();
    let source = "(def cell (vector 1)) (def (change n) (vector-set! cell 0 n)) (def (make) (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 (list (list cell))) (gerbil-ascent-relation 'out 1 [])) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (gerbil-ascent-literal 7)))) (list (gerbil-ascent-atom 'input (list (gerbil-ascent-variable 'x)))))) 32 64 96 '(input)))";
    let module = engine.load_definitions(source).unwrap();
    let value = module.call("make", &[], None).unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let receipt = session.run(None, &limits, &cancel).unwrap();
    let handle = u64::try_from(receipt.field("resultHandle").unwrap().index().unwrap()).unwrap();
    let proof = session
        .provenance(handle, "out", &ProvenanceLimits::default(), &cancel)
        .unwrap();
    let graph = proof.graph().unwrap();
    assert!(
        proof
            .verify(&graph, &ProvenanceLimits::default(), &cancel)
            .unwrap()
    );
    module
        .call(
            "change",
            &[gerbil_ascent::ObjectInput::Integer(2.into())],
            None,
        )
        .unwrap();
    assert!(
        proof
            .verify(&graph, &ProvenanceLimits::default(), &cancel)
            .is_err()
    );
    assert!(proof.graph().is_err());
    let current = session
        .provenance(handle, "out", &ProvenanceLimits::default(), &cancel)
        .unwrap();
    assert!(
        !current
            .verify(&graph, &ProvenanceLimits::default(), &cancel)
            .unwrap()
    );
    assert!(
        current
            .verify(
                &current.graph().unwrap(),
                &ProvenanceLimits::default(),
                &cancel
            )
            .unwrap()
    );
}

#[test]
fn module_values_transfer_into_sources_and_survive_the_module_owner() {
    use gerbil_ascent::ObjectInput;
    let engine = ascent_scheme::Engine::new(1).unwrap();
    let module=engine.load_definitions("(def (cell) (vector 7)) (def (make) (gerbil-ascent-program (list (gerbil-ascent-relation 'input 1 []) (gerbil-ascent-relation 'out 1 [])) (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'out (list (gerbil-ascent-variable 'x)))) (list (gerbil-ascent-atom 'input (list (gerbil-ascent-variable 'x)))))) 8 8 16 '(input)))").unwrap();
    let value = module.call("cell", &[], None).unwrap();
    let session = module
        .call("make", &[], None)
        .unwrap()
        .open_session(FactLimits::default())
        .unwrap();
    session
        .replace(
            std::collections::BTreeMap::from([(
                "input".into(),
                vec![vec![ObjectInput::Reference(value.reference(None).unwrap())]],
            )]),
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    value.close();
    module.close();
    let receipt = session
        .run(
            None,
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    let handle = u64::try_from(receipt.field("resultHandle").unwrap().index().unwrap()).unwrap();
    let graph = session.result(handle).unwrap().rows("out").unwrap();
    let rows = crate::support::rows(&graph, handle).unwrap();
    assert_eq!(rows.len(), 1);
    let gerbil_ascent::Value::Object(value) = &rows[0][0] else {
        panic!("vector cell")
    };
    let gerbil_ascent::GraphItem::Reference(root) = value.graph().root else {
        panic!("vector root")
    };
    assert!(
        matches!(&value.graph().nodes[&root],gerbil_ascent::ObjectNode::Vector(items) if matches!(&items[..],[gerbil_ascent::GraphItem::Number(n)] if n=="7"))
    );
}

#[test]
fn engine_shutdown_reclaims_native_slots_while_revoked_leases_are_still_retained() {
    let engine = ascent_scheme::Engine::new(1).unwrap();
    let modules = (0..64)
        .map(|_| engine.load_definitions("(def (answer) 7)").unwrap())
        .collect::<Vec<_>>();
    let value = modules[0].call("answer", &[], None).unwrap();
    engine.shutdown();
    assert!(value.graph().is_err());
    let next = ascent_scheme::Engine::new(1).unwrap();
    let live = next.load_definitions("(def (answer) 9)").unwrap();
    assert!(live.call("answer", &[], None).is_ok());
    drop(modules);
}

#[test]
fn explicitly_typed_text_is_not_reinterpreted_as_a_symbol_on_source_replacement() {
    use gerbil_ascent::{ObjectInput, Value};
    let engine = ascent_scheme::Engine::new(1).unwrap();
    let module=engine.load_definitions("(define-evidence (make) (sources input) (outputs out) (relation input ((x symbol?))) (relation out ((x symbol?))) ((out X) <-- (input X)))").unwrap();
    let session = module
        .call("make", &[], None)
        .unwrap()
        .open_session(FactLimits::default())
        .unwrap();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    assert!(
        session
            .replace(
                std::collections::BTreeMap::from([(
                    "input".into(),
                    vec![vec![ObjectInput::Value(Value::Text("x".into()))]]
                )]),
                &limits,
                &cancel
            )
            .is_err()
    );
    session
        .replace(
            std::collections::BTreeMap::from([(
                "input".into(),
                vec![vec![ObjectInput::Text("x".into())]],
            )]),
            &limits,
            &cancel,
        )
        .unwrap();
    let receipt = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(
        receipt.field("relations").unwrap().field("out").unwrap(),
        &gerbil_ascent::Data::List(vec![gerbil_ascent::Data::List(vec![
            gerbil_ascent::Data::from("x")
        ])])
    );
}
