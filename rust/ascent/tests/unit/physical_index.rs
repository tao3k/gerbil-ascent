//! Concrete bucket projection, occurrence preservation and set admission.
use super::Index;
use crate::{
    Atom, Clause, FactLimits, Program, Relation, Rule, Term, Type, Value,
    execution::{Bindings, Fact, Values},
    graph::{Clause as CompiledClause, Graph},
};
use std::collections::hash_map::RandomState;

#[test]
fn actual_bucket_build_extend_and_lookup_match_independent_projection() {
    let source = [[1, 2, 3], [1, 2, 3], [4, 2, 5], [1, 6, 3]];
    let additions = [[7, 2, 8], [1, 2, 3]];
    for columns in [vec![], vec![0], vec![1], vec![2, 0], vec![1, 1]] {
        let graph = Graph::build(Program {
            relations: vec![
                Relation::new("e", vec![Type::Integer; 3], true),
                Relation::new("p", vec![Type::Integer], false),
            ],
            rules: vec![Rule {
                head: Atom::new("p", vec![Term::Literal(Value::from(1))]),
                body: vec![Clause::positive(Atom::new(
                    "e",
                    vec![
                        Term::Literal(Value::from(1)),
                        Term::Literal(Value::from(2)),
                        Term::Literal(Value::from(3)),
                    ],
                ))],
            }],
            relation_limit: None,
            fact_limits: FactLimits::default(),
        })
        .unwrap();
        let CompiledClause::Relation { mut atom, .. } = graph.rules[0].body[0].clone() else {
            unreachable!()
        };
        atom.keys = columns.clone();
        atom.index = (!columns.is_empty()).then_some(0);
        let mut values: Values = graph.values;
        let mut index = Index::new(std::slice::from_ref(&columns));
        let encode = |row: &[i32], values: &mut Values| {
            row.iter()
                .map(|v| values.intern(&Value::from(*v)))
                .collect::<Vec<_>>()
                .into()
        };
        for row in &source {
            index.append(encode(row, &mut values));
        }
        let matches = |row: &[i32]| {
            columns
                .iter()
                .all(|column| row[*column] == source[0][*column])
        };
        let expected = |rows: &[[i32; 3]]| {
            rows.iter()
                .filter(|row| matches(*row))
                .map(|row| {
                    row.iter()
                        .map(|v| Value::from(*v))
                        .collect::<Vec<_>>()
                        .into()
                })
                .collect::<Vec<crate::Row>>()
        };
        let decode = |index: &Index, values: &Values| {
            index
                .candidates(&atom, &Bindings::new())
                .iter()
                .map(|row| values.decode(row))
                .collect::<Vec<_>>()
        };
        assert_eq!(decode(&index, &values), expected(&source));
        let before = index.candidates(&atom, &Bindings::new()).to_vec();
        for row in &additions {
            index.append(encode(row, &mut values));
        }
        assert_eq!(
            decode(&index, &values),
            [expected(&source), expected(&additions)].concat()
        );
        assert_eq!(
            before
                .iter()
                .map(|row| values.decode(row))
                .collect::<Vec<_>>(),
            expected(&source)
        );
        let authority = RandomState::new();
        let fact = Fact::new(encode(&source[0], &mut values), &authority);
        let mut set = Index::new(&[columns]);
        assert!(set.insert(fact.clone()));
        assert!(!set.insert(fact));
        assert_eq!(set.rows.len(), 1);
    }
}
