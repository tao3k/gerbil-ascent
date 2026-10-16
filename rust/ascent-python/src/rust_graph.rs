//! Python owns graph leases; the Rust Library owns composition and admission.
use crate::rust_api::{Evidence, Owner, cell, error};
use gerbil_ascent::{RelationalGraph, Row, Type};
use pyo3::{Bound, PyAny, PyRef, PyResult, Python, pyclass, pymethods, types::PyAnyMethods};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
type Transform = Arc<dyn Fn(RelationalGraph) -> gerbil_ascent::Result<RelationalGraph> + Send + Sync>;
enum GraphBody { Relation(RelationalGraph), Function { input: usize, output: usize, function: Transform } }

#[pyclass(name = "Graph", frozen)]
pub(super) struct Graph {
    engine: gerbil_ascent::Engine,
    body: GraphBody,
    closed: AtomicBool,
}
impl Graph {
    pub(super) fn source(
        engine: &Owner,
        name: &str,
        width: usize,
        rows: &Bound<'_, PyAny>,
    ) -> PyResult<Self> {
        if engine.0.is_closed() {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        let rows = rows
            .try_iter()?
            .map(|row| {
                row?.try_iter()?
                    .map(|v| cell(&v?, Type::Any))
                    .collect::<PyResult<Vec<_>>>()
                    .map(Row::from)
            })
            .collect::<PyResult<Vec<_>>>()?;
        Ok(Self::owned(
            engine.0.clone(),
            RelationalGraph::source(name, width, rows).map_err(error)?,
        ))
    }
    fn owned(engine: gerbil_ascent::Engine, graph: RelationalGraph) -> Self {
        Self {
            engine,
            body: GraphBody::Relation(graph),
            closed: AtomicBool::new(false),
        }
    }
    fn relation(&self) -> PyResult<&RelationalGraph> {
        self.check()?;
        match &self.body {
            GraphBody::Relation(graph) => Ok(graph),
            GraphBody::Function { .. } => Err(pyo3::exceptions::PyValueError::new_err("apply the higher-order Graph before opening a relation session")),
        }
    }
    fn function(engine: &Owner, input: usize, output: usize, function: Transform) -> PyResult<Self> {
        if engine.0.is_closed() { return Err(error(gerbil_ascent::Error::Closed)); }
        Ok(Self { engine: engine.0.clone(), body: GraphBody::Function { input, output, function }, closed: AtomicBool::new(false) })
    }
    pub(super) fn projection(engine: &Owner, input: usize, columns: Vec<usize>) -> PyResult<Self> {
        if input > 16 || columns.len() > 16 || columns.iter().any(|i| *i >= input) {
            return Err(pyo3::exceptions::PyValueError::new_err("projection column outside input"));
        }
        Self::function(engine, input, columns.len(), Arc::new(gerbil_ascent::make_projection_graph(columns)))
    }
    pub(super) fn transitive(engine: &Owner) -> PyResult<Self> {
        Self::function(engine, 2, 2, Arc::new(gerbil_ascent::make_transitive_graph()))
    }
    fn check(&self) -> PyResult<()> {
        if self.closed() {
            Err(error(gerbil_ascent::Error::Closed))
        } else {
            Ok(())
        }
    }
    fn pair(&self, other: &Self) -> PyResult<()> {
        self.check()?;
        other.check()?;
        if !self.engine.same_owner(&other.engine) {
            return Err(pyo3::exceptions::PyValueError::new_err(
                "foreign graph owner",
            ));
        }
        Ok(())
    }
}
#[pymethods]
impl Graph {
    #[getter]
    fn closed(&self) -> bool {
        self.closed.load(Ordering::Acquire) || self.engine.is_closed()
    }
    #[getter]
    fn width(&self) -> PyResult<usize> {
        self.check()?;
        Ok(match &self.body { GraphBody::Relation(graph) => graph.width(), GraphBody::Function { output, .. } => *output })
    }
    #[getter]
    fn input_width(&self) -> PyResult<Option<usize>> {
        self.check()?;
        Ok(match self.body { GraphBody::Function { input, .. } => Some(input), GraphBody::Relation(_) => None })
    }
    fn apply(&self, py: Python<'_>, argument: &Self) -> PyResult<Self> {
        self.pair(argument)?;
        let GraphBody::Function { input, output, function } = &self.body else {
            return Err(pyo3::exceptions::PyValueError::new_err("higher-order Graph required"));
        };
        let relation = argument.relation()?;
        if relation.width() != *input { return Err(pyo3::exceptions::PyValueError::new_err("Graph input width mismatch")); }
        let result = py.detach(|| function(relation.clone())).map_err(error)?;
        if result.width() != *output { return Err(pyo3::exceptions::PyValueError::new_err("Graph output width mismatch")); }
        Ok(Self::owned(self.engine.clone(), result))
    }
    fn then(&self, other: &Self) -> PyResult<Self> {
        self.pair(other)?;
        let (GraphBody::Function { input, output, function: first }, GraphBody::Function { input: next, output: final_width, function: second }) = (&self.body, &other.body) else {
            return Err(pyo3::exceptions::PyValueError::new_err("two higher-order Graphs required"));
        };
        if output != next { return Err(pyo3::exceptions::PyValueError::new_err("Graph composition width mismatch")); }
        Ok(Self { engine: self.engine.clone(), body: GraphBody::Function { input: *input, output: *final_width,
            function: Arc::new(gerbil_ascent::compose_graphs(first.clone(), second.clone())) }, closed: AtomicBool::new(false) })
    }
    fn project(&self, columns: Vec<usize>) -> PyResult<Self> {
        self.check()?;
        Ok(Self::owned(
            self.engine.clone(),
            self.relation()?.project(columns).map_err(error)?,
        ))
    }
    fn union(&self, other: &Self) -> PyResult<Self> {
        self.pair(other)?;
        Ok(Self::owned(
            self.engine.clone(),
            self.relation()?.union(other.relation()?).map_err(error)?,
        ))
    }
    fn join(&self, other: &Self, left_key: usize, right_key: usize) -> PyResult<Self> {
        self.pair(other)?;
        Ok(Self::owned(
            self.engine.clone(),
            self.relation()?
                .join(other.relation()?, left_key, right_key)
                .map_err(error)?,
        ))
    }
    #[pyo3(signature=(output,*,limits=None))]
    fn open_session(
        &self,
        py: Python<'_>,
        output: &str,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>,
    ) -> PyResult<Evidence> {
        self.check()?;
        let limits = limits.map(|p| p.0).unwrap_or_default();
        let relation = self.relation()?;
        py.detach(|| {
            self.engine
                .open_evidence_program(relation.evidence(output)?, limits)
        })
        .map(Evidence::owned)
        .map_err(error)
    }
    fn close(&self) {
        self.closed.store(true, Ordering::Release);
    }
    fn __enter__(slf: PyRef<'_, Self>) -> PyResult<PyRef<'_, Self>> {
        slf.check()?;
        Ok(slf)
    }
    fn __exit__(
        &self,
        _ty: &Bound<'_, PyAny>,
        _value: &Bound<'_, PyAny>,
        _traceback: &Bound<'_, PyAny>,
    ) {
        self.close();
    }
}
