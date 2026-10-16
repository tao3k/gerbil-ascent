//! Rust-only declaration loading and execution; Python transports owned values.
use gerbil_ascent::{Cancellation, Engine, Row, SourceSession, Type, Value};
use gerbil_scheme_python::{OwnedValue, ValueLimits};
use pyo3::{
    Bound, Py, PyAny, PyErr, PyRef, PyResult, Python, pyclass, pymethods, pymodule,
    types::{
        PyAnyMethods, PyDict, PyDictMethods, PyModule, PyModuleMethods, PyTuple, PyTupleMethods,
    },
    wrap_pyfunction,
};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex},
    time::Duration,
};
#[path = "rust_bindings.rs"]
mod bindings;
#[path = "api/computational.rs"]
mod computational;
#[path = "api/conversation.rs"]
mod conversation;
#[path = "api/derivations.rs"]
mod derivations;
#[path = "api/domain.rs"]
mod domain;
#[path = "api/evidence_conversation.rs"]
mod evidence_conversation;
#[path = "rust_exports.rs"]
mod exports;
#[path = "api/interaction.rs"]
mod interaction;
#[path = "transport.rs"]
pub(super) mod packets;
#[path = "api/review.rs"]
mod review;
#[path = "rust_sources.rs"]
mod sources;
#[path = "api/trajectory.rs"]
mod trajectory;
#[path = "rust_errors.rs"]
mod types;
pyo3::create_exception!(ascent, EngineError, pyo3::exceptions::PyValueError);
use EngineError as PyValueError;

pub(super) fn error(e: impl std::fmt::Display) -> PyErr {
    PyValueError::new_err(e.to_string())
}

#[pyclass(name = "Engine", frozen)]
pub(super) struct Owner(pub(super) Engine);
#[pymethods]
impl Owner {
    #[pyo3(signature=(source,constructor=None,*,trusted=false,limits=None,diagnostics=false))]
    fn dsl(&self, source: &str, constructor: Option<&str>, trusted: bool,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>, diagnostics: bool) -> PyResult<crate::core_abi::CoreSession> {
        if !trusted { return Err(PyValueError::new_err("explicit trusted DSL admission required")); }
        crate::core_abi::CoreSession::open(self.0.clone(), source, constructor,
            limits.map(|p| p.0).unwrap_or_default(), diagnostics)
    }
    #[pyo3(signature=(graph,*,trusted=false,limits=None,diagnostics=false))]
    fn core_graph(&self, graph: &Bound<'_, PyAny>, trusted: bool,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>, diagnostics: bool) -> PyResult<crate::core_abi::CoreSession> {
        if !trusted { return Err(PyValueError::new_err("explicit trusted Graph admission required")); }
        crate::core_abi::CoreSession::open_graph(self.0.clone(), graph,
            limits.map(|p| p.0).unwrap_or_default(), diagnostics)
    }
    #[pyo3(signature=(components,entry,constructor=None,*,trusted=false,limits=None,diagnostics=false))]
    fn core_components(&self, components: &Bound<'_, PyAny>, entry: &str,
        constructor: Option<&str>, trusted: bool,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>, diagnostics: bool) -> PyResult<crate::core_abi::CoreSession> {
        if !trusted { return Err(PyValueError::new_err("explicit trusted DSL admission required")); }
        crate::core_abi::CoreSession::open_components(self.0.clone(), components, entry, constructor,
            limits.map(|p| p.0).unwrap_or_default(), diagnostics)
    }
    #[pyo3(signature=(source,constructor=None,*,trusted=false,limits=None,diagnostics=false))]
    fn core_evidence(&self, source: &str, constructor: Option<&str>, trusted: bool,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>, diagnostics: bool) -> PyResult<crate::core_abi::CoreSession> {
        if !trusted { return Err(PyValueError::new_err("explicit trusted DSL admission required")); }
        crate::core_abi::CoreSession::open(self.0.clone(), source, constructor,
            limits.map(|p| p.0).unwrap_or_default(), diagnostics)
    }
    #[new]
    #[pyo3(signature=(*,backend="rust",workers=1))]
    fn new(backend: &str, workers: usize) -> PyResult<Self> {
        let workers = gerbil_scheme_python::select_backend(backend, None, Some(workers))
            .map_err(|e| PyValueError::new_err(e.to_string()))?;
        Engine::new(workers).map(Self).map_err(error)
    }
    #[classattr]
    fn backend() -> &'static str {
        "rust"
    }
    #[getter]
    fn closed(&self) -> bool {
        self.0.is_closed()
    }
    fn describe(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        packets::write(
            py,
            &gerbil_ascent::Data::object([
                ("schema", "ascent.rust-library.v1".into()),
                ("abi", 1_u64.into()),
                ("backend", "rust".into()),
                (
                    "workers",
                    gerbil_ascent::Data::Integer(self.0.threads().into()),
                ),
                ("schemeVm", false.into()),
                (
                    "operations",
                    gerbil_ascent::Data::List(
                        [
                            "open-evidence",
                            "open-components",
                            "open-sources",
                            "open-rule-sources",
                            "open-catalog",
                            "result-owner",
                            "source-replace",
                            "source-run",
                            "close",
                            "evidence-dag",
                        ]
                        .into_iter()
                        .map(Into::into)
                        .collect(),
                    ),
                ),
                ("ruleTextContract", "inert-relational-subset.v1".into()),
            ]),
        )
    }
    #[pyo3(signature=(source,constructor=None,*,trusted=false,limits=None))]
    fn evidence(
        &self,
        py: Python<'_>,
        source: &str,
        constructor: Option<&str>,
        trusted: bool,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>,
    ) -> PyResult<Evidence> {
        if !trusted {
            return Err(PyValueError::new_err(
                "explicit trusted DSL admission required",
            ));
        }
        let limits = limits.map(|p| p.0).unwrap_or_default();
        py.detach(|| self.0.open_evidence_sources(&[source], constructor, limits))
            .map(Evidence::owned)
            .map_err(error)
    }
    #[pyo3(signature=(manifest,sources,entry,*,trusted=false))]
    fn components(
        &self,
        manifest: &Bound<'_, PyAny>,
        sources: &Bound<'_, PyAny>,
        entry: &str,
        trusted: bool,
    ) -> PyResult<crate::rust_components::Components> {
        crate::rust_components::Components::new(self, manifest, sources, entry, trusted)
    }
    fn source_graph(&self, name: &str, width: usize, rows: &Bound<'_, PyAny>) -> PyResult<crate::rust_graph::Graph> {
        crate::rust_graph::Graph::source(self, name, width, rows)
    }
    fn projection_graph(&self, input_width: usize, columns: Vec<usize>) -> PyResult<crate::rust_graph::Graph> {
        crate::rust_graph::Graph::projection(self, input_width, columns)
    }
    fn transitive_graph(&self) -> PyResult<crate::rust_graph::Graph> {
        crate::rust_graph::Graph::transitive(self)
    }
    #[pyo3(signature=(*texts, limits=None))]
    fn open_sources(
        &self,
        py: Python<'_>,
        texts: &Bound<'_, PyTuple>,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>,
    ) -> PyResult<Evidence> {
        let texts = texts
            .iter()
            .map(|t| t.extract::<String>())
            .collect::<PyResult<Vec<_>>>()?;
        let limits = limits.map(|p| p.0).unwrap_or_default();
        py.detach(|| {
            self.0.open_sources(
                &texts.iter().map(String::as_str).collect::<Vec<_>>(),
                limits,
            )
        })
        .map(Evidence::owned)
        .map_err(error)
    }
    #[pyo3(signature=(*texts, limits=None))]
    fn open_rule_sources(
        &self,
        py: Python<'_>,
        texts: &Bound<'_, PyTuple>,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>,
    ) -> PyResult<Evidence> {
        let texts = texts
            .iter()
            .map(|t| t.extract::<String>())
            .collect::<PyResult<Vec<_>>>()?;
        let limits = limits.map(|p| p.0).unwrap_or_default();
        py.detach(|| {
            self.0.open_rule_sources(
                &texts.iter().map(String::as_str).collect::<Vec<_>>(),
                limits,
            )
        })
        .map(Evidence::owned)
        .map_err(error)
    }
    #[staticmethod]
    #[pyo3(signature=(*texts))]
    fn read_rules(py: Python<'_>, texts: &Bound<'_, PyTuple>) -> PyResult<Py<PyAny>> {
        let texts = texts
            .iter()
            .map(|t| t.extract::<String>())
            .collect::<PyResult<Vec<_>>>()?;
        let catalog = py
            .detach(|| {
                let program = gerbil_ascent::Program::read_rule_sources(
                    &texts.iter().map(String::as_str).collect::<Vec<_>>(),
                )?;
                let queries = program
                    .relations
                    .iter()
                    .map(|r| r.name.clone())
                    .collect::<Vec<_>>();
                let encoded = gerbil_ascent::Catalog::encode(&program, &queries)?;
                Ok::<_, gerbil_ascent::Error>(gerbil_ascent::Data::object([
                    ("relations", encoded.field("relations")?.clone()),
                    ("rules", encoded.field("rules")?.clone()),
                ]))
            })
            .map_err(error)?;
        packets::write(py, &catalog)
    }
    #[pyo3(signature=(program,*,limits=None))]
    fn open(
        &self,
        py: Python<'_>,
        program: &Bound<'_, PyAny>,
        limits: Option<PyRef<'_, crate::rust_components::Policy>>,
    ) -> PyResult<Evidence> {
        let catalog = gerbil_ascent::Catalog::read(&packets::read(program)?).map_err(error)?;
        let limits = limits.map(|p| p.0).unwrap_or_default();
        py.detach(|| {
            self.0
                .open_catalog(catalog.program, BTreeMap::new(), catalog.queries, limits)
        })
        .map(Evidence::owned)
        .map_err(error)
    }
    fn close(&self) {
        self.0.shutdown();
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

#[pyclass(name = "EvidenceSession", frozen)]
pub(super) struct Evidence {
    owner: Arc<Mutex<SourceSession>>,
    declarations: Vec<gerbil_ascent::Relation>,
    queries: Vec<String>,
}
impl Evidence {
    fn closed(&self, py: Python<'_>) -> PyResult<bool> {
        py.detach(|| {
            self.owner
                .lock()
                .map(|o| o.source_program().is_err())
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))
        })
    }
    pub(super) fn owned(session: SourceSession) -> Self {
        Self {
            declarations: session.descriptors().to_vec(),
            queries: session.queries().to_vec(),
            owner: Arc::new(Mutex::new(session)),
        }
    }
}
#[pymethods]
impl Evidence {
    #[getter(closed)]
    fn is_closed(&self, py: Python<'_>) -> PyResult<bool> {
        self.closed(py)
    }
    #[getter]
    fn projection(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let result = py.detach(|| {
            self.owner
                .lock()
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))?
                .source_program()
                .and_then(|program| gerbil_ascent::Catalog::encode(&program, &self.queries))
                .map_err(error)
        });
        let packet = match result {
            Ok(program) => {
                gerbil_ascent::Data::object([("status", "supported".into()), ("program", program)])
            }
            Err(e) => gerbil_ascent::Data::object([
                ("status", "unsupported".into()),
                ("reason", e.to_string().into()),
            ]),
        };
        packets::write(py, &packet)
    }
    #[getter]
    fn fact_limits<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let limits = py.detach(|| {
            self.owner
                .lock()
                .map(|o| o.fact_limits())
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))
        })?;
        let out = PyDict::new(py);
        for (name, value) in [
            ("input", limits.input),
            ("derived", limits.derived),
            ("output", limits.output),
        ] {
            if let Some(value) = value {
                out.set_item(name, value)?;
            } else {
                out.set_item(name, "unlimited")?;
            }
        }
        Ok(out)
    }
    #[getter]
    fn queries(&self) -> Vec<String> {
        self.queries.clone()
    }
    #[getter]
    fn descriptors<'py>(&self, py: Python<'py>) -> PyResult<Vec<Bound<'py, PyDict>>> {
        self.declarations
            .iter()
            .map(|r| {
                let row = PyDict::new(py);
                row.set_item("name", &r.name)?;
                row.set_item("source", r.source)?;
                row.set_item("arity", r.columns.len())?;
                row.set_item(
                    "columns",
                    r.columns.iter().map(|_| "value").collect::<Vec<_>>(),
                )?;
                Ok(row)
            })
            .collect()
    }
    fn replace(&self, py: Python<'_>, sources: &Bound<'_, PyDict>) -> PyResult<()> {
        let declarations: BTreeMap<_, _> = self
            .declarations
            .iter()
            .map(|r| (r.name.clone(), r.clone()))
            .collect();
        let mut updates = BTreeMap::new();
        for (name, rows) in sources.iter() {
            let name = name.extract::<String>()?;
            let declaration = declarations
                .get(&name)
                .ok_or_else(|| PyValueError::new_err("unknown source relation"))?;
            let values = rows
                .try_iter()?
                .map(|row| transport_row(py, &self.owner, &row?, &declaration.columns))
                .collect::<PyResult<Vec<_>>>()?;
            updates.insert(name, values);
        }
        py.detach(|| {
            self.owner
                .lock()
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))?
                .replace(
                    updates,
                    &SourceSession::default_limits(),
                    &Cancellation::default(),
                )
                .map(|_| ())
                .map_err(error)
        })
    }
    #[pyo3(signature=(timeout_nanoseconds=1_000_000_000,*,queries=None))]
    fn run<'py>(
        &self,
        py: Python<'py>,
        timeout_nanoseconds: u64,
        queries: Option<Vec<String>>,
    ) -> PyResult<Bound<'py, PyDict>> {
        if self.closed(py)? {
            return Err(PyValueError::new_err("session closed"));
        }
        let queries = queries.unwrap_or_else(|| self.queries.clone());
        let mut limits = SourceSession::default_limits();
        limits.timeout = Duration::from_nanos(timeout_nanoseconds);
        let observation = py.detach(|| {
            let mut owner = self
                .owner
                .lock()
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))?;
            Ok::<_, PyErr>(owner.run(Some(&queries), &limits, &Cancellation::default()))
        })?;
        let observation = match observation {
            Ok(value) => value,
            Err(gerbil_ascent::Error::Timeout) => {
                let receipt = PyDict::new(py);
                receipt.set_item("complete", false)?;
                receipt.set_item("nativeResultReused", false)?;
                receipt.set_item("relations", PyDict::new(py))?;
                receipt.set_item("evaluationPath", "deadline")?;
                return Ok(receipt);
            }
            Err(failure) => return Err(error(failure)),
        };
        let result = PyDict::new(py);
        let relations = PyDict::new(py);
        let mut structured = false;
        for (name, rows) in observation.relations {
            structured |= rows
                .iter()
                .flat_map(|row| row.iter())
                .any(|v| matches!(v, Value::Object(_)) && v.as_binary64().is_none());
            let rows = rows
                .iter()
                .map(|r| {
                    r.iter()
                        .map(|v| match v {
                            Value::Object(_) if v.as_binary64().is_some() => project(py, v),
                            Value::Object(_) => Py::new(py, Object(v.clone())).map(Py::into_any),
                            _ => project(py, v),
                        })
                        .collect::<PyResult<Vec<_>>>()
                })
                .collect::<PyResult<Vec<_>>>()?;
            relations.set_item(name, rows)?;
        }
        result.set_item("relations", relations)?;
        result.set_item(
            "scalarProjection",
            if structured { "partial" } else { "supported" },
        )?;
        result.set_item("complete", observation.complete)?;
        result.set_item("sourceGeneration", observation.source_generation)?;
        result.set_item("resultHandle", observation.result_handle)?;
        result.set_item("runIndex", observation.run_index)?;
        result.set_item("nativeResultReused", observation.reused)?;
        result.set_item("activeRuleCount", observation.active_rule_count)?;
        result.set_item("reusedRelations", observation.reused_relations)?;
        result.set_item(
            "evaluationPath",
            if observation.evaluated {
                "recomputed"
            } else {
                "retained"
            },
        )?;
        Ok(result)
    }
    fn result(&self, py: Python<'_>, receipt: &Bound<'_, PyDict>) -> PyResult<ResultOwner> {
        let handle = receipt
            .get_item("resultHandle")?
            .ok_or_else(|| PyValueError::new_err("result handle required"))?
            .extract::<u64>()?;
        py.detach(|| {
            self.owner
                .lock()
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))?
                .result(handle)
                .map(|result| ResultOwner(result, self.owner.clone(), handle))
                .map_err(error)
        })
    }
    fn explanation(
        &self,
        py: Python<'_>,
        receipt: &Bound<'_, PyDict>,
        relation: &str,
    ) -> PyResult<Explanation> {
        let handle = receipt
            .get_item("resultHandle")?
            .ok_or_else(|| PyValueError::new_err("result handle required"))?
            .extract::<u64>()?;
        explanation(py, &self.owner, handle, relation)
    }
    fn close(&self, py: Python<'_>) -> PyResult<()> {
        py.detach(|| {
            self.owner
                .lock()
                .map_err(|_| PyValueError::new_err("owner lock poisoned"))?
                .close();
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

fn transport_row(
    py: Python<'_>,
    owner: &Arc<Mutex<SourceSession>>,
    row: &Bound<'_, PyAny>,
    columns: &[Type],
) -> PyResult<Row> {
    let cells = row.try_iter()?.collect::<PyResult<Vec<_>>>()?;
    if cells.len() != columns.len() {
        return Err(PyValueError::new_err("source tuple arity"));
    }
    cells
        .iter()
        .zip(columns)
        .map(|(value, ty)| {
            validate_reference(py, owner, value)?;
            cell(value, *ty)
        })
        .collect::<PyResult<Vec<_>>>()
        .map(Row::from)
}

fn validate_reference(
    py: Python<'_>,
    owner: &Arc<Mutex<SourceSession>>,
    value: &Bound<'_, PyAny>,
) -> PyResult<()> {
    let Ok(reference) = value.extract::<PyRef<'_, Reference>>() else {
        return Ok(());
    };
    let reference = reference.0.clone();
    py.detach(|| {
        owner
            .lock()
            .map_err(|_| PyValueError::new_err("owner lock poisoned"))?
            .validate_value(&reference)
            .map_err(error)
    })
}

#[pyclass(name = "Value", frozen)]
struct Object(Value);
#[pymethods]
impl Object {
    #[getter]
    fn graph(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let Value::Object(value) = &self.0 else {
            return Err(PyValueError::new_err("structured value required"));
        };
        packets::write(py, &value.graph().to_native())
    }
    fn scalar(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        project(py, &self.0)
    }
}
#[pyclass(name = "Result", frozen)]
struct ResultOwner(gerbil_ascent::SourceResult, Arc<Mutex<SourceSession>>, u64);
#[pymethods]
impl ResultOwner {
    fn __enter__(slf: PyRef<'_, Self>) -> PyResult<PyRef<'_, Self>> {
        if slf.closed() { return Err(PyValueError::new_err("native result released")); }
        Ok(slf)
    }
    fn __exit__(&self, _ty: &Bound<'_, PyAny>, _value: &Bound<'_, PyAny>, _traceback: &Bound<'_, PyAny>) {
        self.close();
    }
    fn graph(&self, py: Python<'_>, relation: &str) -> PyResult<Py<PyAny>> {
        let rows = self.0.rows(relation).map_err(error)?;
        let graph = gerbil_ascent::rows_graph(rows).map_err(error)?;
        packets::write(py, &graph.to_native())
    }
    fn rows(&self, py: Python<'_>, relation: &str) -> PyResult<Py<PyAny>> {
        let rows = self.0.rows(relation).map_err(|e| {
            if e == gerbil_ascent::Error::Closed {
                PyValueError::new_err("native result released")
            } else {
                error(e)
            }
        })?;
        if rows
            .iter()
            .flat_map(|row| row.iter())
            .any(|v| matches!(v, Value::Object(_)) && v.as_binary64().is_none())
        {
            let graph = gerbil_ascent::rows_graph(rows).map_err(error)?;
            return packets::write(
                py,
                &gerbil_ascent::Data::object([
                    ("type", "graph".into()),
                    ("value", graph.to_native()),
                ]),
            );
        }
        let rows = rows
            .iter()
            .map(|row| {
                row.iter()
                    .map(|v| project(py, v))
                    .collect::<PyResult<Vec<_>>>()
            })
            .collect::<PyResult<Vec<_>>>()?;
        let result = PyDict::new(py);
        result.set_item("rows", rows)?;
        Ok(result.unbind().into_any())
    }
    #[getter]
    fn closed(&self) -> bool {
        self.0.is_released()
    }
    fn explanation(&self, py: Python<'_>, relation: &str) -> PyResult<Explanation> {
        self.0.rows(relation).map_err(error)?;
        explanation(py, &self.1, self.2, relation)
    }
    fn reference(&self, relation: &str, row: usize, column: usize) -> PyResult<Reference> {
        self.0
            .value(relation, row, column)
            .map(Reference)
            .map_err(error)
    }
    fn close(&self) {
        self.0.close();
    }
}
#[pyclass(name = "ResultValue", frozen)]
struct Reference(gerbil_ascent::RowValue);
#[pymethods]
impl Reference {
    fn scalar(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        project(py, &self.0.value().map_err(error)?)
    }
}
#[pyclass(name = "Explanation", frozen)]
struct Explanation(Mutex<gerbil_ascent::Provenance>, gerbil_ascent::Data);
#[pymethods]
impl Explanation {
    #[getter]
    fn current(&self, py: Python<'_>) -> PyResult<bool> {
        py.detach(|| {
            let owner = self
                .0
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
        py.detach(|| {
            self.0
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?
                .graph()
                .map(|g| g.generation)
                .map_err(error)
        })
    }
    #[getter]
    fn graph(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        py.detach(|| {
            self.0
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?
                .graph()
                .map_err(error)
        })?;
        packets::write(py, &self.1)
    }
    fn summary<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let graph = py.detach(|| {
            self.0
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
        py.detach(|| {
            self.0
                .lock()
                .map_err(|_| PyValueError::new_err("explanation lock poisoned"))?
                .close();
            Ok(())
        })
    }
}
fn explanation(
    py: Python<'_>,
    owner: &Arc<Mutex<SourceSession>>,
    handle: u64,
    relation: &str,
) -> PyResult<Explanation> {
    py.detach(|| {
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
        Ok(Explanation(Mutex::new(provenance), metadata))
    })
}

pub(super) fn cell(value: &Bound<'_, PyAny>, ty: Type) -> PyResult<Value> {
    if let Ok(reference) = value.extract::<PyRef<'_, Reference>>() {
        return reference.0.value().map_err(error);
    }
    if let Ok(object) = value.extract::<PyRef<'_, Object>>() {
        return Ok(object.0.clone());
    }
    match (ty, OwnedValue::from_python(value, ValueLimits::default())?) {
        (Type::Integer | Type::Number | Type::Scalar | Type::Any, OwnedValue::Integer(v)) => {
            Ok(Value::Integer(v))
        }
        (Type::Boolean | Type::Scalar | Type::Any, OwnedValue::Boolean(v)) => Ok(Value::Boolean(v)),
        (Type::Symbol | Type::Scalar, OwnedValue::Text(v)) => Ok(Value::Symbol(v.into())),
        (Type::Text | Type::Any, OwnedValue::Text(v)) => Ok(Value::Text(v.into())),
        (Type::Number | Type::Any | Type::Scalar, OwnedValue::Real(v)) => {
            Value::inexact(v).map_err(error)
        }
        _ => Err(PyValueError::new_err(
            "unsupported or mismatched source value; no VM fallback",
        )),
    }
}
fn project(py: Python<'_>, value: &Value) -> PyResult<Py<PyAny>> {
    use gerbil_scheme_python::OwnedValue;
    let value = match value {
        Value::Integer(n) => OwnedValue::Integer(n.clone()),
        Value::Boolean(b) => OwnedValue::Boolean(*b),
        Value::Symbol(s) | Value::Text(s) => OwnedValue::Text(s.to_string()),
        Value::Object(_) if value.as_binary64().is_some() => {
            OwnedValue::Real(value.as_binary64().unwrap())
        }
        Value::Object(_) => {
            return Err(PyValueError::new_err(
                "object projection unavailable; Rust result remains retained",
            ));
        }
    };
    value.to_python(py)
}
#[pymodule]
fn _core(module: &Bound<'_, PyModule>) -> PyResult<()> {
    crate::core_abi::install(module)?;
    super::build_inventory::install(module)?;
    exports::install(module)?;
    module.add_class::<Owner>()?;
    module.add("EngineError", module.py().get_type::<EngineError>())?;
    module.add_class::<crate::rust_components::Policy>()?;
    module.add_class::<crate::rust_components::Components>()?;
    module.add_class::<crate::rust_components::Declaration>()?;
    module.add_class::<crate::rust_graph::Graph>()?;
    module.add_class::<Evidence>()?;
    module.add_class::<ResultOwner>()?;
    module.add_class::<Reference>()?;
    module.add_class::<Object>()?;
    module.add_class::<Explanation>()?;
    module.add("EXECUTION_BACKEND", "rust")?;
    let evidence = PyModule::new(module.py(), "ascent.evidence")?;
    evidence.add_function(wrap_pyfunction!(derivations::identity, &evidence)?)?;
    evidence.add_class::<computational::ComputationalEvidence>()?;
    exports::evidence(&evidence)?;
    module
        .py()
        .import("sys")?
        .getattr("modules")?
        .set_item("ascent.evidence", &evidence)?;
    Ok(())
}
