//! Independent plain-vector matching oracle across the inline/spill boundary.
use crate::execution::{Cell, Pattern, Values, kernels::bind};

fn oracle(terms: &[Pattern], row: &[Cell], prior: &[Option<Cell>]) -> Option<Vec<Option<Cell>>> {
    let mut slots = prior.to_vec();
    for (term, value) in terms.iter().zip(row) {
        match term {
            Pattern::Literal(expected) if expected != value => return None,
            Pattern::Wildcard | Pattern::Literal(_) => (),
            Pattern::Variable(slot) => {
                let target = &mut slots[*slot as usize];
                if target.is_some_and(|old| old != *value) {
                    return None;
                }
                *target = Some(*value);
            }
        }
    }
    Some(slots)
}

#[test]
fn generated_matching_agrees_with_vector_oracle_before_and_after_inline_spill() {
    let mut values = Values::default();
    let cells: Vec<_> = (0..3)
        .map(|n| values.intern(&crate::Value::from(n)))
        .collect();
    assert!(bind(&[], &[], &[]).unwrap().is_empty());
    for width in [1_u32, 3, 4, 5, 16] {
        for mask in 0..8 {
            let prior: Vec<_> = (0..width)
                .map(|slot| (mask & (1 << (slot % 3)) != 0).then_some(cells[slot as usize % 3]))
                .collect();
            let patterns = [
                vec![Pattern::Variable(0), Pattern::Variable(width - 1)],
                vec![Pattern::Variable(width - 1), Pattern::Variable(width - 1)],
                vec![Pattern::Literal(cells[0]), Pattern::Variable(width - 1)],
                vec![Pattern::Wildcard, Pattern::Variable(width - 1)],
            ];
            for terms in patterns {
                for a in &cells {
                    for b in &cells {
                        let row = [*a, *b];
                        let wanted = oracle(&terms, &row, &prior);
                        let actual = bind(&terms, &row, &prior);
                        assert_eq!(actual.as_deref(), wanted.as_deref());
                        assert_eq!(prior.len(), width as usize);
                    }
                }
            }
        }
    }
}
