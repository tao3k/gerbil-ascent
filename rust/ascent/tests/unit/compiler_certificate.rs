//! Actual compiled descriptors and adversarial translation certificates.
use super::check;
use crate::{Clause as Input, Relation, Type};
use crate::{
    Program, Term,
    execution::Pattern,
    graph::{Clause, Graph},
};

fn fixture() -> Graph {
    let atom = |relation, variables: &[u32]| {
        crate::Atom::new(
            relation,
            variables.iter().copied().map(Term::Variable).collect(),
        )
    };
    Graph::build(Program {
        relations: vec![
            Relation::new("e", vec![Type::Integer; 2], true),
            Relation::new("p", vec![Type::Integer; 2], false),
        ],
        rules: vec![crate::Rule {
            head: atom("p", &[40, 71]),
            body: vec![
                Input::positive(atom("e", &[40, 2])),
                Input::positive(atom("e", &[2, 71])),
            ],
        }],
        relation_limit: None,
        fact_limits: crate::FactLimits::default(),
    })
    .unwrap()
}

#[test]
fn actual_positive_descriptors_are_checked_independently() {
    let graph = fixture();
    assert!(check(
        &graph.program,
        &graph.rules,
        &graph.indexes,
        &graph.values
    ));
    let mut corrupt = graph.clone();
    corrupt.rules[0].variables -= 1;
    assert!(!check(
        &corrupt.program,
        &corrupt.rules,
        &corrupt.indexes,
        &corrupt.values
    ));
    let mut corrupt = graph.clone();
    corrupt.rules[0].head.terms = vec![Pattern::Variable(2), Pattern::Variable(0)].into();
    assert!(!check(
        &corrupt.program,
        &corrupt.rules,
        &corrupt.indexes,
        &corrupt.values
    ));
    let mut corrupt = graph.clone();
    corrupt.indexes[0][0] = vec![1];
    assert!(!check(
        &corrupt.program,
        &corrupt.rules,
        &corrupt.indexes,
        &corrupt.values
    ));
    let mut corrupt = graph.clone();
    let Clause::Relation { atom, .. } = &mut corrupt.rules[0].body[1] else {
        unreachable!()
    };
    atom.keys = vec![1];
    assert!(!check(
        &corrupt.program,
        &corrupt.rules,
        &corrupt.indexes,
        &corrupt.values
    ));
}
