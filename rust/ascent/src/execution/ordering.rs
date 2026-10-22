//! Publication order uses actual value ranks, never insertion-order codes.
use super::{Budget, Values, values::Row};
#[cfg(feature = "rayon")]
use rayon::{
    iter::{IndexedParallelIterator, IntoParallelIterator, ParallelIterator},
    slice::ParallelSliceMut,
};
use std::{cmp::Ordering, ops::Deref};

/// Private ordering handoff: only the decoder constructs ordered output.
pub(crate) struct EvaluatedRows {
    rows: Vec<crate::Row>,
    ordered: bool,
}
impl EvaluatedRows {
    pub(super) fn new(rows: Vec<crate::Row>, ordered: bool) -> Self {
        Self { rows, ordered }
    }
    pub(crate) fn into_rows(self) -> (Vec<crate::Row>, bool) {
        (self.rows, self.ordered)
    }
}
impl Deref for EvaluatedRows {
    type Target = [crate::Row];
    fn deref(&self) -> &Self::Target {
        &self.rows
    }
}

/// Rank actual values once; interning codes themselves have no value order.
pub(super) fn ranks(values: &Values) -> Vec<usize> {
    let mut codes: Vec<_> = (0..values.values.len()).collect();
    codes.sort_unstable_by(|a, b| values.values[*a].cmp(&values.values[*b]));
    let mut ranks = vec![0; codes.len()];
    for (rank, code) in codes.into_iter().enumerate() {
        ranks[code] = rank;
    }
    ranks
}

// BEGIN GENERATED RANKED ROW ORDER
pub(super) fn compare(a: &Row, b: &Row, ranks: &[usize]) -> Ordering {
    a.iter()
        .map(|cell| ranks[cell.ordinal()])
        .cmp(b.iter().map(|cell| ranks[cell.ordinal()]))
}
// END GENERATED RANKED ROW ORDER

pub(super) fn decode(
    rows: Vec<Row>,
    values: &Values,
    ranks: Option<&[usize]>,
    budget: &Budget,
    parallel: &(dyn Fn() -> bool + Sync),
    chunk: usize,
) -> super::EvaluatedRows {
    let mut rows = rows;
    if let Some(ranks) = ranks {
        #[cfg(feature = "rayon")]
        if rows.len() >= 16_384 && parallel() {
            rows.par_sort_unstable_by(|a, b| compare(a, b, ranks));
        } else {
            rows.sort_unstable_by(|a, b| compare(a, b, ranks));
        }
        #[cfg(not(feature = "rayon"))]
        rows.sort_unstable_by(|a, b| compare(a, b, ranks));
    }
    let decode = |(i, row): (usize, Row)| {
        ((i % chunk != 0 || budget.poll()) && budget.active()).then(|| values.decode(&row))
    };
    #[cfg(feature = "rayon")]
    // Work may have arrived since evaluation entry. Recheck the same advisory
    // population at this phase boundary; every decoder budget poll is retained.
    if rows.len() >= 8192 && parallel() {
        return super::EvaluatedRows::new(
            rows.into_par_iter()
                .enumerate()
                .filter_map(decode)
                .collect(),
            ranks.is_some(),
        );
    }
    #[cfg(not(feature = "rayon"))]
    let _ = parallel;
    super::EvaluatedRows::new(
        rows.into_iter().enumerate().filter_map(decode).collect(),
        ranks.is_some(),
    )
}

#[cfg(test)]
#[path = "../../tests/unit/ordering.rs"]
mod tests;
