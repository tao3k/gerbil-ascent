use gerbil_ascent::{
    Cancellation, Engine, Error, FactLimits, ProvenanceLimits, ProvenanceStatus, SourceSession,
};
use std::{collections::BTreeMap, time::Duration};
const GRAPH: &str = "(ascent (relation edge ((x integer?) (y integer?))) (relation path ((x integer?) (y integer?))) ((path x y) <-- (edge x y)) ((path x z) <-- (path x y) (edge y z)))";
#[test]
fn independent_positive_graph_retains_recursive_alternatives_and_rejects_tampering() {
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_sources(&[GRAPH], FactLimits::default())
        .unwrap();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    session.run(None, &limits, &cancel).unwrap();
    session
        .replace(
            BTreeMap::from([(
                "edge".into(),
                vec![
                    vec![1.into(), 2.into()].into(),
                    vec![2.into(), 1.into()].into(),
                    vec![2.into(), 3.into()].into(),
                ],
            )]),
            &limits,
            &cancel,
        )
        .unwrap();
    let observed = session.run(None, &limits, &cancel).unwrap();
    let result = session.result(observed.result_handle).unwrap();
    let proof = session
        .provenance(
            observed.result_handle,
            "path",
            &ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    let graph = proof.graph().unwrap();
    assert_eq!(graph.status, ProvenanceStatus::Complete);
    assert_eq!(graph.roots.len(), 6);
    assert!(
        graph
            .edges
            .iter()
            .any(|e| e.inputs.iter().any(|id| *id >= e.output))
    );
    assert!(
        proof
            .verify(&graph, &ProvenanceLimits::default(), &cancel)
            .unwrap()
    );
    let mut forged = (*graph).clone();
    forged.edges.pop();
    assert!(
        !proof
            .verify(&forged, &ProvenanceLimits::default(), &cancel)
            .unwrap()
    );
    let mut forged = (*graph).clone();
    forged.generation += 1;
    assert!(
        !proof
            .verify(&forged, &ProvenanceLimits::default(), &cancel)
            .unwrap()
    );
    let mut foreign = (*graph).clone();
    foreign.source_identity += 1;
    assert!(
        !proof
            .verify(&foreign, &ProvenanceLimits::default(), &cancel)
            .unwrap()
    );
    result.close();
    assert_eq!(proof.graph().unwrap().status, ProvenanceStatus::Complete);
    let canceled = Cancellation::default();
    canceled.cancel();
    assert_eq!(
        proof.verify(&graph, &ProvenanceLimits::default(), &canceled),
        Err(Error::Canceled)
    );
    session
        .replace(BTreeMap::from([("edge".into(), vec![])]), &limits, &cancel)
        .unwrap();
    assert!(proof.graph().is_err());
}
#[test]
fn replay_bounds_publish_no_partial_nodes_edges_or_roots_and_absence_is_closed() {
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_sources(&[GRAPH], FactLimits::default())
        .unwrap();
    let cancel = Cancellation::default();
    let limits = SourceSession::default_limits();
    let observed = session.run(None, &limits, &cancel).unwrap();
    let absent = session
        .provenance(
            observed.result_handle,
            "path",
            &ProvenanceLimits::default(),
            &cancel,
        )
        .unwrap();
    assert_eq!(
        absent.graph().unwrap().status,
        ProvenanceStatus::ClosedAbsent
    );
    session
        .replace(
            BTreeMap::from([("edge".into(), vec![vec![1.into(), 2.into()].into()])]),
            &limits,
            &cancel,
        )
        .unwrap();
    let observed = session.run(None, &limits, &cancel).unwrap();
    for bounded in [
        ProvenanceLimits {
            max_steps: 1,
            ..Default::default()
        },
        ProvenanceLimits {
            max_nodes: 1,
            ..Default::default()
        },
        ProvenanceLimits {
            max_edges: 1,
            ..Default::default()
        },
        ProvenanceLimits {
            timeout: Duration::ZERO,
            ..Default::default()
        },
    ] {
        let proof = session
            .provenance(observed.result_handle, "path", &bounded, &cancel)
            .unwrap();
        let graph = proof.graph().unwrap();
        assert_eq!(graph.status, ProvenanceStatus::Bounded);
        assert!(graph.nodes.is_empty() && graph.edges.is_empty() && graph.roots.is_empty());
        assert!(
            !proof
                .verify(&graph, &ProvenanceLimits::default(), &cancel)
                .unwrap()
        );
    }
}

#[test]
fn stratified_negation_scalar_and_grouped_reductions_have_checked_witnesses() {
    use gerbil_ascent::ProvenanceWitness;
    let workers: &[usize] = if cfg!(feature = "rayon") {
        &[1, 4]
    } else {
        &[1]
    };
    for &threads in workers {
        for reducer in ["count", "sum", "min", "max"] {
            let mut session = stratified_session(threads, reducer);
            let limits = SourceSession::default_limits();
            let cancel = Cancellation::default();
            let observed = session.run(None, &limits, &cancel).unwrap();
            assert_eq!(observed.relations["kept"], vec![vec![1.into()].into()]);
            let proof = session
                .provenance(
                    observed.result_handle,
                    "kept",
                    &ProvenanceLimits::default(),
                    &cancel,
                )
                .unwrap();
            let graph = proof.graph().unwrap();
            assert_eq!(graph.checker_version, 3);
            assert_eq!(graph.status, ProvenanceStatus::Complete);
            assert!(
                proof
                    .verify(&graph, &ProvenanceLimits::default(), &cancel)
                    .unwrap()
            );
            let factors = &graph
                .edges
                .iter()
                .find(|e| e.rule == Some(0))
                .unwrap()
                .witnesses;
            assert!(matches!(
                factors.as_slice(),
                [
                    ProvenanceWitness::Absent(_),
                    ProvenanceWitness::Guard(_),
                    ProvenanceWitness::Compute { .. }
                ]
            ));
            let aggregate = session
                .provenance(
                    observed.result_handle,
                    "out",
                    &ProvenanceLimits::default(),
                    &cancel,
                )
                .unwrap();
            let graph = aggregate.graph().unwrap();
            assert!(
                aggregate
                    .verify(&graph, &ProvenanceLimits::default(), &cancel)
                    .unwrap()
            );
            let counts = graph
                .edges
                .iter()
                .flat_map(|e| &e.witnesses)
                .filter_map(|w| match w {
                    ProvenanceWitness::Aggregate { rows, .. } => Some(rows.len()),
                    _ => None,
                })
                .collect::<Vec<_>>();
            assert_eq!(
                counts,
                if matches!(reducer, "count" | "sum") {
                    vec![2, 0]
                } else {
                    vec![2]
                }
            );
            let mut forged = (*graph).clone();
            let edge = forged
                .edges
                .iter_mut()
                .find(|e| !e.witnesses.is_empty())
                .unwrap();
            edge.witnesses.clear();
            assert!(
                !aggregate
                    .verify(&forged, &ProvenanceLimits::default(), &cancel)
                    .unwrap()
            );
            session
                .replace(
                    BTreeMap::from([("blocked".into(), vec![vec![0.into()].into()])]),
                    &limits,
                    &cancel,
                )
                .unwrap();
            assert!(proof.graph().is_err());
            assert!(aggregate.graph().is_err());
        }
    }
}

fn stratified_session(threads: usize, reducer: &str) -> SourceSession {
    use gerbil_ascent::Value;
    let inputs = if reducer == "count" { "" } else { "Y" };
    let dsl = format!(
        "(ascent (relation input ((x integer?))) (relation blocked ((x integer?))) (relation kept ((x integer?))) (relation group ((g symbol?))) (relation n ((g symbol?) (v integer?))) (relation out ((g symbol?) (v integer?))) ((kept Y) <-- (input X) (not (blocked X)) (if (X) (and (even? X) (or #t (even? \"unreachable\")))) (let Y (X) (+ X 1))) ((out G T) <-- (group G) (aggregate T gerbil-ascent-{reducer} ({inputs}) (n G Y))))"
    );
    let engine = Engine::new(threads).unwrap();
    let mut session = engine.open_sources(&[&dsl], FactLimits::default()).unwrap();
    let limits = SourceSession::default_limits();
    let cancel = Cancellation::default();
    session.run(None, &limits, &cancel).unwrap();
    session
        .replace(
            BTreeMap::from([
                (
                    "input".into(),
                    [0, 2, 3].map(|n| vec![n.into()].into()).to_vec(),
                ),
                ("blocked".into(), vec![vec![2.into()].into()]),
                (
                    "group".into(),
                    ["a", "empty"]
                        .map(|s| vec![Value::Symbol(s.into())].into())
                        .to_vec(),
                ),
                (
                    "n".into(),
                    [2, 5]
                        .map(|n| vec![Value::Symbol("a".into()), n.into()].into())
                        .to_vec(),
                ),
            ]),
            &limits,
            &cancel,
        )
        .unwrap();
    session
}

#[test]
fn replay_charges_integer_magnitude_before_computation_and_does_not_publish_partial_factors() {
    let dsl = "(ascent (relation input ((x integer?))) (relation out ((x integer?))) ((out Y) <-- (input X) (let Y (X) (* X X))))";
    let engine = Engine::new(1).unwrap();
    let mut session = engine.open_sources(&[dsl], FactLimits::default()).unwrap();
    let cancel = Cancellation::default();
    let limits = SourceSession::default_limits();
    session.run(None, &limits, &cancel).unwrap();
    let huge = num_bigint::BigInt::from(1) << 4096;
    session
        .replace(
            BTreeMap::from([(
                "input".into(),
                vec![vec![gerbil_ascent::Value::from(huge)].into()],
            )]),
            &limits,
            &cancel,
        )
        .unwrap();
    let result = session.run(None, &limits, &cancel).unwrap();
    let proof = session
        .provenance(
            result.result_handle,
            "out",
            &ProvenanceLimits {
                max_steps: 100,
                ..Default::default()
            },
            &cancel,
        )
        .unwrap();
    let graph = proof.graph().unwrap();
    assert_eq!(graph.status, ProvenanceStatus::Bounded);
    assert!(graph.nodes.is_empty() && graph.edges.is_empty() && graph.roots.is_empty());
}
