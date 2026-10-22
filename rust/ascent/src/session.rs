//! Caller-owned pools, source transactions and completed result publication.
use crate::{
    Cancellation, Error, Limits, Program, Result, Row, Snapshot,
    execution::{evaluate, work},
    graph::Graph,
};
#[cfg(feature = "rayon")]
use rayon::{ThreadPool, slice::ParallelSliceMut};
use std::{
    collections::{BTreeMap, HashSet},
    sync::{
        Arc, OnceLock,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};
pub use work::WorkDistribution;

static RUNTIME_PROCESS: OnceLock<u32> = OnceLock::new();

/// Uses an explicit pool; never configures Rayon's process-global pool.
#[derive(Clone)]
pub struct Engine {
    #[cfg(feature = "rayon")]
    pool: Arc<ThreadPool>,
    parallel: bool,
    process: u32,
    closed: Arc<AtomicBool>,
    source_limit: Option<usize>,
    request_limit: Option<usize>,
    source_scopes: Arc<AtomicUsize>,
    work: work::Work,
}
impl Engine {
    /// # Errors
    /// Rejects zero workers, unavailable parallelism, or pool construction failure.
    pub fn new(threads: usize) -> Result<Self> {
        if *RUNTIME_PROCESS.get_or_init(std::process::id) != std::process::id() {
            return Err(Error::InvalidProgram(
                "forked Library runtime requires exec before initialization".into(),
            ));
        }
        if threads == 0 {
            return Err(Error::InvalidProgram(
                "worker count must be positive".into(),
            ));
        }
        #[cfg(not(feature = "rayon"))]
        {
            if threads != 1 {
                return Err(Error::InvalidProgram(
                    "multiple workers require the rayon feature".into(),
                ));
            }
            Ok(Self {
                parallel: false,
                process: std::process::id(),
                closed: Arc::default(),
                source_limit: None,
                request_limit: None,
                source_scopes: Arc::default(),
                work: work::Work::default(),
            })
        }
        #[cfg(feature = "rayon")]
        {
            let pool = rayon::ThreadPoolBuilder::new()
                .num_threads(threads)
                .build()
                .map_err(|error| Error::InvalidProgram(error.to_string()))?;
            Ok(Self::with_pool(Arc::new(pool)))
        }
    }
    #[must_use]
    #[cfg(feature = "rayon")]
    pub fn with_pool(pool: Arc<ThreadPool>) -> Self {
        Self {
            pool,
            parallel: true,
            process: *RUNTIME_PROCESS.get_or_init(std::process::id),
            closed: Arc::default(),
            source_limit: None,
            request_limit: None,
            source_scopes: Arc::default(),
            work: work::Work::default(),
        }
    }
    /// Choose fanout without changing pool size or source/result ownership.
    /// Clones share the pending-evaluation ledger; independent Engines do not.
    #[must_use]
    pub fn with_work_distribution(mut self, distribution: WorkDistribution) -> Self {
        self.work.distribution = distribution;
        self
    }
    #[must_use]
    pub fn work_distribution(&self) -> WorkDistribution {
        self.work.distribution
    }
    /// Queued/running uncached evaluations, held through snapshot publication.
    /// Retained results and outer provenance projection are separate scopes.
    #[must_use]
    pub fn pending_evaluations(&self) -> usize {
        self.work.pending()
    }
    fn request_fanout(&self) -> bool {
        self.work.fanout(self.threads(), self.parallel)
    }
    fn sort_rows(&self, rows: &mut [Row]) {
        #[cfg(not(feature = "rayon"))]
        debug_assert!(!self.parallel, "serial build cannot enter a Rayon pool");
        // Avoid splitting short sorts and one-worker pools. Large snapshots use
        // this caller-owned pool; final publication still rechecks the deadline.
        #[cfg(feature = "rayon")]
        if self.request_fanout() && self.threads() > 1 && rows.len() >= 16_384 {
            self.pool.install(|| rows.par_sort_unstable());
            return;
        }
        rows.sort_unstable();
    }
    /// Matched algorithm/control; one-worker Rayon is a separate configuration.
    /// # Errors
    /// Returns a pool-construction failure.
    pub fn serial() -> Result<Self> {
        let mut engine = Self::new(1)?;
        engine.parallel = false;
        Ok(engine)
    }
    #[must_use]
    pub fn threads(&self) -> usize {
        #[cfg(feature = "rayon")]
        {
            self.pool.current_num_threads()
        }
        #[cfg(not(feature = "rayon"))]
        {
            1
        }
    }
    /// # Errors
    /// Rejects invalid typed declarations, unsafe variables or negative cycles.
    pub fn open(&self, program: Program) -> Result<Session> {
        self.check()?;
        let graph = Arc::new(Graph::build(program)?);
        let counts: Vec<_> = graph
            .program
            .relations
            .iter()
            .map(|r| r.rows.len())
            .collect();
        let input_count = counts
            .iter()
            .try_fold(0usize, |sum, count| sum.checked_add(*count))
            .ok_or(Error::SourceFactLimit)?;
        if graph
            .program
            .fact_limits
            .input
            .is_some_and(|limit| input_count > limit)
        {
            return Err(Error::SourceFactLimit);
        }
        let sources: Vec<Vec<Row>> = graph
            .program
            .relations
            .iter()
            .map(|r| {
                if r.source {
                    if r.initial_occurrences {
                        r.rows.clone()
                    } else {
                        r.rows
                            .iter()
                            .cloned()
                            .collect::<HashSet<_>>()
                            .into_iter()
                            .collect()
                    }
                } else {
                    Vec::new()
                }
            })
            .collect();

        Ok(Session {
            engine: self.clone(),
            graph,
            committed_counts: counts.clone(),
            counts,
            closed: false,
            committed_generation: 0,
            sources: sources.clone(),
            committed: sources,
            generation: 0,
            clean: false,
            last: None,
        })
    }
    /// Whether this shared engine owner has been shut down.
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.process != std::process::id() || self.closed.load(Ordering::Acquire)
    }
    /// Set a caller-owned lifetime admission cap, not a process-wide VM limit.
    /// # Errors
    /// Rejects zero limits and policy changes after admitting a source scope.
    pub fn with_source_limit(mut self, limit: Option<usize>) -> Result<Self> {
        if limit == Some(0)
            || self.source_scope_count() != 0
            || Arc::strong_count(&self.source_scopes) != 1
        {
            return Err(Error::InvalidProgram(
                "positive source limit before admission required".into(),
            ));
        }
        self.source_limit = limit;
        Ok(self)
    }
    #[must_use]
    pub fn source_limit(&self) -> Option<usize> {
        self.source_limit
    }
    /// Set a host transport ceiling before publishing any owner clones.
    /// # Errors
    /// Rejects zero ceilings or policy changes on an already shared owner.
    pub fn with_request_limit(mut self, limit: Option<usize>) -> Result<Self> {
        if limit == Some(0)
            || Arc::strong_count(&self.source_scopes) != 1
            || self.source_scope_count() != 0
        {
            return Err(Error::InvalidProgram(
                "positive request limit before admission required".into(),
            ));
        }
        self.request_limit = limit;
        Ok(self)
    }
    #[must_use]
    pub fn request_limit(&self) -> Option<usize> {
        self.request_limit
    }
    #[must_use]
    pub fn source_scope_count(&self) -> usize {
        self.source_scopes.load(Ordering::Acquire)
    }
    /// Charge a trusted source-read attempt; failure and close do not refund it.
    /// # Errors
    /// Rejects closed/forked owners, exhausted caller caps and count overflow.
    pub fn admit_source(&self) -> Result<()> {
        self.check()?;
        self.source_scopes
            .try_update(Ordering::AcqRel, Ordering::Acquire, |count| {
                if self.source_limit.is_some_and(|limit| count >= limit) {
                    None
                } else {
                    count.checked_add(1)
                }
            })
            .map(|_| ())
            .map_err(|_| Error::InvalidProgram("caller source scope limit exceeded".into()))
    }
    /// Clones share an owner; independently constructed pools do not.
    #[must_use]
    pub fn same_owner(&self, other: &Self) -> bool {
        Arc::ptr_eq(&self.closed, &other.closed)
    }
    /// Closing an engine invalidates all session owners sharing its pool.
    pub fn shutdown(&self) {
        self.closed.store(true, Ordering::Release);
    }
    /// Validate engine lifetime and process ownership.
    /// # Errors
    /// Rejects closed or inherited process owners.
    pub fn check(&self) -> Result<()> {
        if self.is_closed() {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
}
/// Retained source owner; only successful runs publish immutable snapshots.
#[derive(Clone)]
pub struct Session {
    closed: bool,
    counts: Vec<usize>,
    committed_counts: Vec<usize>,
    committed_generation: u64,
    engine: Engine,
    graph: Arc<Graph>,
    sources: Vec<Vec<Row>>,
    committed: Vec<Vec<Row>>,
    generation: u64,
    clean: bool,
    last: Option<Arc<Snapshot>>,
}
impl Session {
    /// Close this owner. Immutable snapshots remain independent observations.
    pub fn close(&mut self) {
        self.closed = true;
    }
    pub(crate) fn check(&self) -> Result<()> {
        self.engine.check()?;
        if self.closed {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
    pub(crate) fn is_clean(&self) -> bool {
        self.clean
    }
    pub(crate) fn program(&self) -> &Program {
        &self.graph.program
    }
    pub(crate) fn current_program(&self) -> Program {
        let mut program = self.graph.program.clone();
        for (relation, rows) in program.relations.iter_mut().zip(&self.sources) {
            if relation.source {
                relation.rows.clone_from(rows);
            }
        }
        program
    }

    /// Validate the entire transaction before publishing any source replacement.
    /// # Errors
    /// Rejects non-source relations, incorrect rows or exhausted generation IDs.
    pub fn replace_sources(&mut self, updates: BTreeMap<String, Vec<Row>>) -> Result<()> {
        self.check()?;
        let mut counts = self.counts.clone();
        let mut checked = Vec::new();
        for (name, rows) in updates {
            let id = self.graph.validate_rows(&name, &rows)?;
            counts[id] = rows.len();
            let rows = if self.graph.program.relations[id].initial_occurrences {
                rows
            } else {
                rows.into_iter()
                    .collect::<HashSet<_>>()
                    .into_iter()
                    .collect()
            };
            checked.push((id, rows));
        }
        if checked.is_empty() {
            return Ok(());
        }
        let count = counts
            .iter()
            .try_fold(0usize, |sum, n| sum.checked_add(*n))
            .ok_or(Error::SourceFactLimit)?;
        if self
            .graph
            .program
            .fact_limits
            .input
            .is_some_and(|limit| count > limit)
        {
            return Err(Error::SourceFactLimit);
        }
        let generation = self
            .generation
            .checked_add(1)
            .ok_or_else(|| Error::InvalidUpdate("generation exhausted".into()))?;
        for (id, rows) in checked {
            self.sources[id] = rows;
        }
        self.counts = counts;
        self.generation = generation;
        self.clean = false;
        Ok(())
    }
    /// # Errors
    /// Returns the same admission failures as `replace_sources`.
    pub fn replace(&mut self, name: &str, rows: Vec<Row>) -> Result<()> {
        self.replace_sources(BTreeMap::from([(name.into(), rows)]))
    }
    #[must_use]
    pub fn last_completed(&self) -> Option<Arc<Snapshot>> {
        self.last.clone()
    }
    /// # Errors
    /// Returns cancellation or budget exhaustion without publishing partial data.
    pub fn run(&mut self, limits: &Limits, cancellation: &Cancellation) -> Result<Arc<Snapshot>> {
        self.check()?;
        // Cancellation/deadline also applies to retained-result admission.
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        if limits.timeout.is_zero() {
            return Err(Error::Timeout);
        }
        if let Some(last) = self.cached(limits)? {
            return Ok(last);
        }
        let started = std::time::Instant::now();
        let _evaluation = self.engine.work.enter()?;
        #[cfg(feature = "rayon")]
        {
            let pool = Arc::clone(&self.engine.pool);
            pool.install(|| self.evaluate_and_publish(started, limits, cancellation))
        }
        #[cfg(not(feature = "rayon"))]
        self.evaluate_and_publish(started, limits, cancellation)
    }
    fn evaluate_and_publish(
        &mut self,
        started: std::time::Instant,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<Arc<Snapshot>> {
        let rows = match evaluate(
            &self.graph,
            &self.sources,
            limits,
            cancellation,
            self.engine.request_fanout(),
            started,
        ) {
            Ok(rows) => rows,
            Err(error) => return self.reject(error),
        };
        self.publish(rows, started, limits, cancellation)
    }
    fn cached(&self, limits: &Limits) -> Result<Option<Arc<Snapshot>>> {
        let Some(last) = self.last.as_ref().filter(|_| self.clean) else {
            return Ok(None);
        };
        if last.relations.values().map(Vec::len).sum::<usize>() > limits.max_facts {
            return Err(Error::FactLimit);
        }
        Ok(Some(last.clone()))
    }
    fn reject(&mut self, error: Error) -> Result<Arc<Snapshot>> {
        self.sources.clone_from(&self.committed);
        self.counts.clone_from(&self.committed_counts);
        self.generation = self.committed_generation;
        self.clean = false;
        Err(error)
    }
    fn publish(
        &mut self,
        rows: Vec<Vec<Row>>,
        started: std::time::Instant,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<Arc<Snapshot>> {
        #[cfg(feature = "rayon")]
        debug_assert!(
            self.engine.pool.current_thread_index().is_some(),
            "snapshot publication must stay on the caller-owned Rayon pool"
        );
        if self
            .graph
            .program
            .fact_limits
            .output
            .is_some_and(|limit| rows.iter().map(Vec::len).sum::<usize>() > limit)
        {
            return self.reject(Error::OutputFactLimit);
        }
        let relations = self
            .graph
            .program
            .relations
            .iter()
            .zip(rows)
            .map(|(declaration, rows)| {
                let mut rows = rows;
                self.engine.sort_rows(&mut rows);
                (declaration.name.clone(), rows)
            })
            .collect();
        let snapshot = Arc::new(Snapshot {
            generation: self.generation,
            relations,
        });
        let canceled = cancellation.is_canceled();
        if canceled || started.elapsed() >= limits.timeout {
            return self.reject(if canceled {
                Error::Canceled
            } else {
                Error::Timeout
            });
        }
        if let Err(error) = self.engine.check() {
            return self.reject(error);
        }
        self.committed.clone_from(&self.sources);
        self.committed_counts.clone_from(&self.counts);
        self.committed_generation = self.generation;
        self.clean = true;
        self.last = Some(snapshot.clone());
        Ok(snapshot)
    }
}
