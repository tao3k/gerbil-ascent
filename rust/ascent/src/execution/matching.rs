//! Owned binding slots used by the Scheme-generated matching algorithm.
use super::Cell;
use smallvec::SmallVec;

pub(crate) type Bindings = SmallVec<[Option<Cell>; 4]>;

pub(crate) struct MatchState {
    values: Bindings,
    rejected: bool,
}
impl MatchState {
    #[inline]
    pub(crate) fn new(prior: &[Option<Cell>]) -> Self {
        Self {
            values: SmallVec::from_slice(prior),
            rejected: false,
        }
    }
    #[inline]
    pub(crate) fn is_rejected(&self) -> bool {
        self.rejected
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
    pub(crate) fn set(mut self, slot: usize, value: Cell) -> Self {
        self.values[slot] = Some(value);
        self
    }
    #[inline]
    pub(crate) fn reject(mut self) -> Self {
        self.rejected = true;
        self
    }
    #[inline]
    pub(crate) fn finish(self) -> Option<Bindings> {
        (!self.rejected).then_some(self.values)
    }
}

#[cfg(test)]
#[path = "../../tests/unit/matching.rs"]
mod tests;
