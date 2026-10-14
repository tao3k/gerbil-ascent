use gerbil_ascent::{Cancellation, Engine, Error, FactLimits, SourceSession, Value};
use std::collections::BTreeMap;
const SOURCE: &str = "(ascent (relation input ((x integer?))) (relation output ((x integer?))) ((output X) <-- (input X) (if (X) (>= X 0))))";
fn update(values: &[i64]) -> BTreeMap<String, Vec<gerbil_ascent::Row>> {
    BTreeMap::from([(
        "input".into(),
        values
            .iter()
            .map(|n| vec![Value::from(*n)].into())
            .collect(),
    )])
}
#[test]
fn source_owners_preserve_occurrence_limits_transactionality_and_generation() {
    let engine = Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 }).unwrap();
    let mut session = engine
        .open_sources(
            &[SOURCE],
            FactLimits {
                input: Some(2),
                ..Default::default()
            },
        )
        .unwrap();
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    assert!(
        session
            .replace(update(&[1]), &limits, &cancellation)
            .is_err()
    );
    let initial = session.run(None, &limits, &cancellation).unwrap();
    assert!(!initial.reused);
    let old = session.result(initial.result_handle).unwrap();
    assert_eq!(
        session.replace(update(&[1, 1, 1]), &limits, &cancellation),
        Err(Error::SourceFactLimit)
    );
    assert_eq!(old.generation().unwrap(), 0);
    assert_eq!(
        session
            .replace(update(&[1, 1]), &limits, &cancellation)
            .unwrap(),
        1
    );
    assert!(old.rows("output").is_err());
    let first = session.run(None, &limits, &cancellation).unwrap();
    assert!(!first.reused);
    assert_eq!(first.source_generation, 1);
    let result = session.result(first.result_handle).unwrap();
    assert_eq!(
        result.rows("output").unwrap(),
        &[vec![Value::from(1)].into()]
    );
    let again = session.run(None, &limits, &cancellation).unwrap();
    assert!(again.reused);
    let bad = BTreeMap::from([
        ("input".into(), vec![vec![Value::from(2)].into()]),
        ("output".into(), vec![vec![Value::from(9)].into()]),
    ]);
    assert!(session.replace(bad, &limits, &cancellation).is_err());
    assert_eq!(result.generation().unwrap(), 1);
    assert_eq!(
        session.run(None, &limits, &cancellation).unwrap().relations,
        first.relations
    );
    session.close();
    session.close();
    assert!(result.rows("input").is_err());
    assert!(session.run(None, &limits, &cancellation).is_err());
}
#[test]
fn source_guard_failures_preserve_existing_result_owners_and_answers() {
    let source = SOURCE.replace("(>= X 0)", "(or X (even? \"bad\"))");
    let mut session = Engine::new(1)
        .unwrap()
        .open_sources(&[&source], FactLimits::default())
        .unwrap();
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    let before = session.run(None, &limits, &cancellation).unwrap();
    let retained = session.result(before.result_handle).unwrap();
    assert!(matches!(
        session.replace(update(&[0]), &limits, &cancellation),
        Err(Error::Evaluation(_))
    ));
    assert_eq!(retained.generation().unwrap(), 0);
    assert_eq!(
        session.run(None, &limits, &cancellation).unwrap().relations,
        before.relations
    );
}
#[test]
fn native_fact_policies_tighten_bounds_and_enforce_output_and_derived_counts() {
    let engine = Engine::new(1).unwrap();
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    let bounded = SOURCE.replace("((output X)", "(bounds 2 4 6) ((output X)");
    let session = engine
        .open_sources(
            &[&bounded],
            FactLimits {
                input: Some(100),
                ..Default::default()
            },
        )
        .unwrap();
    assert_eq!(session.fact_limits().input, Some(2));
    for policy in [
        FactLimits {
            derived: Some(1),
            ..Default::default()
        },
        FactLimits {
            output: Some(3),
            ..Default::default()
        },
    ] {
        let mut session = engine.open_sources(&[SOURCE], policy).unwrap();
        let before = session.run(None, &limits, &cancellation).unwrap();
        assert!(
            session
                .replace(update(&[1, 2]), &limits, &cancellation)
                .is_err()
        );
        assert_eq!(
            session.run(None, &limits, &cancellation).unwrap().relations,
            before.relations
        );
    }
    assert!(
        engine
            .open_sources(
                &[SOURCE],
                FactLimits {
                    input: Some(0),
                    ..Default::default()
                }
            )
            .is_err()
    );
}
#[test]
fn source_results_release_capacity_and_engine_shutdown_invalidates_all_owners() {
    let engine = Engine::new(1).unwrap();
    let mut session = engine
        .open_sources(&[SOURCE], FactLimits::default())
        .unwrap();
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    let handles = (0..64)
        .map(|_| {
            session
                .run(None, &limits, &cancellation)
                .unwrap()
                .result_handle
        })
        .collect::<Vec<_>>();
    assert!(session.run(None, &limits, &cancellation).is_err());
    let result = session.result(handles[0]).unwrap();
    result.close();
    result.close();
    assert!(result.generation().is_err());
    assert!(session.run(None, &limits, &cancellation).is_ok());
    let retained = session.result(handles[1]).unwrap();
    engine.shutdown();
    engine.shutdown();
    assert_eq!(retained.generation(), Err(Error::Closed));
    assert!(session.run(None, &limits, &cancellation).is_err());
    assert!(
        engine
            .open_sources(&[SOURCE], FactLimits::default())
            .is_err()
    );
}
#[test]
fn source_result_scope_does_not_survive_owner_drop_or_accept_unknown_queries() {
    let engine = Engine::new(1).unwrap();
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    let mut session = engine
        .open_sources(&[SOURCE], FactLimits::default())
        .unwrap();
    assert!(
        session
            .run(Some(&["missing".into()]), &limits, &cancellation)
            .is_err()
    );
    assert!(
        session
            .run(
                Some(&["input".into(), "input".into()]),
                &limits,
                &cancellation
            )
            .is_err()
    );
    let first = session.run(None, &limits, &cancellation).unwrap();
    assert_eq!(first.run_index, 1);
    let result = session.result(first.result_handle).unwrap();
    drop(session);
    assert!(result.rows("input").is_err());
}
#[test]
fn column_domains_apply_to_sources_and_derived_rows_without_publishing_failures() {
    use gerbil_ascent::{Atom, Clause, Program, Relation, Rule, Term, Type};
    let mut input = Relation::new("input", vec![Type::Integer], true);
    input.domains[0] = Some([Value::from(1), Value::from(2)].into());
    let mut output = Relation::new("output", vec![Type::Integer], false);
    output.domains[0] = Some([Value::from(2)].into());
    let mut program = Program {
        relation_limit: None,
        relations: vec![input, output],
        ..Program::default()
    };
    program.rules.push(Rule {
        head: Atom::new("output", vec![Term::Variable(0)]),
        body: vec![Clause::positive(Atom::new(
            "input",
            vec![Term::Variable(0)],
        ))],
    });
    for &workers in if cfg!(feature = "rayon") {
        &[1, 2, 4, 8, 12][..]
    } else {
        &[1][..]
    } {
        let mut session = Engine::new(workers)
            .unwrap()
            .open_source_program(program.clone(), FactLimits::default())
            .unwrap();
        let limits = SourceSession::default_limits();
        let cancellation = Cancellation::default();
        session.run(None, &limits, &cancellation).unwrap();
        session
            .replace(update(&[2]), &limits, &cancellation)
            .unwrap();
        let before = session.run(None, &limits, &cancellation).unwrap();
        assert!(
            session
                .replace(update(&[1]), &limits, &cancellation)
                .is_err()
        );
        assert!(
            session
                .replace(update(&[3]), &limits, &cancellation)
                .is_err()
        );
        assert_eq!(
            session.run(None, &limits, &cancellation).unwrap().relations,
            before.relations
        );
        assert_eq!(
            session
                .result(before.result_handle)
                .unwrap()
                .generation()
                .unwrap(),
            1
        );
    }
    program.relations[0].domains[0] = Some([Value::Boolean(true)].into());
    assert!(Engine::new(1).unwrap().open(program).is_err());
}

#[test]
fn native_initial_rows_and_fact_rules_keep_their_distinct_budget_and_authority_contracts() {
    let source = "(ascent (relation fixed ((x integer?)) '((1) (1) (2))) (relation input ((x integer?))) (relation output ((x integer?))) (bounds 4 3 10) ((output X) <-- (fixed X)) ((output X) <-- (input X)) (fact (output 7)))";
    let engine = Engine::new(if cfg!(feature = "rayon") { 4 } else { 1 }).unwrap();
    let mut owner = engine
        .open_sources(&[source], FactLimits::default())
        .unwrap();
    let limits = SourceSession::default_limits();
    let cancellation = Cancellation::default();
    let initial = owner.run(None, &limits, &cancellation).unwrap();
    assert_eq!(initial.relations["fixed"].len(), 2);
    assert_eq!(
        initial.relations["output"],
        vec![
            vec![Value::from(1)].into(),
            vec![Value::from(2)].into(),
            vec![Value::from(7)].into()
        ]
    );
    assert!(
        owner
            .replace(
                BTreeMap::from([("fixed".into(), vec![])]),
                &limits,
                &cancellation
            )
            .is_err()
    );
    owner.replace(update(&[2]), &limits, &cancellation).unwrap();
    let before = owner.run(None, &limits, &cancellation).unwrap();
    assert!(
        owner
            .replace(update(&[2, 2]), &limits, &cancellation)
            .is_err()
    );
    assert!(owner.replace(update(&[8]), &limits, &cancellation).is_err()); // fourth derived tuple exceeds three
    assert_eq!(
        owner.run(None, &limits, &cancellation).unwrap().relations,
        before.relations
    );
    assert!(
        engine
            .open_sources(
                &[source],
                FactLimits {
                    input: Some(2),
                    ..FactLimits::default()
                }
            )
            .is_err()
    );
}
