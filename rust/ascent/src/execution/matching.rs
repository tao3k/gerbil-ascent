//! Owned binding slots used by the Scheme-generated matching algorithm.
use super::{Cell, Pattern};
use smallvec::SmallVec;

pub(crate) type Bindings = SmallVec<[Option<Cell>; 4]>;

/// One stack-local slot owner; generated steps borrow it without moving it.
// BEGIN GENERATED BORROWED MATCH
pub(crate) struct MatchState {
    values: Bindings,
}
impl MatchState {
    #[inline]
    pub(crate) fn matching(
        terms: &[Pattern],
        row: &[Cell],
        prior: &[Option<Cell>],
        step: fn(&mut Self, &Pattern, Cell) -> bool,
    ) -> Option<Bindings> {
        let mut state = Self {
            values: prior.iter().copied().collect(),
        };
        terms
            .iter()
            .zip(row)
            .all(|(term, value)| step(&mut state, term, *value))
            .then_some(state.values)
    }
    #[inline]
    pub(crate) fn contains(&self, slot: usize) -> bool {
        self.values[slot].is_some()
    }
    #[inline]
    pub(crate) fn value(&self, slot: usize) -> Cell {
        self.values[slot].expect("generated bound-slot branch")
    }
    #[inline]
    pub(crate) fn set(&mut self, slot: usize, value: Cell) -> bool {
        self.values[slot] = Some(value);
        true
    }
}

// END GENERATED BORROWED MATCH

#[cfg(test)]
#[path = "../../tests/unit/matching.rs"]
mod tests;
