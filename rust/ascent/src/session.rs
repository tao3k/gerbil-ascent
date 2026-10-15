//! Caller-owned pools, source transactions and completed result publication.
use crate::{
    Cancellation, Error, Limits, Program, Result, Row, Snapshot, execution::evaluate, graph::Graph,
};
#[cfg(feature = "rayon")]
use rayon::{ThreadPool, slice::ParallelSliceMut};
use std::{
    collections::{BTreeMap, HashSet},
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};

/// Uses an explicit pool; never configures Rayon's process-global pool.
#[derive(Clone)]
pub struct Engine {
    #[cfg(feature = "rayon")]
    pool: Arc<ThreadPool>,
    parallel: bool,
    closed: Arc<AtomicBool>,
    pub(crate) evidence_owners: Arc<AtomicUsize>,
    pub(crate) trajectory_owners: Arc<AtomicUsize>,
}
impl Engine {
    /// # Errors
    /// Rejects zero workers, unavailable parallelism, or pool construction failure.
    pub fn new(threads: usize) -> Result<Self> {
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
                closed: Arc::default(),
                evidence_owners: Arc::default(),
                trajectory_owners: Arc::default(),
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
            closed: Arc::default(),
            evidence_owners: Arc::default(),
            trajectory_owners: Arc::default(),
        }
    }
    fn sort_rows(&self, rows: &mut [Row]) {
        #[cfg(not(feature = "rayon"))]
        debug_assert!(!self.parallel, "serial build cannot enter a Rayon pool");
        // Avoid splitting short sorts and one-worker pools. Large snapshots use
        // this caller-owned pool; final publication still rechecks the deadline.
        #[cfg(feature = "rayon")]
        if self.parallel && self.threads() > 1 && rows.len() >= 16_384 {
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
        self.closed.load(Ordering::Acquire)
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
    pub(crate) fn check(&self) -> Result<()> {
        if self.closed.load(Ordering::Acquire) {
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
        let execute = || {
            evaluate(
                &self.graph,
                &self.sources,
                limits,
                cancellation,
                self.engine.parallel,
            )
        };
        #[cfg(feature = "rayon")]
        let evaluated = self.engine.pool.install(execute);
        #[cfg(not(feature = "rayon"))]
        let evaluated = execute();
        let rows = match evaluated {
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
