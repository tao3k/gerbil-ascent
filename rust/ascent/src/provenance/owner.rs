//! Bounded stratified provenance replay, independent from the execution kernel.
use crate::{Cancellation, Error, Program, Result, Row, SourceResult};
use std::{sync::Arc, time::Duration};
/// Publication status; unsupported/exhausted replay never publishes a partial graph.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProvenanceStatus {
    Complete,
    ClosedAbsent,
    Bounded,
    Unsupported,
    Invalid,
}
/// Independent replay limits include unsuccessful row probes and graph material.
#[derive(Clone, Debug)]
pub struct ProvenanceLimits {
    pub max_steps: usize,
    pub max_nodes: usize,
    pub max_edges: usize,
    pub timeout: Duration,
}
impl Default for ProvenanceLimits {
    fn default() -> Self {
        Self {
            max_steps: 100_000,
            max_nodes: 4096,
            max_edges: 4096,
            timeout: Duration::from_secs(1),
        }
    }
}
/// Ground fact identity, distinct from its possibly recursive alternatives.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProvenanceNode {
    pub relation: String,
    pub row: Row,
    pub source: bool,
}
/// One grounded rule alternative. `None` marks an admitted initial fact.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ProvenanceEdge {
    pub witnesses: Vec<ProvenanceWitness>,
    pub output: usize,
    pub rule: Option<usize>,
    pub inputs: Vec<usize>,
}
/// Complete lower-stratum absence/aggregate observations and checked scalar factors.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum ProvenanceWitness {
    Absent(crate::Atom),
    Guard(crate::Expression),
    Compute {
        slot: u32,
        expression: crate::Expression,
        value: crate::Value,
    },
    Aggregate {
        atom: crate::Atom,
        operator: crate::Reducer,
        rows: Vec<usize>,
        value: crate::Value,
    },
}
/// Finite recursive equations. Cyclic edges are intentional; nodes are finite.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ProvenanceGraph {
    pub status: ProvenanceStatus,
    pub checker_version: u32,
    pub source_identity: u64,
    pub generation: u64,
    pub query: String,
    pub nodes: Vec<ProvenanceNode>,
    pub edges: Vec<ProvenanceEdge>,
    pub roots: Vec<usize>,
}
impl ProvenanceGraph {
    pub(super) fn empty(
        status: ProvenanceStatus,
        source_identity: u64,
        generation: u64,
        query: &str,
    ) -> Self {
        Self {
            status,
            source_identity,
            checker_version: 3,
            generation,
            query: query.into(),
            nodes: Vec::new(),
            edges: Vec::new(),
            roots: Vec::new(),
        }
    }
}
/// Source-bound observation. Holds an independent lease, never authority to execute a task.
pub struct Provenance {
    program: Program,
    query_internal: String,
    result: SourceResult,
    graph: Arc<ProvenanceGraph>,
}
impl Provenance {
    pub(crate) fn generate(
        program: Program,
        result: &SourceResult,
        query: &str,
        limits: &ProvenanceLimits,
        cancel: &Cancellation,
    ) -> Result<Self> {
        result.rows(query)?;
        let query_internal = result.resolve(query)?.to_string();
        let mut graph = super::replay::generate(&program, result, &query_internal, limits, cancel)?;
        graph.query = query.into();
        let result = result.fork()?;
        Ok(Self {
            program,
            query_internal,
            result,
            graph: Arc::new(graph),
        })
    }
    /// # Errors
    /// Rejects stale source generations and closed/released owners.
    pub fn graph(&self) -> Result<Arc<ProvenanceGraph>> {
        self.result.generation()?;
        Ok(self.graph.clone())
    }
    /// Replays the exact admitted program/current sources independently of Rayon.
    /// # Errors
    /// Invalid limits, cancellation or stale observation authority fail closed.
    pub fn verify(
        &self,
        candidate: &ProvenanceGraph,
        limits: &ProvenanceLimits,
        cancel: &Cancellation,
    ) -> Result<bool> {
        self.result.generation()?;
        if !matches!(
            candidate.status,
            ProvenanceStatus::Complete | ProvenanceStatus::ClosedAbsent
        ) {
            return Ok(false);
        }
        let mut expected = super::replay::generate(
            &self.program,
            &self.result,
            &self.query_internal,
            limits,
            cancel,
        )?;
        expected.query.clone_from(&self.graph.query);
        self.result.generation()?;
        Ok(&expected == candidate)
    }
    pub fn close(&self) {
        self.result.close();
    }
}
impl Drop for Provenance {
    fn drop(&mut self) {
        self.close();
    }
}
pub(super) fn invalid(message: &str) -> Error {
    Error::InvalidUpdate(message.into())
}
