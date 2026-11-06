//! Typed provenance ownership and observation; no Python proof interpreter.
use super::{
    types::Cancellation,
    types::{ceiling, source_error},
};
use gerbil_ascent as engine;
use pyo3::{
    Bound, PyAny, PyRef, PyResult, Python, pyclass, pymethods,
    types::{PyDict, PyDictMethods, PyList, PyListMethods},
};
#[pyclass(name = "ProvenanceLimits", frozen)]
#[derive(Clone)]
pub(super) struct ProvenanceLimits(pub(super) engine::ProvenanceLimits);
#[pymethods]
impl ProvenanceLimits {
    #[new]
    #[pyo3(signature=(*,max_steps=None,max_nodes=None,max_edges=None))]
    fn new(
        max_steps: Option<&Bound<'_, PyAny>>,
        max_nodes: Option<&Bound<'_, PyAny>>,
        max_edges: Option<&Bound<'_, PyAny>>,
    ) -> PyResult<Self> {
        Ok(Self(engine::ProvenanceLimits {
            max_steps: ceiling(max_steps)?.unwrap_or(100_000),
            max_nodes: ceiling(max_nodes)?.unwrap_or(4096),
            max_edges: ceiling(max_edges)?.unwrap_or(4096),
            ..engine::ProvenanceLimits::default()
        }))
    }
}
#[pyclass(name = "Provenance", frozen)]
pub(super) struct Provenance(pub(super) Proof);
pub(super) enum Proof {
    Core(engine::Provenance),
    Scheme(ascent_scheme::SchemeProvenance),
}
impl Proof {
    fn graph(&self) -> engine::Result<std::sync::Arc<engine::ProvenanceGraph>> {
        match self {
            Self::Core(p) => p.graph(),
            Self::Scheme(p) => p.graph(),
        }
    }
    fn verify(
        &self,
        g: &engine::ProvenanceGraph,
        l: &engine::ProvenanceLimits,
        c: &engine::Cancellation,
    ) -> engine::Result<bool> {
        match self {
            Self::Core(p) => p.verify(g, l, c),
            Self::Scheme(p) => p.verify(g, l, c),
        }
    }
    fn close(&self) {
        match self {
            Self::Core(p) => p.close(),
            Self::Scheme(p) => p.close(),
        }
    }
}
#[pymethods]
impl Provenance {
    #[getter]
    fn graph<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let graph = self.0.graph().map_err(source_error)?;
        let out = PyDict::new(py);
        let status = match graph.status {
            engine::ProvenanceStatus::Complete => "complete",
            engine::ProvenanceStatus::ClosedAbsent => "closed-absent",
            engine::ProvenanceStatus::Bounded => "bounded",
            engine::ProvenanceStatus::Unsupported => "unsupported",
            engine::ProvenanceStatus::Invalid => "invalid",
        };
        out.set_item("status", status)?;
        out.set_item("checkerVersion", graph.checker_version)?;
        out.set_item("sourceGeneration", graph.generation)?;
        out.set_item("sourceIdentity", graph.source_identity)?;
        out.set_item("query", &graph.query)?;
        out.set_item("roots", &graph.roots)?;
        let nodes = PyList::empty(py);
        for (id, node) in graph.nodes.iter().enumerate() {
            let value = PyDict::new(py);
            value.set_item("id", id)?;
            value.set_item("relation", &node.relation)?;
            value.set_item("source", node.source)?;
            value.set_item(
                "row",
                super::graphs::rows(py, std::slice::from_ref(&node.row))?,
            )?;
            nodes.append(value)?;
        }
        out.set_item("nodes", nodes)?;
        let edges = PyList::empty(py);
        for edge in &graph.edges {
            let value = PyDict::new(py);
            value.set_item("output", edge.output)?;
            value.set_item("rule", edge.rule)?;
            value.set_item("inputs", &edge.inputs)?;
            value.set_item(
                "witnesses",
                super::proof_observations::witnesses(py, &edge.witnesses)?,
            )?;
            edges.append(value)?;
        }
        out.set_item("edges", edges)?;
        Ok(out)
    }
    #[pyo3(signature=(*,limits=None,cancellation=None))]
    fn verify(
        &self,
        py: Python<'_>,
        limits: Option<PyRef<'_, ProvenanceLimits>>,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<bool> {
        let limits = limits.map(|l| l.0.clone()).unwrap_or_default();
        let cancel = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        py.detach(|| {
            let graph = self.0.graph()?;
            self.0.verify(&graph, &limits, &cancel)
        })
        .map_err(source_error)
    }
    fn close(&self) {
        self.0.close();
    }
    fn __enter__(slf: PyRef<'_, Self>) -> PyRef<'_, Self> {
        slf
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
