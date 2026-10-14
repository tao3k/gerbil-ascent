//! Incremental reflexive transitive closure with atomic admission and immutable compressed cuts.
use crate::{Cancellation, Error, Result, Row, Value, invalid_data as invalid};
use std::{
    collections::BTreeMap,
    sync::Arc,
    time::{Duration, Instant},
};
#[derive(Clone, Default)]
struct Group {
    values: Vec<Value>,
    index: BTreeMap<Value, usize>,
    bits: Vec<Vec<u64>>,
}
impl Group {
    fn node(&mut self, value: Value) -> usize {
        if let Some(&i) = self.index.get(&value) {
            return i;
        }
        let i = self.values.len();
        self.index.insert(value.clone(), i);
        self.values.push(value);
        let width = (i + 1).div_ceil(64);
        for row in &mut self.bits {
            row.resize(width, 0);
        }
        let mut row = vec![0; width];
        row[i / 64] |= 1 << (i % 64);
        self.bits.push(row);
        i
    }
    fn count(&self) -> usize {
        self.bits
            .iter()
            .flatten()
            .map(|w| w.count_ones() as usize)
            .sum()
    }
}
impl Group {
    fn connect(
        &mut self,
        a: usize,
        b: usize,
        cancel: &Cancellation,
        deadline: Instant,
    ) -> Result<()> {
        let successors = self.bits[b].clone();
        let mut steps = 0;
        for row in &mut self.bits {
            probe(cancel, deadline)?;
            if bit(row, a) {
                merge_bits(row, &successors, &mut steps)?;
            }
        }
        Ok(())
    }
}
fn probe(cancel: &Cancellation, deadline: Instant) -> Result<()> {
    if cancel.is_canceled() {
        return Err(Error::Canceled);
    }
    if Instant::now() >= deadline {
        return Err(Error::Timeout);
    }
    Ok(())
}
fn bit(row: &[u64], i: usize) -> bool {
    row[i / 64] & (1 << (i % 64)) != 0
}
fn merge_bits(target: &mut [u64], source: &[u64], steps: &mut usize) -> Result<()> {
    for (target, source) in target.iter_mut().zip(source) {
        *steps += 1;
        if *steps > 1_000_000 {
            return Err(Error::StateLimit);
        }
        *target |= source;
    }
    Ok(())
}
#[derive(Clone, Default)]
struct State {
    width: Option<usize>,
    groups: BTreeMap<Vec<Value>, Arc<Group>>,
    count: usize,
}
/// Immutable closure cut. Indexed reads preserve the same traversal order as complete export.
#[derive(Clone, Default)]
pub struct ReachabilitySnapshot(Arc<State>);
/// Incremental closure uses Rust-owned bitsets; failed insertions cannot change published cuts.
#[derive(Clone, Default)]
pub struct Reachability {
    state: Arc<State>,
}
impl Reachability {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }
    #[must_use]
    pub fn freeze(&self) -> ReachabilitySnapshot {
        ReachabilitySnapshot(self.state.clone())
    }
    /// Return the exact newly admitted tuple count; the budget includes new reflexive nodes.
    /// # Errors
    /// Rejects inconsistent arity, exhausted budgets, cancellation, or bounded work/time.
    pub fn insert(
        &mut self,
        edge: &[Value],
        budget: usize,
        cancel: &Cancellation,
    ) -> Result<usize> {
        let (prefix, group, admitted) = self.prepare(edge, cancel)?;
        if admitted > budget {
            return Err(Error::FactLimit);
        }
        let mut next = (*self.state).clone();
        next.width = Some(edge.len());
        next.count = next.count.checked_add(admitted).ok_or(Error::StateLimit)?;
        next.groups.insert(prefix, Arc::new(group));
        self.state = Arc::new(next);
        Ok(admitted)
    }
    fn prepare(&self, edge: &[Value], cancel: &Cancellation) -> Result<(Vec<Value>, Group, usize)> {
        let deadline = Instant::now() + Duration::from_secs(1);
        if edge.len() < 2 || edge.len() > 16 || self.state.width.is_some_and(|w| w != edge.len()) {
            return Err(invalid("reachability edge arity"));
        }
        let prefix = edge[..edge.len() - 2].to_vec();
        let existing = self.state.groups.get(&prefix);
        let mut group = existing.map_or_else(Group::default, |g| (**g).clone());
        if self.state.groups.len() >= 1024 && existing.is_none() {
            return Err(Error::StateLimit);
        }
        let fresh = edge[edge.len() - 2..]
            .iter()
            .filter(|v| !group.index.contains_key(*v))
            .collect::<std::collections::BTreeSet<_>>()
            .len();
        if group.values.len() + fresh > 4096 {
            return Err(Error::StateLimit);
        }
        let before = group.count();
        let a = group.node(edge[edge.len() - 2].clone());
        let b = group.node(edge[edge.len() - 1].clone());
        group.connect(a, b, cancel, deadline)?;
        let admitted = group
            .count()
            .checked_sub(before)
            .ok_or_else(|| invalid("reachability count regression"))?;
        Ok((prefix, group, admitted))
    }
    /// Actual compressed-storage observation: groups, vertices, bitset words and logical tuples.
    #[must_use]
    pub fn resources(&self) -> [usize; 4] {
        [
            self.state.groups.len(),
            self.state.groups.values().map(|g| g.values.len()).sum(),
            self.state
                .groups
                .values()
                .flat_map(|g| &g.bits)
                .map(Vec::len)
                .sum(),
            self.state.count,
        ]
    }
}
impl ReachabilitySnapshot {
    #[must_use]
    pub fn resources(&self) -> [usize; 4] {
        Reachability {
            state: self.0.clone(),
        }
        .resources()
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.0.count
    }
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.0.count == 0
    }
    #[must_use]
    pub fn contains(&self, row: &[Value]) -> bool {
        if self.0.width != Some(row.len()) || row.len() < 2 {
            return false;
        }
        let Some(group) = self.0.groups.get(&row[..row.len() - 2]) else {
            return false;
        };
        let (Some(&a), Some(&b)) = (
            group.index.get(&row[row.len() - 2]),
            group.index.get(&row[row.len() - 1]),
        ) else {
            return false;
        };
        group.bits[a][b / 64] & (1 << (b % 64)) != 0
    }
    /// Selected reads use fixed endpoint indexes; repeated constraints must all agree.
    /// # Errors
    /// Rejects invalid columns, cancellation, bounded output, and time exhaustion.
    pub fn rows(
        &self,
        selectors: &[(usize, Value)],
        limit: usize,
        cancel: &Cancellation,
    ) -> Result<Vec<Row>> {
        let deadline = Instant::now() + Duration::from_secs(1);
        let width = self.0.width.unwrap_or(2);
        if selectors.iter().any(|(c, _)| *c >= width) {
            return Err(invalid("view column outside row"));
        }
        let mut constraints = BTreeMap::new();
        for (c, v) in selectors {
            if constraints.insert(*c, v).is_some_and(|old| old != v) {
                return Ok(Vec::new());
            }
        }
        let mut result = Vec::new();
        for (prefix, group) in &self.0.groups {
            if prefix_matches(prefix, &constraints, width) {
                group.collect(prefix, &constraints, limit, cancel, deadline, &mut result)?;
            }
        }
        Ok(result)
    }
}

impl Reachability {
    /// Independently traverse current closure to check reflexivity and transitivity.
    /// # Errors
    /// Rejects cancelled or bounded validation without certifying a partial traversal.
    pub fn validate(&self, cancel: &Cancellation) -> Result<bool> {
        let deadline = Instant::now() + Duration::from_secs(1);
        let mut steps = 0usize;
        for group in self.state.groups.values() {
            if !group.validate(cancel, deadline, &mut steps)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
}

fn prefix_matches(prefix: &[Value], constraints: &BTreeMap<usize, &Value>, width: usize) -> bool {
    constraints
        .iter()
        .filter(|(c, _)| **c < width - 2)
        .all(|(c, v)| prefix.get(*c) == Some(*v))
}
struct Selection<'a> {
    prefix: &'a [Value],
    right: Option<usize>,
    limit: usize,
    cancel: &'a Cancellation,
    deadline: Instant,
}
impl Group {
    fn collect(
        &self,
        prefix: &[Value],
        constraints: &BTreeMap<usize, &Value>,
        limit: usize,
        cancel: &Cancellation,
        deadline: Instant,
        result: &mut Vec<Row>,
    ) -> Result<()> {
        let width = prefix.len() + 2;
        let left = constraints
            .get(&(width - 2))
            .map(|v| self.index.get(*v).copied());
        let right = constraints
            .get(&(width - 1))
            .map(|v| self.index.get(*v).copied());
        if matches!(left, Some(None)) || matches!(right, Some(None)) {
            return Ok(());
        }
        let selection = Selection {
            prefix,
            right: right.flatten(),
            limit,
            cancel,
            deadline,
        };
        for a in 0..self.values.len() {
            if left.flatten().is_none_or(|i| i == a) {
                self.collect_row(a, &selection, result)?;
            }
        }
        Ok(())
    }
    fn collect_row(
        &self,
        a: usize,
        selection: &Selection<'_>,
        result: &mut Vec<Row>,
    ) -> Result<()> {
        probe(selection.cancel, selection.deadline)?;
        for (word, bits) in self.bits[a].iter().enumerate() {
            let pending = selected_word(*bits, word, selection.right);
            self.collect_word(a, word, pending, selection, result)?;
        }
        Ok(())
    }
    fn collect_word(
        &self,
        a: usize,
        word: usize,
        mut pending: u64,
        selection: &Selection<'_>,
        result: &mut Vec<Row>,
    ) -> Result<()> {
        while pending != 0 {
            let b = word * 64 + pending.trailing_zeros() as usize;
            pending &= pending - 1;
            if result.len() >= selection.limit {
                return Err(Error::FactLimit);
            }
            let mut row = selection.prefix.to_vec();
            row.extend([self.values[a].clone(), self.values[b].clone()]);
            result.push(row.into());
        }
        Ok(())
    }
    fn validate(
        &self,
        cancel: &Cancellation,
        deadline: Instant,
        steps: &mut usize,
    ) -> Result<bool> {
        for (a, row) in self.bits.iter().enumerate() {
            probe(cancel, deadline)?;
            if !bit(row, a) || !self.validate_row(row, steps)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
    fn validate_row(&self, row: &[u64], steps: &mut usize) -> Result<bool> {
        for b in 0..self.values.len() {
            if bit(row, b) && !subset(&self.bits[b], row, steps)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
}
fn selected_word(bits: u64, word: usize, right: Option<usize>) -> u64 {
    match right {
        Some(b) if b / 64 == word => bits & (1 << (b % 64)),
        Some(_) => 0,
        None => bits,
    }
}
fn subset(left: &[u64], right: &[u64], steps: &mut usize) -> Result<bool> {
    for (left, right) in left.iter().zip(right) {
        *steps += 1;
        if *steps > 100_000_000 {
            return Err(Error::StateLimit);
        }
        if left & !right != 0 {
            return Ok(false);
        }
    }
    Ok(true)
}
