use super::compare;
use crate::{
    Atom, Cancellation, Clause, Engine, FactLimits, Limits, Program, Relation, Rule, Term, Type,
    Value, execution::Values,
};
use std::{collections::BTreeSet, sync::Arc};

fn complex_values() -> Vec<Value> {
    use crate::{FrozenValue, GraphItem, ObjectGraph, ObjectNode};
    use std::collections::BTreeMap;
    [
        ObjectNode::Vector(vec![GraphItem::Reference(0)]),
        ObjectNode::Vector(vec![GraphItem::Number("1".into())]),
        ObjectNode::Opaque("same".into()),
        ObjectNode::Symbol {
            name: "same".into(),
            interned: false,
        },
    ]
    .into_iter()
    .enumerate()
    .map(|(id, node)| {
        Value::Object(
            FrozenValue::new(
                7,
                id as u64,
                ObjectGraph {
                    root: GraphItem::Reference(0),
                    nodes: Arc::new(BTreeMap::from([(0, node)])),
                },
            )
            .unwrap(),
        )
    })
    .collect()
}

#[test]
fn actual_rank_comparator_matches_value_order_for_all_variants_and_tuple_prefixes() {
    let mut values = Values::default();
    let mut scalars: Vec<_> = (-32..32).rev().map(Value::from).collect();
    scalars.extend([
        Value::Symbol("z".into()),
        Value::Text("a".into()),
        Value::Boolean(true),
        Value::Boolean(false),
        Value::number("3/2").unwrap(),
        Value::number("1.5").unwrap(),
        Value::number("+nan.0").unwrap(),
    ]);
    scalars.extend(complex_values());
    let cells: Vec<_> = scalars.iter().map(|v| values.intern(v)).collect();
    let ranks = super::ranks(&values);
    let rows: Vec<super::Row> = (0..cells.len() * 3)
        .map(|i| {
            (0..i % 4)
                .map(|j| cells[(i * 17 + j * 13) % cells.len()])
                .collect::<Vec<_>>()
                .into()
        })
        .collect();
    for a in &rows {
        for b in &rows {
            assert_eq!(
                compare(a, b, &ranks),
                values.decode(a).cmp(&values.decode(b))
            );
        }
    }
    let mut ranked = rows.clone();
    ranked.sort_unstable_by(|a, b| compare(a, b, &ranks));
    let actual: Vec<_> = ranked.iter().map(|row| values.decode(row)).collect();
    let mut expected: Vec<_> = rows.iter().map(|row| values.decode(row)).collect();
    expected.sort_unstable();
    assert_eq!(actual, expected);
}

fn projection() -> Program {
    let mut source = Relation::new("e", vec![Type::Any; 2], true);
    source.initial_occurrences = true;
    Program {
        relations: vec![source, Relation::new("p", vec![Type::Any; 2], false)],
        rules: vec![Rule {
            head: Atom::new("p", vec![Term::Variable(1), Term::Variable(0)]),
            body: vec![Clause::positive(Atom::new(
                "e",
                vec![Term::Variable(0), Term::Variable(1)],
            ))],
        }],
        relation_limit: None,
        fact_limits: FactLimits::default(),
    }
}

#[test]
fn ranked_large_publication_matches_full_value_sort_and_preserves_source_occurrences() {
    for threads in [1, if cfg!(feature = "rayon") { 12 } else { 1 }] {
        let mut palette: Vec<_> = (0..100).rev().map(Value::from).collect();
        palette.extend(complex_values());
        let width = palette.len();
        let rows: Vec<crate::Row> = (0..width * width + 500)
            .rev()
            .map(|n| {
                Arc::from([
                    palette[n % width].clone(),
                    palette[(n / width) % width].clone(),
                ])
            })
            .collect();
        let mut session = Engine::new(threads).unwrap().open(projection()).unwrap();
        session.replace("e", rows.clone()).unwrap();
        let snapshot = session
            .run(&Limits::default(), &Cancellation::default())
            .unwrap();
        let mut expected_source = rows.clone();
        expected_source.sort_unstable();
        let expected: Vec<crate::Row> = rows
            .iter()
            .map(|row| Arc::from([row[1].clone(), row[0].clone()]))
            .collect::<BTreeSet<_>>()
            .into_iter()
            .collect();
        assert_eq!(snapshot.relations["e"], expected_source);
        assert!(
            snapshot.relations["e"]
                .iter()
                .zip(&expected_source)
                .all(|(a, b)| Arc::ptr_eq(a, b))
        );
        assert_eq!(snapshot.relations["p"], expected);
        assert!(Arc::ptr_eq(
            &snapshot,
            &session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap()
        ));
        session.replace("e", vec![]).unwrap();
        assert_eq!(
            session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap()
                .relations["p"],
            [] as [crate::Row; 0]
        );
        assert_eq!(snapshot.relations["p"], expected);
    }
}

#[test]
fn large_publication_keeps_original_fact_state_timeout_and_cancellation_failures() {
    let rows: Vec<crate::Row> = (0..10_000)
        .map(|n| Arc::from([Value::from(n % 100), Value::from(n / 100)]))
        .collect();
    for case in 0..4 {
        let mut session = Engine::new(1).unwrap().open(projection()).unwrap();
        session.replace("e", rows.clone()).unwrap();
        let mut limits = Limits::default();
        let canceled = Cancellation::default();
        let expected = match case {
            0 => {
                limits.max_facts = 10_001;
                crate::Error::FactLimit
            }
            1 => {
                limits.max_states = 1;
                crate::Error::StateLimit
            }
            2 => {
                limits.timeout = std::time::Duration::ZERO;
                crate::Error::Timeout
            }
            _ => {
                canceled.cancel();
                crate::Error::Canceled
            }
        };
        assert_eq!(session.run(&limits, &canceled).unwrap_err(), expected);
    }
}
