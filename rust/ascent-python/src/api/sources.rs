//! `PyO3` source sessions expose Rust-owned transactions and result lifetimes.
use super::types::{ceiling, source_error};
use super::{
    conversion::{descriptors, relation_rows, typed_rows},
    graphs,
    types::{Cancellation, EngineError},
};
use gerbil_ascent as engine;
use pyo3::{
    Bound, PyAny, PyRef, PyResult, Python, pyclass, pymethods,
    types::{PyAnyMethods, PyDictMethods, PyTupleMethods},
    types::{PyDict, PyList, PyTuple},
};
use std::{collections::BTreeMap, sync::Mutex, time::Duration};
#[pyclass(name = "FactLimits", frozen)]
#[derive(Clone, Copy, Default)]
pub(super) struct FactLimits(pub(super) engine::FactLimits);
#[pymethods]
impl FactLimits {
    #[new]
    #[pyo3(signature=(input=None,derived=None,output=None))]
    fn new(
        input: Option<&Bound<'_, PyAny>>,
        derived: Option<&Bound<'_, PyAny>>,
        output: Option<&Bound<'_, PyAny>>,
    ) -> PyResult<Self> {
        Ok(Self(engine::FactLimits {
            input: ceiling(input)?,
            derived: ceiling(derived)?,
            output: ceiling(output)?,
        }))
    }
    #[getter]
    fn input(&self) -> Option<usize> {
        self.0.input
    }
    #[getter]
    fn derived(&self) -> Option<usize> {
        self.0.derived
    }
    #[getter]
    fn output(&self) -> Option<usize> {
        self.0.output
    }
    fn wire<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        policy(py, self.0, false)
    }
}
pub(super) fn policy(
    py: Python<'_>,
    limits: engine::FactLimits,
    unlimited: bool,
) -> PyResult<Bound<'_, PyDict>> {
    let out = PyDict::new(py);
    for (name, value) in [
        ("input", limits.input),
        ("derived", limits.derived),
        ("output", limits.output),
    ] {
        if let Some(value) = value {
            out.set_item(name, value)?;
        } else if unlimited {
            out.set_item(name, "unlimited")?;
        }
    }
    Ok(out)
}
pub(super) fn texts(sources: &Bound<'_, PyTuple>) -> PyResult<Vec<String>> {
    sources.iter().map(|v| v.extract::<String>()).collect()
}
pub(super) fn runtime_limits(timeout_nanoseconds: u64) -> PyResult<engine::Limits> {
    if timeout_nanoseconds > 1_000_000_000 {
        return Err(EngineError::new_err("native DSL deadline contract"));
    }
    Ok(engine::Limits {
        timeout: Duration::from_nanos(timeout_nanoseconds),
        ..engine::SourceSession::default_limits()
    })
}
fn replacements(
    input: &Bound<'_, PyAny>,
    descriptors: &[engine::Relation],
) -> PyResult<BTreeMap<String, Vec<engine::Row>>> {
    let entries: Vec<(String, Bound<'_, PyAny>)> = if let Ok(mapping) = input.cast::<PyDict>() {
        mapping
            .iter()
            .map(|(key, rows)| Ok((key.extract()?, rows)))
            .collect::<PyResult<_>>()?
    } else {
        input
            .try_iter()?
            .map(|entry| {
                let entry = entry?;
                Ok((
                    entry.get_item("relation")?.extract()?,
                    entry.get_item("rows")?,
                ))
            })
            .collect::<PyResult<_>>()?
    };
    let descriptors: BTreeMap<_, _> = descriptors.iter().map(|r| (r.name.as_str(), r)).collect();
    let mut out = BTreeMap::new();
    for (name, input) in entries {
        let declaration = descriptors
            .get(name.as_str())
            .ok_or_else(|| EngineError::new_err("unknown source"))?;
        if !declaration.source {
            return Err(EngineError::new_err(
                "derived relation is not source authority",
            ));
        }
        if out.insert(name, typed_rows(&input, declaration)?).is_some() {
            return Err(EngineError::new_err("duplicate source update"));
        }
    }
    Ok(out)
}
pub(super) fn receipt(
    py: Python<'_>,
    result: engine::SourceObservation,
) -> PyResult<Bound<'_, PyDict>> {
    let out = PyDict::new(py);
    let relations = PyDict::new(py);
    let partial = result
        .relations
        .values()
        .flatten()
        .flat_map(|row| row.iter())
        .any(|v| matches!(v, engine::Value::Object(_)));
    for (name, rows) in result.relations {
        relations.set_item(name, relation_rows(py, &rows)?)?;
    }
    out.set_item("complete", result.complete)?;
    out.set_item("relations", relations)?;
    out.set_item("resultHandle", result.result_handle)?;
    out.set_item("sourceGeneration", result.source_generation)?;
    out.set_item("runIndex", result.run_index)?;
    out.set_item("nativeResultReused", result.reused)?;
    out.set_item(
        "scalarProjection",
        if partial { "partial" } else { "supported" },
    )?;
    out.set_item(
        "evaluationPath",
        if result.evaluated {
            "recomputed"
        } else {
            "retained"
        },
    )?;
    out.set_item("activeRuleCount", result.active_rule_count)?;
    out.set_item("reusedRelations", result.reused_relations)?;
    Ok(out)
}
#[pyclass(name = "SourceSession", frozen)]
pub(super) struct SourceSession(pub(super) Mutex<engine::SourceSession>);
impl SourceSession {
    pub(super) fn owned(session: engine::SourceSession) -> Self {
        Self(Mutex::new(session))
    }
    fn lock(&self) -> PyResult<std::sync::MutexGuard<'_, engine::SourceSession>> {
        self.0
            .lock()
            .map_err(|_| pyo3::exceptions::PyRuntimeError::new_err("source session lock poisoned"))
    }
}
#[pymethods]
impl SourceSession {
    #[getter]
    fn descriptors<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyList>> {
        let values = py.detach(|| self.lock().map(|session| session.descriptors().to_vec()))?;
        descriptors(py, &values)
    }
    #[getter]
    fn projection<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let program = py.detach(|| self.lock().map(|session| session.program().clone()))?;
        super::catalog::projection(py, &program)
    }
    #[getter]
    fn queries<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyTuple>> {
        let queries = py.detach(|| self.lock().map(|session| session.queries().to_vec()))?;
        PyTuple::new(py, queries)
    }
    #[getter]
    fn fact_limits<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let limits = py.detach(|| self.lock().map(|session| session.fact_limits()))?;
        policy(py, limits, true)
    }
    #[pyo3(signature=(sources,*,timeout_nanoseconds=1_000_000_000,cancellation=None))]
    fn replace<'py>(
        &self,
        py: Python<'py>,
        sources: &Bound<'_, PyAny>,
        timeout_nanoseconds: u64,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<Bound<'py, PyDict>> {
        let mut limits = runtime_limits(timeout_nanoseconds)?;
        let deadline = super::types::admission_deadline(limits.timeout).map_err(source_error)?;
        let cancellation = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        let descriptors = py
            .detach(|| {
                super::types::lock_before(&self.0, deadline, &cancellation)
                    .map(|session| session.descriptors().to_vec())
            })
            .map_err(source_error)?;
        let updates = replacements(sources, &descriptors)?;
        let generation = py.detach(|| {
            let mut session = super::types::lock_before(&self.0, deadline, &cancellation)
                .map_err(source_error)?;
            limits.timeout = super::types::remaining(deadline).map_err(source_error)?;
            session
                .replace(updates, &limits, &cancellation)
                .map_err(source_error)
        })?;
        let out = PyDict::new(py);
        out.set_item("updated", true)?;
        out.set_item("sourceGeneration", generation)?;
        Ok(out)
    }
    #[pyo3(signature=(timeout_nanoseconds=1_000_000_000,*,queries=None,cancellation=None))]
    fn run<'py>(
        &self,
        py: Python<'py>,
        timeout_nanoseconds: u64,
        queries: Option<Vec<String>>,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<Bound<'py, PyDict>> {
        let mut limits = runtime_limits(timeout_nanoseconds)?;
        let deadline = super::types::admission_deadline(limits.timeout).map_err(source_error)?;
        let cancellation = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        let result = py.detach(|| {
            let mut session = super::types::lock_before(&self.0, deadline, &cancellation)
                .map_err(source_error)?;
            limits.timeout = super::types::remaining(deadline).map_err(source_error)?;
            session
                .run(queries.as_deref(), &limits, &cancellation)
                .map_err(source_error)
        })?;
        drop(queries);
        receipt(py, result)
    }
    fn result(&self, py: Python<'_>, receipt: &Bound<'_, PyAny>) -> PyResult<ResultOwner> {
        let handle = super::types::result_handle(&receipt.get_item("resultHandle")?)?;
        py.detach(|| {
            self.lock()?
                .result(handle)
                .map(|result| ResultOwner { result, handle })
                .map_err(source_error)
        })
    }
    #[pyo3(signature=(receipt,relation,*,limits=None,cancellation=None))]
    fn provenance(
        &self,
        py: Python<'_>,
        receipt: &Bound<'_, PyAny>,
        relation: &str,
        limits: Option<PyRef<'_, super::provenance::ProvenanceLimits>>,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<super::provenance::Provenance> {
        let handle = super::types::result_handle(&receipt.get_item("resultHandle")?)?;
        let mut limits = limits.map(|l| l.0.clone()).unwrap_or_default();
        let deadline = super::types::admission_deadline(limits.timeout).map_err(source_error)?;
        let cancel = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        py.detach(|| {
            let session =
                super::types::lock_before(&self.0, deadline, &cancel).map_err(source_error)?;
            limits.timeout = super::types::remaining(deadline).map_err(source_error)?;
            session
                .provenance(handle, relation, &limits, &cancel)
                .map(|p| super::provenance::Provenance(super::provenance::Proof::Core(p)))
                .map_err(source_error)
        })
    }
    fn close(&self, py: Python<'_>) -> PyResult<()> {
        py.detach(|| {
            self.lock()?.close();
            Ok(())
        })
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
    ) -> PyResult<()> {
        self.close(py)
    }
}
#[pyclass(name = "Result", frozen)]
pub(super) struct ResultOwner {
    result: engine::SourceResult,
    handle: u64,
}
#[pymethods]
impl ResultOwner {
    fn reference(
        &self,
        relation: &str,
        row: usize,
        column: usize,
    ) -> PyResult<super::types::ResultValue> {
        self.result
            .value(relation, row, column)
            .map(|v| super::types::ResultValue(super::types::CellValue::Core(v)))
            .map_err(source_error)
    }

    #[new]
    fn new(
        py: Python<'_>,
        session: PyRef<'_, SourceSession>,
        handle: &Bound<'_, PyAny>,
    ) -> PyResult<Self> {
        let handle = super::types::result_handle(handle)?;
        let source: &SourceSession = &session;
        let result = py.detach(|| source.lock()?.result(handle).map_err(source_error))?;
        drop(session);
        Ok(Self { result, handle })
    }
    fn rows<'py>(&self, py: Python<'py>, relation: &str) -> PyResult<Bound<'py, PyDict>> {
        let rows = self.result.rows(relation).map_err(source_error)?;
        let out = PyDict::new(py);
        out.set_item("resultHandle", self.handle)?;
        out.set_item(
            "sourceGeneration",
            self.result.generation().map_err(source_error)?,
        )?;
        out.set_item("value", graphs::rows(py, rows)?)?;
        Ok(out)
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
