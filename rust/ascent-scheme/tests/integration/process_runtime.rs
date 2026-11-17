//! Production process owners: identity, lexical state, typed values and interruption.
use ascent_scheme::{Engine, ProcessPool, WorkerProgram};
use gerbil_ascent::{Cancellation, Data, Error, FactLimits, Limits, ObjectInput};
use std::{collections::BTreeSet, time::Duration};
#[path = "../support/source_cancellation.rs"]
mod source_cancellation;
fn program() -> WorkerProgram {
    WorkerProgram::new(env!("CARGO_BIN_EXE_ascent-scheme-worker"), vec![])
}

#[test]
fn scheme_actor_progresses_while_the_process_transport_waits_for_a_request() {
    let pool = ProcessPool::with_program(1, &program()).unwrap();
    assert_eq!(pool.receipts()[0].processors, 1);
    let engine = Engine::new(1).unwrap().on_process(pool.owner(0).unwrap());
    engine
        .register_module(
            "resident-wake",
            r#"
              (export start)
              (def (start gate marker)
                (thread-start!
                 (make-thread
                  (lambda ()
                    (let await-gate ()
                      (unless (file-exists? gate)
                        (thread-sleep! 0.005)
                        (await-gate)))
                    (call-with-output-file marker
                      (lambda (port) (display "actor-ran" port))))))
                #t)
            "#,
        )
        .unwrap();
    let module = engine.module("resident-wake").unwrap();
    let directory = tempfile::tempdir().unwrap();
    let gate = directory.path().join("client-returned");
    let marker = directory.path().join("actor-ran");
    let reply = module
        .call(
            "start",
            &[
                ObjectInput::Text(gate.to_str().unwrap().into()),
                ObjectInput::Text(marker.to_str().unwrap().into()),
            ],
            None,
        )
        .unwrap();

    // The actor can finish only after the caller returned and created the gate.
    // Keep the reply rooted so dropping it cannot introduce another VM call.
    std::fs::write(&gate, "").unwrap();
    let deadline = std::time::Instant::now() + Duration::from_secs(5);
    let observed = loop {
        if let Ok(text) = std::fs::read_to_string(&marker)
            && text == "actor-ran"
        {
            break true;
        }
        if std::time::Instant::now() >= deadline {
            break false;
        }
        std::thread::sleep(Duration::from_millis(10));
    };
    assert!(observed, "actor required another application call to wake");
    drop(reply);
    module.close();
    engine.shutdown();
}

#[test]
fn typed_actor_publishes_complete_rows_and_keeps_proof_scope_on_refusal() {
    let pool = ProcessPool::with_program(1, &program()).unwrap();
    assert_eq!(pool.receipts()[0].processors, 1);
    let owner = pool.owner(0).unwrap();
    let invoke = |request| {
        owner.call_cancelable(request, Limits::default().timeout, &Cancellation::default())
    };
    let source = "(ascent (relation edge (from to)) (relation answer (from to))
        ((answer x z) <-- (edge x y) (edge y z)) (bounds 3 1 4))";
    let handle = invoke(Data::object([
        ("operation", "open-sources".into()),
        ("sources", Data::List(vec![source.into()])),
    ]))
    .unwrap()
    .field("handle")
    .unwrap()
    .clone();
    let query = || {
        invoke(Data::object([
            ("operation", "source-run".into()),
            ("handle", handle.clone()),
            ("queries", Data::List(vec!["answer".into()])),
        ]))
        .unwrap()
    };
    let change = |edges: &[(usize, usize)]| {
        let rows = edges
            .iter()
            .map(|&(a, b)| Data::List(vec![a.into(), b.into()]))
            .collect();
        Data::object([
            ("operation", "source-replace".into()),
            ("handle", handle.clone()),
            (
                "sources",
                Data::List(vec![Data::object([
                    ("relation", "edge".into()),
                    ("rows", Data::List(rows)),
                ])]),
            ),
        ])
    };
    assert_eq!(query().field("complete").unwrap(), &Data::Bool(true));
    invoke(change(&[(0, 1), (1, 2)])).unwrap();
    let answer = query();
    assert_eq!(answer.field("complete").unwrap(), &Data::Bool(true));
    assert_eq!(
        answer.field("scalarProjection").unwrap(),
        &Data::from("supported")
    );
    assert_eq!(
        answer.field("relations").unwrap().field("answer").unwrap(),
        &Data::List(vec![Data::List(vec![0usize.into(), 2usize.into()])]),
    );
    let proof_scope = Data::object([
        ("operation", "owned-result".into()),
        ("handle", handle.clone()),
        ("action", "proof-scope".into()),
        ("relation", "answer".into()),
        ("result", answer.field("resultHandle").unwrap().clone()),
    ]);
    // The Actor rejects at replacement, which would stage a new cut in the
    // ordinary Session. Its last published rows and proof scope are still live.
    assert_eq!(
        invoke(change(&[(0, 1), (1, 2), (2, 3)])),
        Err(Error::DerivedFactLimit),
    );
    assert_eq!(
        invoke(proof_scope.clone())
            .unwrap()
            .field("sourceGeneration")
            .unwrap(),
        &Data::from(1usize),
    );
    invoke(change(&[(8, 9), (9, usize::MAX)])).unwrap();
    assert!(invoke(proof_scope).is_err());
    let next = query();
    assert_eq!(
        next.field("relations").unwrap().field("answer").unwrap(),
        &Data::List(vec![Data::List(vec![8usize.into(), usize::MAX.into()])]),
    );
    invoke(Data::object([
        ("operation", "close".into()),
        ("handle", handle),
    ]))
    .unwrap();
}

#[test]
fn twelve_resident_processes_keep_values_limits_and_cancellation_owner_affine() {
    let pool = ProcessPool::with_program(12, &program()).unwrap();
    let receipts = pool.receipts();
    assert_eq!(receipts.len(), 12);
    assert_eq!(
        receipts
            .iter()
            .map(|v| v.pid)
            .collect::<BTreeSet<_>>()
            .len(),
        12
    );
    assert_eq!(
        receipts
            .iter()
            .map(|v| v.domain)
            .collect::<BTreeSet<_>>()
            .len(),
        12
    );
    assert!(receipts.iter().all(|v| v.processors == 1));
    let modules = prepare_modules(&pool);
    verify_values(&modules);
    verify_running_cancellation(&pool.owner(0).unwrap());
    source_cancellation::verify(&modules[0].0, &pool.owner(0).unwrap());
    std::thread::scope(|scope| {
        for (engine, _) in &modules {
            scope.spawn(move || verify_sources(engine));
        }
    });
    for owner in 0..12 {
        let stats = pool.owner(owner).unwrap().statistics();
        assert!(stats.checkpoints > 0);
        assert!(stats.shared_checkpoints <= stats.checkpoints);
        if ascent_scheme::benchmark::kernel_checkpoint_transport() == "buffered-socket" {
            assert_eq!(stats.shared_checkpoints, 0);
        } else {
            assert!(
                stats.shared_checkpoints > 0,
                "source execution must exercise the shared controller"
            );
        }
    }
    // Same numeric ordinal in another process must never authenticate this owner.
    let owner = modules[0]
        .1
        .call("make-adder", &[], None)
        .unwrap()
        .reference(None)
        .unwrap();
    assert!(
        modules[1]
            .1
            .call("read-marker", &[ObjectInput::Reference(owner)], None)
            .is_err()
    );
    let terminal = modules[11]
        .0
        .load_definitions("(def (stop) (exit 9))")
        .unwrap();
    assert!(terminal.call("stop", &[], None).is_err());
    assert!(
        pool.owner(11)
            .unwrap()
            .call(Data::object([("operation", Data::from("describe"))]))
            .is_err()
    );
    assert!(
        modules[0].1.call("read-marker", &[], None).is_ok(),
        "failed worker cannot revoke a different VM"
    );
    for (engine, module) in modules {
        module.close();
        engine.shutdown();
    }
    drop(pool);
}
fn prepare_modules(pool: &ProcessPool) -> Vec<(Engine, ascent_scheme::Module)> {
    let modules: Vec<_> = (0..12).map(|i| {
        let engine = Engine::new(1).unwrap().on_process(pool.owner(i).unwrap());
        let source = format!("(def marker {i}) (def (read-marker) marker) (def (make-adder) (lambda (x) (+ x marker))) (def (complex) (vector 1/3 'a #\\x)) (def (spin) (let loop ((n 0)) (loop (+ n 1))))");
        let module = engine.load_definitions(&source).unwrap();
        (engine, module)
    }).collect();
    modules
}
fn verify_values(modules: &[(Engine, ascent_scheme::Module)]) {
    for round in 0..3 {
        std::thread::scope(|scope| {
            for (i, (engine, module)) in modules.iter().enumerate() {
                scope.spawn(move || {
                    let value = module.call("read-marker", &[], None).unwrap();
                    assert_eq!(
                        value
                            .graph()
                            .unwrap()
                            .field("root")
                            .unwrap()
                            .field("value")
                            .unwrap(),
                        &Data::from(i.to_string())
                    );
                    let adder = module.call("make-adder", &[], None).unwrap();
                    assert_eq!(
                        adder.reference(None).unwrap().owner % 4_294_967_296,
                        engine.process_receipt().unwrap().domain
                    );
                    let result = adder.apply(&[ObjectInput::Integer(round.into())]).unwrap();
                    assert_eq!(
                        result
                            .graph()
                            .unwrap()
                            .field("root")
                            .unwrap()
                            .field("value")
                            .unwrap(),
                        &Data::from((i + round).to_string())
                    );
                    assert!(
                        format!(
                            "{:?}",
                            module.call("complex", &[], None).unwrap().graph().unwrap()
                        )
                        .contains("1/3")
                    );
                });
            }
        });
    }
}
fn verify_running_cancellation(process: &ascent_scheme::ProcessOwner) {
    let opened = process
        .call_cancelable(
            Data::object([
                ("operation", Data::from("dsl-open")),
                (
                    "source",
                    Data::from("(def (spin) (let loop ((n 0)) (loop (+ n 1))))"),
                ),
                ("trusted", Data::Bool(true)),
            ]),
            Limits::default().timeout,
            &Cancellation::default(),
        )
        .unwrap();
    let interrupted = Cancellation::default();
    let checkpoints = process.statistics().checkpoints;
    std::thread::scope(|scope| {
        let signal = interrupted.clone();
        let owner = process.clone();
        scope.spawn(move || {
            let deadline = std::time::Instant::now() + Duration::from_secs(2);
            while owner.statistics().checkpoints <= checkpoints + 2 {
                assert!(
                    std::time::Instant::now() < deadline,
                    "native call never reached its checkpoints"
                );
                std::thread::yield_now();
            }
            signal.cancel();
        });
        let result = process.call_cancelable(
            Data::object([
                ("operation", Data::from("module-call")),
                ("owner", opened.field("owner").unwrap().clone()),
                ("export", Data::from("spin")),
                ("arguments", Data::List(vec![])),
            ]),
            Limits::default().timeout,
            &interrupted,
        );
        assert_eq!(result, Err(Error::Canceled));
    });
    process
        .call(Data::object([
            ("operation", Data::from("module-close")),
            ("owner", opened.field("owner").unwrap().clone()),
        ]))
        .unwrap();
    assert!(
        process
            .call(Data::object([("operation", Data::from("describe"))]))
            .is_ok()
    );
}
fn verify_sources(engine: &Engine) {
    let source = "(define-program (make) (sources edge) (outputs reach) (relation edge ((a exact-integer?) (b exact-integer?))) (relation reach ((a exact-integer?) (b exact-integer?))) ((reach a b) <-- (edge a b)) ((reach a c) <-- (reach a b) (edge b c)))";
    let module = engine.load_definitions(source).unwrap();
    let value = module.call("make", &[], None).unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    let input = std::collections::BTreeMap::from([(
        "edge".to_owned(),
        vec![
            vec![
                ObjectInput::Integer(0.into()),
                ObjectInput::Integer(1.into()),
            ],
            vec![
                ObjectInput::Integer(1.into()),
                ObjectInput::Integer(2.into()),
            ],
        ],
    )]);
    session
        .replace(input.clone(), &Limits::default(), &Cancellation::default())
        .unwrap();
    verify_provenance(&session, &input);
    let bounded = value
        .open_session(FactLimits {
            input: Some(1),
            ..FactLimits::default()
        })
        .unwrap();
    assert_eq!(
        bounded.replace(input, &Limits::default(), &Cancellation::default()),
        Err(Error::SourceFactLimit)
    );
    bounded.close();
    let canceled = Cancellation::default();
    canceled.cancel();
    assert_eq!(
        session.run(None, &Limits::default(), &canceled),
        Err(Error::Canceled)
    );
    let zero = Limits {
        timeout: Duration::ZERO,
        ..Limits::default()
    };
    assert_eq!(
        session.run(None, &zero, &Cancellation::default()),
        Err(Error::Timeout)
    );
    session.close();
}
fn verify_provenance(
    session: &ascent_scheme::RuleSession,
    input: &std::collections::BTreeMap<String, Vec<Vec<ObjectInput>>>,
) {
    let answer = session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        answer
            .field("relations")
            .unwrap()
            .field("reach")
            .unwrap()
            .list()
            .unwrap()
            .len(),
        3
    );
    let handle = u64::try_from(answer.field("resultHandle").unwrap().index().unwrap()).unwrap();
    let proof_limits = gerbil_ascent::ProvenanceLimits::default();
    let proof = session
        .provenance(handle, "reach", &proof_limits, &Cancellation::default())
        .unwrap();
    let graph = proof.graph().unwrap();
    assert!(
        proof
            .verify(&graph, &proof_limits, &Cancellation::default())
            .unwrap()
    );
    session
        .replace(input.clone(), &Limits::default(), &Cancellation::default())
        .unwrap();
    assert!(
        proof.graph().is_err(),
        "source replacement revokes retained provenance"
    );
}

#[test]
fn pool_drop_preserves_external_engine_and_value_leases() {
    let pool = ProcessPool::with_program(1, &program()).unwrap();
    let engine = Engine::new(1).unwrap().on_process(pool.owner(0).unwrap());
    let receipt = engine.process_receipt().unwrap();
    let module = engine.load_definitions("(def (marker) 42)").unwrap();
    drop(pool);
    let value = module.call("marker", &[], None).unwrap();
    assert_eq!(
        value
            .graph()
            .unwrap()
            .field("root")
            .unwrap()
            .field("value")
            .unwrap(),
        &Data::from("42")
    );
    assert_eq!(engine.process_receipt().unwrap().pid, receipt.pid);
    value.close();
    module.close();
    engine.shutdown();
}
