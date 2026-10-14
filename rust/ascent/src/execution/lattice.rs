//! Keyed lattice frontier admission and current-index publication.
use super::{Cell, Fact, FactSet, Values};
use crate::{LatticeJoin, Result};
use std::collections::HashMap;
pub(super) fn key(row: &[Cell]) -> &[Cell] {
    &row[..row.len() - 1]
}
pub(super) fn improves(
    mode: LatticeJoin,
    candidate: &Fact,
    prior: &Fact,
    values: &Values,
) -> Result<bool> {
    mode.improves(
        values.scalar(*candidate.row.last().expect("lattice arity")),
        values.scalar(*prior.row.last().expect("lattice arity")),
    )
}
pub(super) fn merge(
    pending: &mut HashMap<Vec<Cell>, Fact>,
    rows: Vec<Fact>,
    mode: LatticeJoin,
    values: &Values,
) -> Result<usize> {
    let before = pending.len();
    for row in rows {
        let key = key(&row.row).to_vec();
        if let Some(prior) = pending.get(&key)
            && !improves(mode, &row, prior, values)?
        {
            continue;
        }
        pending.insert(key, row);
    }
    Ok(pending.len() - before)
}
pub(super) struct Frontier {
    pub facts: FactSet,
    pub lattice: HashMap<Vec<Cell>, Fact>,
}
impl Frontier {
    pub fn new() -> Self {
        Self {
            facts: FactSet::default(),
            lattice: HashMap::new(),
        }
    }
}
