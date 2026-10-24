use super::{Fact, FactSet};
use crate::{Value, execution::Values};

#[test]
fn digest_collisions_retain_full_typed_equality() {
    let mut values = Values::default();
    let mut facts = FactSet::default();
    for value in [
        Value::from(0),
        Value::Boolean(false),
        Value::from("same"),
        Value::Symbol("same".into()),
    ] {
        let fact = Fact {
            row: vec![values.intern(&value)].into(),
            digest: 7,
        };
        assert!(facts.insert(fact.clone()));
        assert!(!facts.insert(fact.clone()));
        assert!(facts.contains(&fact));
    }
    assert_eq!(facts.len(), 4);
}
