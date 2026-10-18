//! Independent translation validation of the callback-free positive fragment.
//! This runs once at graph admission, never in the join or lookup loop.
use super::descriptor_stream::{check_keys, check_terms};
use super::{Atom, Clause, Rule};
use crate::{Program, execution::Values};
use std::collections::HashMap;

fn atom(
    source: &crate::Atom,
    actual: &Atom,
    program: &Program,
    values: &Values,
    names: &mut HashMap<u32, usize>,
    head: bool,
) -> bool {
    let Some(relation) = program.relations.get(actual.relation) else {
        return false;
    };
    if source.relation != relation.name || source.terms.len() != actual.terms.len() {
        return false;
    }
    // Only names from *previous* atoms can supply lookup keys. A repeated
    // variable first introduced in this atom must not read a stale frame slot.
    if !head && !check_keys(&source.terms, &actual.keys, names) {
        return false;
    }
    check_terms(&source.terms, &actual.terms, values, names, head)
}

pub(super) fn check(
    program: &Program,
    rules: &[Rule],
    shapes: &[Vec<Vec<usize>>],
    values: &Values,
) -> bool {
    if program.rules.len() != rules.len() {
        return false;
    }
    program.rules.iter().zip(rules).all(|(source, actual)| {
        // Other fragments keep their own typed admission, rather than being
        // silently granted a positive-Set certificate.
        if source.body.iter().any(|clause| {
            !matches!(
                clause,
                crate::Clause::Relation {
                    negative: false,
                    ..
                }
            )
        }) {
            return true;
        }
        if source.body.len() != actual.body.len() {
            return false;
        }
        let mut names = HashMap::new();
        let body_checked = source
            .body
            .iter()
            .zip(&actual.body)
            .all(|(source, actual)| {
                let (
                    crate::Clause::Relation {
                        atom: source,
                        negative: false,
                    },
                    Clause::Relation {
                        atom: actual,
                        negative: false,
                    },
                ) = (source, actual)
                else {
                    return false;
                };
                if !atom(source, actual, program, values, &mut names, false) {
                    return false;
                }
                match actual.index {
                    None if actual.keys.is_empty() => true,
                    Some(slot)
                        if shapes
                            .get(actual.relation)
                            .and_then(|shapes| shapes.get(slot))
                            == Some(&actual.keys) =>
                    {
                        true
                    }
                    _ => false,
                }
            });
        body_checked
            && atom(
                &source.head,
                &actual.head,
                program,
                values,
                &mut names,
                true,
            )
            && actual.variables == names.len()
    })
}

#[cfg(test)]
#[path = "../../tests/unit/compiler_certificate.rs"]
mod tests;
