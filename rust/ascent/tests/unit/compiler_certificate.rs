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

#[test]
fn generated_term_decoder_keeps_constructors_and_head_scope() {
    use crate::graph::descriptor_stream::check_terms;
    use crate::Value;
    use std::collections::HashMap;

    let mut values = crate::execution::Values::default();
    let seven = values.intern(&Value::from(7_i64));
    let eight = values.intern(&Value::from(8_i64));
    let mut names = HashMap::new();
    let terms = [
        Term::Variable(40),
        Term::Variable(40),
        Term::Literal(Value::from(7_i64)),
        Term::Wildcard,
    ];
    assert!(check_terms(
        &terms,
        &[
            Pattern::Variable(0),
            Pattern::Variable(0),
            Pattern::Literal(seven),
            Pattern::Wildcard
        ],
        &values,
        &mut names,
        false,
    ));
    assert_eq!(names.get(&40), Some(&0));
    for pattern in [
        Pattern::Variable(0),
        Pattern::Literal(eight),
        Pattern::Wildcard,
    ] {
        assert!(!check_terms(
            &[Term::Literal(Value::from(7_i64))],
            &[pattern],
            &values,
            &mut names,
            false
        ));
    }
    assert!(!check_terms(
        &[Term::Wildcard],
        &[Pattern::Variable(0)],
        &values,
        &mut names,
        false
    ));
    assert!(!check_terms(
        &[Term::Variable(71)],
        &[Pattern::Variable(1)],
        &values,
        &mut names,
        true
    ));
    assert!(!names.contains_key(&71));
    assert!(check_terms(
        &[Term::Variable(40)],
        &[Pattern::Variable(0)],
        &values,
        &mut names,
        true
    ));
    assert!(!check_terms(
        &[Term::Variable(40)],
        &[],
        &values,
        &mut names,
        false
    ));
}
