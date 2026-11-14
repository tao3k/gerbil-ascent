//! Bounded direct lookup for query-owned value codes; sparse codes stay hashed.
use super::{Cell, values::Row};
use std::{
    collections::{HashMap, hash_map::RandomState},
    hash::BuildHasher,
};

#[derive(Default)]
pub(super) struct OrdinalRows<S = RandomState> {
    dense: Vec<Vec<Row>>,
    sparse: HashMap<Cell, Vec<Row>, S>,
    dense_keys: usize,
}
impl<S: BuildHasher + Default> OrdinalRows<S> {
    pub(super) fn get(&self, cell: Cell) -> Option<&Vec<Row>> {
        if let Some(rows) = self.dense.get(cell.ordinal()) {
            (!rows.is_empty()).then_some(rows)
        } else {
            self.sparse.get(&cell)
        }
    }
    pub(super) fn insert(&mut self, cell: Cell, row: Row) {
        let index = cell.ordinal();
        if index >= self.dense.len()
            && let Some(extent) = extent(index, self.dense_keys, self.sparse.len())
        {
            self.dense.resize_with(extent, Vec::new);
            // Whole row lists move, retaining witness order within each key.
            let (dense, occupied) = (&mut self.dense, &mut self.dense_keys);
            self.sparse.retain(|key, rows| {
                if let Some(slot) = dense.get_mut(key.ordinal()) {
                    debug_assert_eq!(slot.as_slice(), []);
                    *slot = std::mem::take(rows);
                    *occupied += 1;
                    false
                } else {
                    true
                }
            });
            if self.sparse.is_empty() {
                self.sparse = HashMap::default();
            }
        }
        if let Some(rows) = self.dense.get_mut(index) {
            self.dense_keys += usize::from(rows.is_empty());
            rows.push(row);
        } else {
            self.sparse.entry(cell).or_default().push(row);
        }
    }
}
// Logical spine extent is at most twice the current distinct-key count plus
// six slots. Checked arithmetic and the Vec byte limit retain sparse fallback.
fn extent(index: usize, dense_keys: usize, sparse_keys: usize) -> Option<usize> {
    let target = index.checked_add(1)?.checked_next_power_of_two()?;
    let bound = dense_keys
        .checked_add(sparse_keys)?
        .checked_add(1)?
        .checked_mul(2)?
        .checked_add(4)?;
    extent_fits(target, bound, isize::MAX as usize / size_of::<Vec<Row>>()).then_some(target)
}

// BEGIN GENERATED ORDINAL EXTENT
fn extent_fits(target: usize, bound: usize, native_limit: usize) -> bool {
    target <= bound && target <= native_limit
}
// END GENERATED ORDINAL EXTENT

#[cfg(test)]
#[path = "../../tests/unit/ordinal.rs"]
mod tests;
