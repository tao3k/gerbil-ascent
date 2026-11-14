//! Scheme result cells retain the exact source generation and owning result.
use super::session::RuleResult;
use gerbil_ascent::{ObjectInput, Result};

/// A source cell lease bound to its native result and generation.
#[derive(Clone)]
pub struct ResultValue {
    pub(super) result: RuleResult,
    pub(super) relation: String,
    pub(super) row: usize,
    pub(super) column: usize,
}
impl ResultValue {
    /// Resolve a generation-checked native cell as a typed argument.
    /// # Errors
    /// Rejects revoked results or invalid row/column coordinates.
    pub fn input(&self) -> Result<ObjectInput> {
        self.result.reference(&self.relation, self.row, self.column)
    }
}
