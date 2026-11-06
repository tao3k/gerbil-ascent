use super::{atom, form, required};

#[test]
fn only_structural_clauses_require_expansion() {
    for tag in ["match", "for", "or"] {
        assert!(required(&[form(tag, [])]));
    }
    assert!(!required(&[form("edge", [atom("or"), atom("match")])]));
    assert!(!required(&[form("if", [form("or", [])])]));
    assert!(!required(&[atom("malformed")]));
    assert!(!required(&[]));
}
