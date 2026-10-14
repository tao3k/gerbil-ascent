//! Exact work/fact admission and cooperative execution interruption.
use super::{Fact, FactSet};
use crate::{Error, Result};
use std::collections::hash_map::RandomState;
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU8, AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};

/// Cooperative execution budgets, shared across strata and worker tasks.
#[derive(Clone, Debug)]
pub struct Limits {
    pub max_facts: usize,
    /// Total binding/projection work, including failed matches and duplicates.
    pub max_states: usize,
    pub timeout: Duration,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            max_facts: 1_000_000,
            max_states: 10_000_000,
            timeout: Duration::from_secs(30),
        }
    }
}
/// Thread-safe cooperative cancellation shared with an executing request.
#[derive(Clone, Debug, Default)]
pub struct Cancellation(Arc<AtomicBool>);
impl Cancellation {
    pub fn cancel(&self) {
        self.0.store(true, Ordering::Release);
    }
    #[must_use]
    pub fn is_canceled(&self) -> bool {
        self.0.load(Ordering::Acquire)
    }
}
pub(crate) struct Budget {
    limits: Limits,
    start: Instant,
    cancellation: Cancellation,
    failure: AtomicU8,
    facts: AtomicUsize,
    derived: AtomicUsize,
    derived_limit: Option<usize>,
    relation_limit: Option<usize>,
    relation_counts: Vec<AtomicUsize>,
    pending: Vec<Mutex<super::lattice::Frontier>>,
    work: AtomicUsize,
    authority: RandomState,
    evaluation: Mutex<Option<Error>>,
}
impl Budget {
    pub(crate) fn new(
        limits: &Limits,
        cancellation: &Cancellation,
        relations: usize,
        policy: crate::FactLimits,
        relation_limit: Option<usize>,
    ) -> Self {
        Self {
            relation_limit,
            relation_counts: if relation_limit.is_some() {
                (0..relations).map(|_| AtomicUsize::new(0)).collect()
            } else {
                Vec::new()
            },
            limits: limits.clone(),
            start: Instant::now(),
            cancellation: cancellation.clone(),
            failure: AtomicU8::new(0),
            facts: AtomicUsize::new(0),
            derived: AtomicUsize::new(0),
            derived_limit: policy.derived,
            pending: (0..relations)
                .map(|_| Mutex::new(super::lattice::Frontier::new()))
                .collect(),
            work: AtomicUsize::new(0),
            authority: RandomState::new(),
            evaluation: Mutex::new(None),
        }
    }
    pub(crate) fn fact(&self, row: super::values::Row) -> Fact {
        Fact::new(row, &self.authority)
    }
    fn fail(&self, reason: u8) {
        let _ = self
            .failure
            .compare_exchange(0, reason, Ordering::AcqRel, Ordering::Acquire);
    }
    /// Cheap cancellation/failure observation remains on every candidate.
    pub(crate) fn active(&self) -> bool {
        if self.cancellation.is_canceled() {
            self.fail(4);
        }
        self.failure.load(Ordering::Acquire) == 0
    }
    /// Clock sampling at bounded candidate chunks and lifecycle boundaries.
    pub(crate) fn poll(&self) -> bool {
        if !self.active() {
            return false;
        }
        if self.start.elapsed() >= self.limits.timeout {
            self.fail(3);
        }
        self.failure.load(Ordering::Acquire) == 0
    }
    fn charge(&self, counter: &AtomicUsize, count: usize, limit: usize, reason: u8) -> bool {
        if !self.poll() {
            return false;
        }
        if counter
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |prior| {
                prior.checked_add(count).filter(|next| *next <= limit)
            })
            .is_err()
        {
            self.fail(reason);
            return false;
        }
        true
    }
    /// Charge exact work; sample the clock at least every 128 admitted units.
    /// Candidate cancellation remains independently checked on every row.
    pub(crate) fn work(&self, count: usize) -> bool {
        if !self.active() {
            return false;
        }
        let admitted = self
            .work
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |prior| {
                prior
                    .checked_add(count)
                    .filter(|next| *next <= self.limits.max_states)
            });
        let Ok(prior) = admitted else {
            self.fail(2);
            return false;
        };
        if prior == 0 || count >= 128 || prior % 128 + count >= 128 {
            return self.poll();
        }
        true
    }
    pub(crate) fn relation_facts(&self, relation: usize, count: usize) -> bool {
        self.relation_limit
            .is_none_or(|limit| self.charge(&self.relation_counts[relation], count, limit, 1))
    }
    /// Called by the round owner after exact deduplication.
    pub(crate) fn facts(&self, count: usize) -> bool {
        self.charge(&self.facts, count, self.limits.max_facts, 1)
    }
    /// Incoming rows are unique within this producer's batch. The shared set
    /// admits each new global fact exactly once before any task retains it.
    pub(crate) fn admit(&self, relation: usize, rows: Vec<Fact>) -> bool {
        let mut known = self.pending[relation]
            .lock()
            .expect("relation candidate admission");
        let accepted: Vec<_> = rows
            .into_iter()
            .filter(|row| !known.facts.contains(row))
            .collect();
        if !self.relation_facts(relation, accepted.len())
            || !self.facts(accepted.len())
            || self
                .derived_limit
                .is_some_and(|limit| !self.charge(&self.derived, accepted.len(), limit, 6))
        {
            return false;
        }
        known.facts.extend(accepted);
        self.active()
    }
    pub(crate) fn admit_lattice(
        &self,
        relation: usize,
        rows: Vec<Fact>,
        mode: crate::LatticeJoin,
        values: &super::Values,
    ) -> bool {
        let mut pending = self.pending[relation]
            .lock()
            .expect("lattice frontier admission");
        let admitted = match super::lattice::merge(&mut pending.lattice, rows, mode, values) {
            Ok(count) => count,
            Err(error) => {
                self.evaluation_error(error);
                return false;
            }
        };
        self.facts(admitted)
            && self
                .derived_limit
                .is_none_or(|limit| self.charge(&self.derived, admitted, limit, 6))
    }
    /// Read only after producer join; empty relations need no publication task.
    pub(crate) fn pending_len(&self, relation: usize) -> usize {
        let pending = self.pending[relation]
            .lock()
            .expect("joined publication size");
        pending.facts.len() + pending.lattice.len()
    }
    /// All producer tasks have joined. One publisher owns each relation while
    /// draining; retaining the set preserves its allocation for the next round.
    pub(crate) fn publish(
        &self,
        relation: usize,
        apply: impl FnOnce(&mut FactSet) -> usize,
    ) -> usize {
        let mut pending = self.pending[relation]
            .lock()
            .expect("joined relation publication");
        let lattice = std::mem::take(&mut pending.lattice);
        pending.facts.extend(lattice.into_values());
        apply(&mut pending.facts)
    }
    pub(crate) fn evaluation_error(&self, error: Error) {
        let mut failure = self.evaluation.lock().expect("expression error owner");
        if failure.is_none() {
            *failure = Some(error);
        }
        self.fail(5);
    }
    pub(crate) fn result(&self) -> Result<()> {
        self.poll();
        match self.failure.load(Ordering::Acquire) {
            0 => Ok(()),
            1 => Err(Error::FactLimit),
            2 => Err(Error::StateLimit),
            3 => Err(Error::Timeout),
            4 => Err(Error::Canceled),
            6 => Err(Error::DerivedFactLimit),
            _ => Err(self
                .evaluation
                .lock()
                .expect("expression error owner")
                .clone()
                .expect("recorded expression error")),
        }
    }
}
