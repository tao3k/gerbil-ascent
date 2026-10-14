//! Constructor sessions execute and validate entirely in Rust.
use super::{module_values, sources, types::Cancellation, types::source_error};
use pyo3::{
    Bound, PyAny, PyRef, PyResult, Python, pyclass, pymethods,
    types::{PyAnyMethods, PyDict, PyDictMethods},
};
use std::collections::BTreeMap;
#[pyclass(name = "EvidenceSession", frozen)]
pub(super) struct EvidenceSession(pub(super) ascent_scheme::Evidence);
#[pymethods]
impl EvidenceSession {
    #[getter]
    fn closed(&self) -> bool {
        self.0.is_closed()
    }
    #[getter]
    fn projection<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        super::packets::write(py, &self.0.projection().map_err(source_error)?)?
            .bind(py)
            .cast::<PyDict>()
            .cloned()
            .map_err(Into::into)
    }
    #[getter]
    fn descriptors<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, pyo3::types::PyList>> {
        super::packets::write(py, &self.0.descriptors().map_err(source_error)?)?
            .bind(py)
            .cast::<pyo3::types::PyList>()
            .cloned()
            .map_err(Into::into)
    }
    #[getter]
    fn queries(&self) -> PyResult<Vec<String>> {
        self.0.queries().map_err(source_error)
    }
    #[getter]
    fn fact_limits<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        sources::policy(py, self.0.fact_limits().map_err(source_error)?, true)
    }

    #[pyo3(signature=(timeout_nanoseconds=1_000_000_000,*,queries=None,cancellation=None))]
    fn run<'py>(
        &self,
        py: Python<'py>,
        timeout_nanoseconds: u64,
        queries: Option<Vec<String>>,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<Bound<'py, PyDict>> {
        let limits = sources::runtime_limits(timeout_nanoseconds)?;
        let cancel = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        let observation = py
            .detach(|| self.0.run(queries.as_deref(), &limits, &cancel))
            .map_err(source_error)?;
        drop(queries);
        super::packets::write(py, &observation)?
            .bind(py)
            .cast::<PyDict>()
            .cloned()
            .map_err(Into::into)
    }
    fn result(&self, receipt: &Bound<'_, PyAny>) -> PyResult<EvidenceResult> {
        let handle = super::types::result_handle(&receipt.get_item("resultHandle")?)?;
        self.0
            .result(handle)
            .map(|result| EvidenceResult {
                owner: self.0.clone(),
                result,
                handle,
            })
            .map_err(source_error)
    }
    #[pyo3(signature=(sources,*,timeout_nanoseconds=1_000_000_000,cancellation=None))]
    fn replace<'py>(
        &self,
        py: Python<'py>,
        sources: &Bound<'_, PyDict>,
        timeout_nanoseconds: u64,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<Bound<'py, PyDict>> {
        let limits = sources::runtime_limits(timeout_nanoseconds)?;
        let mut updates = BTreeMap::new();
        for (name, rows) in sources.iter() {
            let rows = rows
                .try_iter()?
                .map(|row| {
                    row?.try_iter()?
                        .map(|cell| module_values::input(&cell?, 0))
                        .collect::<PyResult<Vec<_>>>()
                })
                .collect::<PyResult<Vec<_>>>()?;
            updates.insert(name.extract::<String>()?, rows);
        }
        let cancel = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        let generation = py
            .detach(|| self.0.replace(updates, &limits, &cancel))
            .map_err(source_error)?;
        let out = PyDict::new(py);
        out.set_item("updated", true)?;
        out.set_item("sourceGeneration", generation)?;
        Ok(out)
    }
    fn close(&self, py: Python<'_>) {
        py.detach(|| self.0.close());
    }
    fn __enter__(slf: PyRef<'_, Self>) -> PyRef<'_, Self> {
        slf
    }
    fn __exit__(
        &self,
        py: Python<'_>,
        _ty: &Bound<'_, PyAny>,
        _value: &Bound<'_, PyAny>,
        _traceback: &Bound<'_, PyAny>,
    ) {
        self.close(py);
    }
}
#[pyclass(name = "EvidenceResult", frozen)]
pub(super) struct EvidenceResult {
    owner: ascent_scheme::Evidence,
    result: ascent_scheme::EvidenceResult,
    handle: u64,
}
#[pymethods]
impl EvidenceResult {
    #[getter]
    fn closed(&self) -> bool {
        self.result.is_released()
    }
    fn reference(
        &self,
        relation: &str,
        row: usize,
        column: usize,
    ) -> PyResult<super::types::ResultValue> {
        self.result
            .value(relation, row, column)
            .map(|v| super::types::ResultValue(super::types::CellValue::Scheme(v)))
            .map_err(source_error)
    }

    fn rows<'py>(&self, py: Python<'py>, relation: &str) -> PyResult<Bound<'py, PyDict>> {
        let observation = self.result.rows(relation).map_err(source_error)?;
        super::packets::write(py, &observation)?
            .bind(py)
            .cast::<PyDict>()
            .cloned()
            .map_err(Into::into)
    }

    fn explanation(&self, py: Python<'_>, relation: &str) -> PyResult<Explanation> {
        self.result.rows(relation).map_err(source_error)?;
        py.detach(|| self.owner.explain(self.handle, relation))
            .map(Explanation)
            .map_err(source_error)
    }
    #[pyo3(signature=(relation,*,limits=None,cancellation=None))]
    fn provenance(
        &self,
        py: Python<'_>,
        relation: &str,
        limits: Option<PyRef<'_, super::provenance::ProvenanceLimits>>,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<super::provenance::Provenance> {
        self.result.rows(relation).map_err(source_error)?;
        let limits = limits.map(|l| l.0.clone()).unwrap_or_default();
        let cancel = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        py.detach(|| {
            self.owner
                .provenance(self.handle, relation, &limits, &cancel)
        })
        .map(super::provenance::Provenance)
        .map_err(source_error)
    }
    fn close(&self) {
        self.result.close();
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
#[pyclass(name = "Explanation", frozen)]
pub(super) struct Explanation(ascent_scheme::Explanation);
#[pymethods]
impl Explanation {
    #[getter]
    fn closed(&self) -> bool {
        self.0.is_closed()
    }
    #[getter]
    fn current(&self) -> bool {
        self.0.is_current()
    }
    #[getter]
    fn source_generation(&self) -> u64 {
        self.0.source_generation()
    }
    #[getter]
    fn graph<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let graph = self.0.graph().map_err(source_error)?;
        super::packets::write(py, &graph)?
            .bind(py)
            .cast::<PyDict>()
            .cloned()
            .map_err(Into::into)
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
