use gerbil_ascent::{
    Cancellation, Engine, Error, FactLimits, ObjectInput as Input, SourceSession, Value,
};
use std::collections::BTreeMap;
const SOURCE: &str = include_str!("../fixtures/evidence-source.ss");
fn number(v: i64) -> Input {
    Input::Integer(v.into())
}
#[test]
fn original_constructor_update_withdrawal_explanation_and_independent_lifetimes() {
    let engine = Engine::new(1).unwrap();
    let module = engine.load_definitions(SOURCE).unwrap();
    let constructor = module
        .call(
            "make-evidence",
            &[Input::List(vec![number(1), number(2)])],
            None,
        )
        .unwrap();
    let session = constructor.open_session(FactLimits::default()).unwrap();
    constructor.close();
    module.close();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let observed = session
        .run(Some(&["output".into()]), &limits, &cancel)
        .unwrap();
    assert_eq!(observed.relations["output"].len(), 2);
    let result = session.result(observed.result_handle).unwrap();
    let explanation = session.explain(observed.result_handle, "output").unwrap();
    result.close();
    assert!(format!("{:?}", explanation.graph().unwrap()).contains("not a per-row proof"));
    explanation.close();
    session
        .replace(
            BTreeMap::from([("input".into(), vec![vec![number(8)]])]),
            &limits,
            &cancel,
        )
        .unwrap();
    let observation = session.run(None, &limits, &cancel).unwrap();
    assert_eq!(
        observation.relations["output"],
        vec![vec![Value::from(8)].into()]
    );
    let retained = session.result(observation.result_handle).unwrap();
    assert!(
        session
            .replace(
                BTreeMap::from([("input".into(), vec![vec![number(1), number(2)]])]),
                &limits,
                &cancel
            )
            .is_err()
    );
    assert_eq!(retained.rows("output").unwrap().len(), 1);
    assert_eq!(
        session.replace(
            BTreeMap::from([("input".into(), vec![vec![number(8)]; 33])]),
            &limits,
            &cancel
        ),
        Err(Error::SourceFactLimit)
    );
    assert_eq!(retained.rows("output").unwrap().len(), 1);
    let canceled = Cancellation::default();
    canceled.cancel();
    assert_eq!(
        session.replace(
            BTreeMap::from([("input".into(), vec![])]),
            &limits,
            &canceled
        ),
        Err(Error::Canceled)
    );
    assert_eq!(retained.rows("output").unwrap().len(), 1);
    session
        .replace(BTreeMap::from([("input".into(), vec![])]), &limits, &cancel)
        .unwrap();
    assert!(retained.rows("output").is_err());
    assert!(session.run(None, &limits, &cancel).unwrap().relations["output"].is_empty());
    session.close();
    assert!(session.run(None, &limits, &cancel).is_err());
}
#[test]
fn cyclic_structural_keys_deduplicate_and_match_through_indexes() {
    let source = r"
      (def (cycle) (let (v (make-vector 1)) (vector-set! v 0 v) v))
      (def (long-cycle) (let* ((a (make-vector 1)) (b (make-vector 1))) (vector-set! a 0 b) (vector-set! b 0 a) a))
      (def (make)
        (let* ((a (cycle)) (b (long-cycle)) (x (gerbil-ascent-variable 'x)))
          (gerbil-ascent-program
            (list (gerbil-ascent-relation 'input 1 (list (list a) (list b) (list (vector 2))))
                  (gerbil-ascent-relation 'wanted 1 (list (list (cycle))))
                  (gerbil-ascent-relation 'output 1 []))
            (list (gerbil-ascent-rule (list (gerbil-ascent-atom 'output (list x)))
                                     (list (gerbil-ascent-atom 'wanted (list x)) (gerbil-ascent-atom 'input (list x)))))
            8 8 8 '(input))))";
    let engine = Engine::new(1).unwrap();
    let module = engine.load_definitions(source).unwrap();
    let session = module
        .call("make", &[], None)
        .unwrap()
        .open_session(FactLimits::default())
        .unwrap();
    let observed = session
        .run(
            None,
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    assert_eq!(observed.relations["input"].len(), 2);
    assert_eq!(observed.relations["output"].len(), 1);
    let row = &observed.relations["output"][0];
    let graph = gerbil_ascent::rows_graph(std::slice::from_ref(row)).unwrap();
    assert!(graph.nodes.values().any(|n| matches!(n, gerbil_ascent::ObjectNode::Vector(items) if items.iter().any(|v| matches!(v,gerbil_ascent::GraphItem::Reference(_))))));
}
#[test]
fn recursive_lattice_replaces_current_rows_and_updates_join_indexes() {
    use gerbil_ascent::{Atom, Clause, LatticeJoin, Program, Relation, Rule, Term, Type};
    let var = |n| Term::Variable(n);
    let mut seed = Relation::new("seed", vec![Type::Integer; 2], true);
    seed.rows = vec![
        vec![0.into(), 9.into()].into(),
        vec![0.into(), 2.into()].into(),
        vec![1.into(), 7.into()].into(),
    ];
    let mut best = Relation::new("best", vec![Type::Integer; 2], false);
    best.lattice = Some(LatticeJoin::Min);
    let mut edge = Relation::new("edge", vec![Type::Integer; 2], true);
    edge.rows = vec![
        vec![0.into(), 1.into()].into(),
        vec![1.into(), 2.into()].into(),
    ];
    let mut rules = vec![
        Rule {
            head: Atom::new("best", vec![var(0), var(1)]),
            body: vec![Clause::positive(Atom::new("seed", vec![var(0), var(1)]))],
        },
        Rule {
            head: Atom::new("best", vec![var(1), var(2)]),
            body: vec![
                Clause::positive(Atom::new("best", vec![var(0), var(2)])),
                Clause::positive(Atom::new("edge", vec![var(0), var(1)])),
            ],
        },
    ];
    let output = Relation::new("output", vec![Type::Integer; 2], false);
    rules.push(Rule {
        head: Atom::new("output", vec![var(0), var(1)]),
        body: vec![Clause::positive(Atom::new("best", vec![var(0), var(1)]))],
    });
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open(Program {
            relation_limit: None,
            relations: vec![seed, best, edge, output],
            rules,
            ..Program::default()
        })
        .unwrap();
    let result = session
        .run(&SourceSession::default_limits(), &Cancellation::default())
        .unwrap();
    assert_eq!(
        result.relations["best"],
        vec![
            vec![0.into(), 2.into()].into(),
            vec![1.into(), 2.into()].into(),
            vec![2.into(), 2.into()].into()
        ]
    );
    assert_eq!(result.relations["output"], result.relations["best"]);
    session
        .replace_sources(BTreeMap::from([(
            "seed".into(),
            vec![vec![0.into(), 11.into()].into()],
        )]))
        .unwrap();
    assert_eq!(
        session
            .run(&SourceSession::default_limits(), &Cancellation::default())
            .unwrap()
            .relations["best"],
        vec![
            vec![0.into(), 11.into()].into(),
            vec![1.into(), 11.into()].into(),
            vec![2.into(), 11.into()].into()
        ]
    );
}

#[test]
fn original_graph_constructor_preserves_opaque_references_and_original_lattice_matches_scheme() {
    let engine = Engine::new(1).unwrap();
    let source = format!(
        "{SOURCE}\n{}\n{}",
        include_str!("../fixtures/constructor-lattice.ss"),
        include_str!("../fixtures/constructor-graph-values.ss")
    );
    let module = engine.load_definitions(&source).unwrap();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let evidence = module
        .call(
            "make-evidence",
            &[Input::List(vec![number(1), number(2), number(1)])],
            None,
        )
        .unwrap()
        .open_session(FactLimits::default())
        .unwrap();
    let count = evidence.run(None, &limits, &cancel).unwrap().relations["output"].len();
    let lattice = module
        .call(
            "make-lattice",
            &[Input::List(vec![
                Input::List(vec![number(0), number(9)]),
                Input::List(vec![number(0), number(2)]),
                Input::List(vec![number(1), number(7)]),
            ])],
            None,
        )
        .unwrap()
        .open_session(FactLimits::default())
        .unwrap();
    let best = lattice.run(None, &limits, &cancel).unwrap().relations["best"].clone();
    assert_eq!(
        best,
        vec![
            vec![0.into(), 2.into()].into(),
            vec![1.into(), 7.into()].into()
        ]
    );
    let graph = module
        .call("make-graph-values", &[], None)
        .unwrap()
        .open_session(FactLimits::default())
        .unwrap();
    module.close();
    let observed = graph.run(None, &limits, &cancel).unwrap();
    let rows = &observed.relations["input"];
    assert_eq!(rows.len(), 8);
    let result = graph.result(observed.result_handle).unwrap();
    let opaque=rows.iter().position(|r| matches!(&r[0],Value::Object(v) if v.graph().nodes.values().any(|n| matches!(n,gerbil_ascent::ObjectNode::Opaque(_))))).unwrap();
    let reference = result.value("input", opaque, 0).unwrap();
    graph
        .replace(
            BTreeMap::from([(
                "input".into(),
                vec![vec![Input::ResultValue(reference.clone())]],
            )]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert!(reference.value().is_err());
    assert!(
        graph
            .replace(
                BTreeMap::from([("input".into(), vec![vec![Input::ResultValue(reference)]])]),
                &limits,
                &cancel
            )
            .is_err()
    );
    let next = graph.run(None, &limits, &cancel).unwrap();
    assert_eq!(next.relations["input"].len(), 1);
    let fallback = graph.explain(next.result_handle, "input").unwrap();
    assert!(format!("{:?}", fallback.graph().unwrap()).contains("unsupported"));
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let oracle = std::process::Command::new("gxi")
        .arg(root.join("tests/fixtures/constructor-oracle.ss"))
        .env("GERBIL_PATH", root.join("../../.gerbil"))
        .output()
        .unwrap();
    assert!(
        oracle.status.success(),
        "{}",
        String::from_utf8_lossy(&oracle.stderr)
    );
    assert_eq!(
        String::from_utf8(oracle.stdout).unwrap(),
        format!("{count}\n{}\n#t\n{}\n", best.len(), rows.len())
    );
}

#[test]
fn session_and_explanation_slots_release_without_revoking_independent_observations() {
    let engine = Engine::new(1).unwrap();
    let module = engine.load_definitions(SOURCE).unwrap();
    let constructor = module
        .call("make-evidence", &[Input::List(vec![number(1)])], None)
        .unwrap();
    let mut sessions = (0..64)
        .map(|_| constructor.open_session(FactLimits::default()).unwrap())
        .collect::<Vec<_>>();
    assert!(constructor.open_session(FactLimits::default()).is_err());
    sessions.pop().unwrap().close();
    let session = constructor.open_session(FactLimits::default()).unwrap();
    let observed = session
        .run(
            None,
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    let result = session.result(observed.result_handle).unwrap();
    assert_eq!(result.rows("output").unwrap().len(), 1);
    for _ in 0..70 {
        let explanation = session.explain(observed.result_handle, "output").unwrap();
        explanation.close();
    }
    let proofs = (0..63)
        .map(|_| session.explain(observed.result_handle, "output").unwrap())
        .collect::<Vec<_>>();
    assert!(session.explain(observed.result_handle, "output").is_err());
    drop(proofs);
    let stale = session.explain(observed.result_handle, "output").unwrap();
    session
        .replace(
            BTreeMap::from([("input".into(), vec![vec![number(2)]])]),
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    assert!(stale.graph().is_ok());
    assert!(!stale.is_current());
    let observed = session
        .run(
            None,
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )
        .unwrap();
    let result = session.result(observed.result_handle).unwrap();
    assert_eq!(result.rows("output").unwrap().len(), 1);
    session.close();
    assert!(result.rows("output").is_err());
    assert!(constructor.open_session(FactLimits::default()).is_ok());
}

#[test]
fn complex_cells_cross_parallel_binding_and_publication_without_host_calls() {
    let source = SOURCE.replace("32 64 96", "8192 8192 16384");
    let workers = if cfg!(feature = "rayon") {
        vec![1, 4, 8]
    } else {
        vec![1]
    };
    for workers in workers {
        let engine = Engine::new(workers).unwrap();
        let module = engine.load_definitions(&source).unwrap();
        let mut values = (0..3000)
            .map(|n| Input::Vector(vec![number(n)]))
            .collect::<Vec<_>>();
        values.push(Input::Vector(vec![number(1)]));
        let session = module
            .call("make-evidence", &[Input::List(values)], None)
            .unwrap()
            .open_session(FactLimits::default())
            .unwrap();
        module.close();
        let observed = session
            .run(
                None,
                &SourceSession::default_limits(),
                &Cancellation::default(),
            )
            .unwrap();
        assert_eq!(observed.relations["output"].len(), 3000);
        assert_eq!(observed.relations["input"], observed.relations["output"]);
    }
}

#[test]
fn historical_explanation_is_readable_but_loses_current_source_authority() {
    let engine = Engine::new(1).unwrap();
    let module = engine.load_definitions(SOURCE).unwrap();
    let value = module
        .call("make-evidence", &[Input::List(vec![number(1)])], None)
        .unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    let receipt = session
        .run(Some(&["output".into()]), &limits, &cancel)
        .unwrap();
    let result = session.result(receipt.result_handle).unwrap();
    let explanation = session.explain(receipt.result_handle, "output").unwrap();
    let original = explanation.graph().unwrap();
    result.close();
    assert!(explanation.is_current());
    assert_eq!(explanation.source_generation(), 0);
    session
        .replace(
            BTreeMap::from([("input".into(), vec![vec![number(2)]])]),
            &limits,
            &cancel,
        )
        .unwrap();
    assert!(!explanation.is_current());
    assert!(std::sync::Arc::ptr_eq(
        &original,
        &explanation.graph().unwrap()
    ));
    explanation.close();
    assert!(explanation.graph().is_err());
    assert!(!explanation.is_current());
}
