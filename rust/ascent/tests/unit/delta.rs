//! Independent, deliberately naive Horn-clause oracle. It shares no matcher,
//! indexes, scheduling, delta selection or SCC implementation with execution.
use super::{Budget, Cancellation, Graph, Limits, evaluate_budgeted};
use crate::{Atom as DeclAtom, Clause as DeclClause, Engine, Program, Relation, Term, Type, Value};
use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::Ordering;

type Database = BTreeMap<String, BTreeSet<crate::Row>>;
fn atom(name: &str, variables: &[u32]) -> DeclAtom {
    DeclAtom::new(
        name,
        variables.iter().copied().map(Term::Variable).collect(),
    )
}
fn rule(head: (&str, &[u32]), body: &[(&str, &[u32])]) -> crate::Rule {
    crate::Rule {
        head: atom(head.0, head.1),
        body: body
            .iter()
            .map(|(n, v)| DeclClause::positive(atom(n, v)))
            .collect(),
    }
}
fn program(reverse: bool) -> Program {
    let mut rules = vec![
        rule(("p", &[0, 2]), &[("q", &[0, 1]), ("q", &[1, 2])]),
        rule(("q", &[0, 1]), &[("p", &[0, 1])]),
        rule(("p", &[0, 1]), &[("edge", &[0, 1])]),
    ];
    if reverse {
        rules.reverse();
    }
    Program {
        relations: ["edge", "p", "q"]
            .iter()
            .map(|n| Relation::new(*n, vec![Type::Integer; 2], *n == "edge"))
            .collect(),
        rules,
        relation_limit: None,
        fact_limits: crate::FactLimits::default(),
    }
}
fn input(mask: usize, nodes: i32) -> Vec<crate::Row> {
    (0..nodes)
        .flat_map(|a| (0..nodes).map(move |b| (a, b)))
        .enumerate()
        .filter(|(i, _)| mask & (1 << i) != 0)
        .map(|(_, (a, b))| vec![Value::from(a), Value::from(b)].into())
        .collect()
}
fn naive(program: &Program, edges: &[crate::Row]) -> (Database, usize, usize) {
    let mut db: Database = program
        .relations
        .iter()
        .map(|r| (r.name.clone(), BTreeSet::new()))
        .collect();
    db.get_mut("edge").unwrap().extend(edges.iter().cloned());
    let mut witnesses = 0;
    let mut matches = 0;
    loop {
        let mut next = db.clone();
        for rule in &program.rules {
            let mut bindings = vec![BTreeMap::<u32, Value>::new()];
            for clause in &rule.body {
                let DeclClause::Relation {
                    atom,
                    negative: false,
                } = clause
                else {
                    panic!("positive oracle subset")
                };
                let mut expanded = Vec::new();
                for binding in &bindings {
                    for row in &db[&atom.relation] {
                        let mut candidate = binding.clone();
                        let valid =
                            atom.terms
                                .iter()
                                .zip(row.iter())
                                .all(|(term, value)| match term {
                                    Term::Variable(v) => {
                                        if let Some(prior) = candidate.get(v) {
                                            prior == value
                                        } else {
                                            candidate.insert(*v, value.clone());
                                            true
                                        }
                                    }
                                    Term::Literal(v) => v == value,
                                    Term::Wildcard => true,
                                });
                        if valid {
                            matches += 1;
                            expanded.push(candidate);
                        }
                    }
                }
                bindings = expanded;
            }
            witnesses += bindings.len();
            for binding in bindings {
                let row: crate::Row = rule
                    .head
                    .terms
                    .iter()
                    .map(|t| match t {
                        Term::Variable(v) => binding[v].clone(),
                        Term::Literal(v) => v.clone(),
                        Term::Wildcard => panic!("head wildcard"),
                    })
                    .collect::<Vec<_>>()
                    .into();
                next.get_mut(&rule.head.relation).unwrap().insert(row);
            }
        }
        if next == db {
            return (db, witnesses, matches);
        }
        db = next;
    }
}
fn compare(mask: usize, reverse: bool, threads: usize) {
    let declaration = program(reverse);
    let edges = input(mask, 3);
    let (expected, _, _) = naive(&declaration, &edges);
    let engine = if threads == 0 {
        Engine::serial().unwrap()
    } else {
        Engine::new(threads).unwrap()
    };
    let mut session = engine.open(declaration).unwrap();
    session.replace("edge", edges).unwrap();
    let snapshot = session
        .run(&Limits::default(), &Cancellation::default())
        .unwrap();
    for (relation, rows) in expected {
        assert_eq!(
            snapshot.relations[&relation]
                .iter()
                .cloned()
                .collect::<BTreeSet<_>>(),
            rows,
            "mask={mask} reverse={reverse} threads={threads} relation={relation}"
        );
    }
}
#[test]
fn delta_exhaustive_nonlinear_mutual_recursion_matches_independent_naive() {
    for mask in 0..512 {
        for reverse in [false, true] {
            compare(mask, reverse, 0);
        }
    }
    #[cfg(feature = "rayon")]
    for threads in [1, 2, 4] {
        for mask in 0..512 {
            for reverse in [false, true] {
                compare(mask, reverse, threads);
            }
        }
    }
}
#[test]
fn delta_actual_kernel_witness_counts_exclude_all_old_and_duplicate_fresh_joins() {
    let declaration = program(false);
    let edges = input(0b0_1010_0010, 3);
    let (expected, naive_witnesses, naive_matches) = naive(&declaration, &edges);
    let graph = Graph::build(declaration).unwrap();
    for parallel in [false, true] {
        let sources = vec![edges.clone(), vec![], vec![]];
        let budget = Budget::new(
            &Limits::default(),
            &Cancellation::default(),
            3,
            crate::FactLimits::default(),
            None,
        );
        let actual = evaluate_budgeted(&graph, &sources, &budget, parallel).unwrap();
        for (i, relation) in ["edge", "p", "q"].iter().enumerate() {
            assert_eq!(
                actual[i].iter().cloned().collect::<BTreeSet<_>>(),
                expected[*relation]
            );
        }
        let witnesses = budget.witnesses.load(Ordering::Relaxed);
        // Every q/q pair is owned by exactly one fresh occurrence over the
        // solve, not merely deduplicated at the rule head.
        let q = &expected["q"];
        let pairs = q
            .iter()
            .flat_map(|a| q.iter().map(move |b| (a, b)))
            .filter(|(a, b)| a[1] == b[0])
            .count();
        assert_eq!(witnesses, edges.len() + q.len() + pairs);
        assert!(witnesses < naive_witnesses);
        assert!(budget.matches.load(Ordering::Relaxed) < naive_matches);
        eprintln!(
            "DELTA-COUNTS parallel={parallel} matched={} witnesses={witnesses} naive_witnesses={naive_witnesses} naive_matched={naive_matches}",
            budget.matches.load(Ordering::Relaxed)
        );
    }
}

#[test]
fn delta_provenance_retains_alternatives_discovered_after_the_head_fact() {
    const SOURCE: &str = "(ascent (relation edge ((x integer?) (y integer?))) (relation p ((x integer?) (y integer?))) (relation q ((x integer?) (y integer?))) ((p x z) <-- (q x y) (q y z)) ((q x y) <-- (p x y)) ((p x y) <-- (edge x y)))";
    let edges = input(0b0_1010_0010, 3);
    let (expected, _, _) = naive(&program(false), &edges);
    let q = &expected["q"];
    let alternatives = q
        .iter()
        .flat_map(|a| q.iter().map(move |b| (a, b)))
        .filter(|(a, b)| a[1] == b[0])
        .count();
    let threads = if cfg!(feature = "rayon") { 4 } else { 1 };
    for engine in [Engine::serial().unwrap(), Engine::new(threads).unwrap()] {
        let mut session = engine
            .open_sources(&[SOURCE], crate::FactLimits::default())
            .unwrap();
        let limits = crate::SourceSession::default_limits();
        let cancel = Cancellation::default();
        session.run(None, &limits, &cancel).unwrap();
        session
            .replace(
                BTreeMap::from([("edge".into(), edges.clone())]),
                &limits,
                &cancel,
            )
            .unwrap();
        let result = session.run(None, &limits, &cancel).unwrap();
        let proof_limits = crate::ProvenanceLimits::default();
        let proof = session
            .provenance(result.result_handle, "q", &proof_limits, &cancel)
            .unwrap();
        let graph = proof.graph().unwrap();
        assert_eq!(graph.status, crate::ProvenanceStatus::Complete);
        assert_eq!(graph.roots.len(), q.len());
        assert_eq!(
            graph
                .edges
                .iter()
                .filter(|edge| edge.rule == Some(0))
                .count(),
            alternatives
        );
        assert!(proof.verify(&graph, &proof_limits, &cancel).unwrap());
        let mut missing = (*graph).clone();
        let index = missing
            .edges
            .iter()
            .position(|edge| edge.rule == Some(0))
            .unwrap();
        missing.edges.remove(index);
        assert!(!proof.verify(&missing, &proof_limits, &cancel).unwrap());
    }
}
