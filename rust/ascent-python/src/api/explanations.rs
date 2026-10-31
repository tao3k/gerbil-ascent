//! Independent explanation leases over existing provenance and recorded metadata.
use super::{PyValueError, error, packets};
use gerbil_ascent::{Cancellation, SourceSession};
use pyo3::{
    Bound, Py, PyAny, PyRef, PyResult, Python, pyclass, pymethods,
    types::{PyDict, PyDictMethods},
};
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};

#[pyclass(name = "Explanation", frozen)]
pub(super) struct Explanation {
    proof: Mutex<gerbil_ascent::Provenance>,
    observation: gerbil_ascent::Data,
    source: Arc<Mutex<SourceSession>>,
    released: AtomicBool,
    generation: u64,
}
#[pymethods]
impl Explanation {
    #[getter]
    fn closed(&self, py: Python<'_>) -> PyResult<bool> {
        if self.released.load(Ordering::Acquire) {
            return Ok(true);
        }
        py.detach(|| {
            self.source
                .lock()
                .map(|source| source.is_closed())
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))
        })
    }
    #[getter]
    fn current(&self, py: Python<'_>) -> PyResult<bool> {
        if self.closed(py)? {
            return Ok(false);
        }
        py.detach(|| {
            let owner = self
                .proof
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?;
            match owner.graph() {
                Ok(_) => Ok(true),
                Err(gerbil_ascent::Error::Closed) => Ok(false),
                Err(failure) => Err(error(failure)),
            }
        })
    }
    #[getter]
    fn source_generation(&self, py: Python<'_>) -> PyResult<u64> {
        if self.closed(py)? {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        Ok(self.generation)
    }
    #[getter]
    fn graph(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        if self.closed(py)? {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        // Historical observations remain readable; current/verify retain their
        // separate generation-bound authority and cannot certify stale sources.
        packets::write(py, &self.observation)
    }
    fn summary<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let graph = py.detach(|| {
            self.proof
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?
                .graph()
                .map_err(error)
        })?;
        let out = PyDict::new(py);
        out.set_item("status", format!("{:?}", graph.status))?;
        out.set_item("sourceIdentity", graph.source_identity)?;
        out.set_item("sourceGeneration", graph.generation)?;
        out.set_item("query", &graph.query)?;
        out.set_item("nodes", graph.nodes.len())?;
        out.set_item("edges", graph.edges.len())?;
        out.set_item("roots", &graph.roots)?;
        Ok(out)
    }
    fn close(&self, py: Python<'_>) -> PyResult<()> {
        self.released.store(true, Ordering::Release);
        py.detach(|| {
            self.proof
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?
                .close();
            Ok(())
        })
    }
    fn verify(&self, py: Python<'_>) -> PyResult<bool> {
        if self.closed(py)? {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        py.detach(|| {
            let proof = self
                .proof
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?;
            let graph = proof.graph().map_err(error)?;
            proof
                .verify(
                    &graph,
                    &gerbil_ascent::ProvenanceLimits::default(),
                    &Cancellation::default(),
                )
                .map_err(error)
        })
    }
    fn __enter__<'py>(slf: PyRef<'py, Self>, py: Python<'py>) -> PyResult<PyRef<'py, Self>> {
        if slf.closed(py)? {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        Ok(slf)
    }
    fn __exit__(
        &self,
        py: Python<'_>,
        _ty: &Bound<'_, PyAny>,
        _value: &Bound<'_, PyAny>,
        _traceback: &Bound<'_, PyAny>,
    ) -> PyResult<()> {
        self.close(py)
    }
}
pub(super) fn explanation(
    py: Python<'_>,
    owner: &Arc<Mutex<SourceSession>>,
    handle: u64,
    relation: &str,
) -> PyResult<Explanation> {
    py.detach(|| {
        let source = owner.clone();
        let owner = owner
            .lock()
            .map_err(|_| PyValueError::new_err("owner lock poisoned"))?;
        let metadata = owner
            .explanation_metadata(handle, relation)
            .map_err(error)?;
        let provenance = owner
            .provenance(
                handle,
                relation,
                &gerbil_ascent::ProvenanceLimits::default(),
                &Cancellation::default(),
            )
            .map_err(error)?;
        let generation = provenance.graph().map_err(error)?.generation;
        Ok(Explanation {
            proof: Mutex::new(provenance),
            observation: metadata,
            source,
            released: AtomicBool::new(false),
            generation,
        })
    })
}
