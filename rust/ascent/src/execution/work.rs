//! Advisory Rayon fanout; never a fact, cancellation or publication authority.
use crate::{Error, Result, execution::request_fanout};
use std::sync::{
    Arc,
    atomic::{AtomicUsize, Ordering},
};

/// Distribute a caller-owned pool across requests or within one evaluation.
/// This controls Rust-owned evaluation only; Scheme handles keep their owner.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub enum WorkDistribution {
    /// Avoid nested fanout when queued/running evaluations fill the pool.
    #[default]
    Adaptive,
    /// One worker per evaluation, suitable for independent short requests.
    /// This is not a priority queue or a latency guarantee.
    AcrossRequests,
    /// Permit internal rule/join parallelism, including under shared load.
    WithinRequest,
}
#[derive(Clone, Default)]
pub(crate) struct Work {
    pub(crate) distribution: WorkDistribution,
    pending: Arc<AtomicUsize>,
}
pub(crate) struct Evaluation(Arc<AtomicUsize>);
impl Work {
    pub(crate) fn pending(&self) -> usize {
        self.pending.load(Ordering::Acquire)
    }
    pub(crate) fn enter(&self) -> Result<Evaluation> {
        let mut pending = self.pending.load(Ordering::Acquire);
        loop {
            let next = pending
                .checked_add(1)
                .ok_or_else(|| Error::InvalidProgram("evaluation population exhausted".into()))?;
            match self.pending.compare_exchange_weak(
                pending,
                next,
                Ordering::AcqRel,
                Ordering::Acquire,
            ) {
                Ok(_) => return Ok(Evaluation(self.pending.clone())),
                Err(actual) => pending = actual,
            }
        }
    }
    pub(crate) fn fanout(&self, workers: usize, enabled: bool) -> bool {
        request_fanout(
            workers,
            self.pending(),
            enabled,
            self.distribution == WorkDistribution::AcrossRequests,
            self.distribution == WorkDistribution::WithinRequest,
        )
    }
}
impl Drop for Evaluation {
    fn drop(&mut self) {
        let before = self.0.fetch_sub(1, Ordering::AcqRel);
        debug_assert!(before > 0);
    }
}

#[cfg(test)]
#[path = "../../tests/unit/request_work.rs"]
mod tests;
