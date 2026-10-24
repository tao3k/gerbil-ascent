use super::{
    catalog,
    declarations::{Atom, Program, Term},
    driver, modules, sources,
    types::{Cancellation, Symbol, error, value},
};

use gerbil_ascent as engine;
use pyo3::{
    Bound, IntoPyObjectExt, Py, PyAny, PyRef, PyResult, Python,
    exceptions::{PyKeyError, PyRuntimeError, PyValueError},
    pyclass, pymethods, pymodule,
    types::{PyAnyMethods, PyModule, PyModuleMethods, PyTuple},
};
use std::{
    sync::{Arc, Mutex},
    time::Duration,
};

/// Caller-owned resident VMs; capacities are independent from Rayon threads.
#[pyclass(name = "ProcessPool", frozen)]
pub(super) struct ProcessPool(ascent_scheme::ProcessPool);
#[pymethods]
impl ProcessPool {
    #[new]
    #[pyo3(signature=(owners=12))]
    fn new(py: Python<'_>, owners: usize) -> PyResult<Self> {
        py.detach(|| ascent_scheme::ProcessPool::new(owners))
            .map(Self)
            .map_err(super::types::source_error)
    }
    #[pyo3(signature=(index, workers=1, *, max_source_scopes=None, max_input_bytes=None, backend=None, work_distribution="adaptive"))]
    fn engine(
        &self,
        index: usize,
        workers: usize,
        max_source_scopes: Option<&Bound<'_, PyAny>>,
        max_input_bytes: Option<&Bound<'_, PyAny>>,
        backend: Option<&str>,
        work_distribution: &str,
    ) -> PyResult<Engine> {
        let owner = self.0.owner(index).map_err(super::types::source_error)?;
        let engine = Engine::new(
            Some(workers),
            max_source_scopes,
            max_input_bytes,
            backend,
            work_distribution,
        )?;
        Ok(Engine(engine.0.on_process(owner)))
    }
    fn identities(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        identities(py, self.0.receipts())
    }
}
pub(super) fn identities(
    py: Python<'_>,
    owners: Vec<ascent_scheme::ProcessReceipt>,
) -> PyResult<Py<PyAny>> {
    super::packets::write(
        py,
        &gerbil_ascent::Data::List(
            owners
                .into_iter()
                .map(|receipt| {
                    gerbil_ascent::Data::object([
                        ("pid", gerbil_ascent::Data::from(u64::from(receipt.pid))),
                        ("domain", gerbil_ascent::Data::from(receipt.domain)),
                        (
                            "processors",
                            gerbil_ascent::Data::from(u64::from(receipt.processors)),
                        ),
                    ])
                })
                .collect(),
        ),
    )
}
#[pyclass(name = "Engine", frozen)]
pub(super) struct Engine(pub(super) ascent_scheme::Engine);
#[pymethods]
impl Engine {
    #[new]
    #[pyo3(signature = (workers=None, *, max_source_scopes=None, max_input_bytes=None, backend=None, work_distribution="adaptive"))]
    pub(super) fn new(
        workers: Option<usize>,
        max_source_scopes: Option<&Bound<'_, PyAny>>,
        max_input_bytes: Option<&Bound<'_, PyAny>>,
        backend: Option<&str>,
        work_distribution: &str,
    ) -> PyResult<Self> {
        let backend = backend
            .map(|v| match v {
                "scheme" => Ok(ascent_scheme::Backend::Scheme),
                "rayon" => Ok(ascent_scheme::Backend::Rayon),
                _ => Err(PyValueError::new_err("backend must be scheme or rayon")),
            })
            .transpose()?;
        let ceiling = super::types::ceiling(max_source_scopes)?;
        let bytes = super::types::ceiling(max_input_bytes)?;
        let distribution = match work_distribution {
            "adaptive" => engine::WorkDistribution::Adaptive,
            "across-requests" => engine::WorkDistribution::AcrossRequests,
            "within-request" => engine::WorkDistribution::WithinRequest,
            _ => return Err(PyValueError::new_err("unknown work distribution")),
        };
        ascent_scheme::Engine::new(workers.unwrap_or(1))
            .map(|engine| engine.with_work_distribution(distribution))
            .map(|engine| backend.map_or(engine.clone(), |backend| engine.with_backend(backend)))
            .and_then(|engine| engine.with_source_scope_limit(ceiling))
            .and_then(|engine| engine.with_input_limit(bytes))
            .map(Self)
            .map_err(error)
    }
    #[getter]
    fn work_distribution(&self) -> &'static str {
        match self.0.work_distribution() {
            gerbil_ascent::WorkDistribution::Adaptive => "adaptive",
            gerbil_ascent::WorkDistribution::AcrossRequests => "across-requests",
            gerbil_ascent::WorkDistribution::WithinRequest => "within-request",
        }
    }
    #[getter]
    fn max_source_scopes(&self) -> Option<usize> {
        self.0.max_source_scopes()
    }
    #[getter]
    fn max_input_bytes(&self) -> Option<usize> {
        self.0.max_input_bytes()
    }
    fn process_identity(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let receipt = py
            .detach(|| self.0.process_receipt())
            .map_err(super::types::source_error)?;
        super::packets::write(
            py,
            &gerbil_ascent::Data::object([
                ("pid", gerbil_ascent::Data::from(u64::from(receipt.pid))),
                ("domain", gerbil_ascent::Data::from(receipt.domain)),
                (
                    "processors",
                    gerbil_ascent::Data::from(u64::from(receipt.processors)),
                ),
            ]),
        )
    }
    fn describe(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let result = py
            .detach(|| self.0.describe())
            .map_err(super::types::source_error)?;
        super::packets::write(py, &result)
    }
    #[pyo3(signature=(program,*,limits=None))]
    fn open(
        &self,
        py: Python<'_>,
        program: &Bound<'_, PyAny>,
        limits: Option<PyRef<'_, sources::FactLimits>>,
    ) -> PyResult<Py<PyAny>> {
        let policy = limits.map(|p| p.0).unwrap_or_default();
        if let Ok(program) = program.extract::<PyRef<'_, Program>>() {
            let mut owned = program.0.clone();
            drop(program);
            owned.fact_limits = owned.fact_limits.tighten(policy).map_err(error)?;
            let session = py.detach(|| self.0.open(owned)).map_err(error)?;
            return Py::new(py, Session(Mutex::new(session))).map(Py::into_any);
        }
        let catalog = catalog::read(program)?;
        let session = py
            .detach(|| {
                self.0
                    .open_catalog(catalog.program, catalog.sources, catalog.queries, policy)
            })
            .map_err(super::types::source_error)?;
        Py::new(py, sources::SourceSession::owned(session)).map(Py::into_any)
    }
    #[pyo3(signature=(*texts))]
    fn read_rules<'py>(
        &self,
        py: Python<'py>,
        texts: &Bound<'_, PyTuple>,
    ) -> PyResult<Bound<'py, pyo3::types::PyDict>> {
        if self.0.is_closed() {
            return Err(super::types::source_error(engine::Error::Closed));
        }
        let texts = sources::texts(texts)?;
        let program = py
            .detach(|| self.0.read_rules(&texts))
            .map_err(super::types::source_error)?;
        super::packets::write(py, &program)?
            .bind(py)
            .cast::<pyo3::types::PyDict>()
            .cloned()
            .map_err(Into::into)
    }
    #[pyo3(signature=(*texts, limits=None))]
    fn open_sources(
        &self,
        py: Python<'_>,
        texts: &Bound<'_, PyTuple>,
        limits: Option<PyRef<'_, sources::FactLimits>>,
    ) -> PyResult<Py<PyAny>> {
        let texts = sources::texts(texts)?;
        let policy = limits.map(|p| p.0).unwrap_or_default();
        let loaded = py
            .detach(|| self.0.load_sources(&texts, policy, false))
            .map_err(super::types::source_error)?;
        match loaded {
            ascent_scheme::Source::Rayon(session) => {
                Py::new(py, sources::SourceSession::owned(*session)).map(Py::into_any)
            }
            ascent_scheme::Source::Scheme(session) => {
                Py::new(py, super::program::RuleSession(session)).map(Py::into_any)
            }
        }
    }
    #[pyo3(signature=(*texts, limits=None))]
    fn open_declaration_sources(
        &self,
        py: Python<'_>,
        texts: &Bound<'_, PyTuple>,
        limits: Option<PyRef<'_, sources::FactLimits>>,
    ) -> PyResult<Py<PyAny>> {
        let texts = sources::texts(texts)?;
        let policy = limits.map(|p| p.0).unwrap_or_default();
        let loaded = py
            .detach(|| self.0.load_sources(&texts, policy, true))
            .map_err(super::types::source_error)?;
        match loaded {
            ascent_scheme::Source::Rayon(session) => {
                Py::new(py, sources::SourceSession::owned(*session)).map(Py::into_any)
            }
            ascent_scheme::Source::Scheme(session) => {
                Py::new(py, super::program::RuleSession(session)).map(Py::into_any)
            }
        }
    }
    #[pyo3(signature=(module,constructor,*arguments))]
    fn open_module(
        &self,
        py: Python<'_>,
        module: &str,
        constructor: &str,
        arguments: &Bound<'_, PyTuple>,
    ) -> PyResult<super::program::RuleSession> {
        let args = super::module_values::arguments(arguments)?;
        py.detach(|| {
            let module = self.0.module(module)?;
            let result = module
                .call(constructor, &args, None)
                .and_then(|value| value.open_session(engine::FactLimits::default()));
            module.close();
            result
        })
        .map(super::program::RuleSession)
        .map_err(super::types::source_error)
    }
    #[pyo3(signature=(manifest,sources,entry,constructor,*arguments,trusted=false))]
    fn rule_components(
        &self,
        manifest: &Bound<'_, PyAny>,
        sources: &Bound<'_, PyAny>,
        entry: &str,
        constructor: &str,
        arguments: &Bound<'_, PyTuple>,
        trusted: bool,
    ) -> PyResult<super::program::RuleSession> {
        let py = arguments.py();
        if !trusted {
            return Err(PyValueError::new_err(
                "trusted component execution must be explicitly authorized",
            ));
        }
        let components = super::components::read(manifest, sources)?;
        let args = super::module_values::arguments(arguments)?;
        py.detach(|| {
            let module = self.0.load_components(&components, entry)?;
            let result = module
                .call(constructor, &args, None)
                .and_then(|value| value.open_session(engine::FactLimits::default()));
            module.close();
            result
        })
        .map(super::program::RuleSession)
        .map_err(super::types::source_error)
    }
    fn module(&self, py: Python<'_>, name: &str) -> PyResult<modules::Module> {
        py.detach(|| self.0.module(name))
            .map(modules::Module)
            .map_err(super::types::source_error)
    }
    #[pyo3(signature=(name,source,*,trusted=false))]
    fn register_module(&self, name: &str, source: &str, trusted: bool) -> PyResult<()> {
        if !trusted {
            return Err(PyValueError::new_err(
                "trusted module source must be explicitly authorized",
            ));
        }
        self.0
            .register_module(name, source)
            .map_err(super::types::source_error)
    }
    #[pyo3(signature=(source,*,trusted=false))]
    fn dsl(&self, py: Python<'_>, source: &str, trusted: bool) -> PyResult<modules::Module> {
        modules::load(&self.0, py, source, trusted)
    }
    #[pyo3(signature=(manifest,sources,entry,*,trusted=false))]
    fn components(
        &self,
        py: Python<'_>,
        manifest: &Bound<'_, PyAny>,
        sources: &Bound<'_, PyAny>,
        entry: &str,
        trusted: bool,
    ) -> PyResult<modules::Module> {
        modules::load_components(&self.0, py, manifest, sources, entry, trusted)
    }
    #[pyo3(signature=(source,constructor,*arguments,trusted=false,limits=None))]
    fn rules(
        &self,
        py: Python<'_>,
        source: &str,
        constructor: &str,
        arguments: &Bound<'_, PyTuple>,
        trusted: bool,
        limits: Option<PyRef<'_, sources::FactLimits>>,
    ) -> PyResult<super::program::RuleSession> {
        if !trusted {
            return Err(PyValueError::new_err(
                "trusted host Scheme execution must be explicitly authorized",
            ));
        }
        let policy = limits.map(|v| v.0).unwrap_or_default();
        let args = super::module_values::arguments(arguments)?;
        py.detach(|| {
            let module = self.0.load_definitions(source)?;
            let result = module
                .call(constructor, &args, None)
                .and_then(|value| value.open_session(policy));
            module.close();
            result
        })
        .map(super::program::RuleSession)
        .map_err(super::types::source_error)
    }
    #[getter]
    fn closed(&self) -> bool {
        self.0.is_closed()
    }
    fn shutdown(&self, py: Python<'_>) {
        py.detach(|| self.0.shutdown());
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
        self.shutdown(py);
    }
    #[getter]
    fn workers(&self) -> usize {
        self.0.threads()
    }
}
#[pyclass(name = "Session", frozen)]
struct Session(Mutex<engine::Session>);
#[pymethods]
impl Session {
    fn replace(&self, py: Python<'_>, relation: &str, rows: Vec<Vec<Py<PyAny>>>) -> PyResult<()> {
        let rows: Vec<engine::Row> = rows
            .into_iter()
            .map(|row| {
                row.into_iter()
                    .map(|v| value(v.bind(py)))
                    .collect::<PyResult<Vec<_>>>()
                    .map(Into::into)
            })
            .collect::<PyResult<_>>()?;
        py.detach(|| {
            self.0
                .lock()
                .map_err(|_| PyRuntimeError::new_err("session lock poisoned"))?
                .replace(relation, rows)
                .map_err(error)
        })
    }
    #[pyo3(signature = (timeout_seconds=30.0, max_facts=1_000_000, max_states=10_000_000, cancellation=None))]
    fn run(
        &self,
        py: Python<'_>,
        timeout_seconds: f64,
        max_facts: usize,
        max_states: usize,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<Snapshot> {
        let timeout = Duration::try_from_secs_f64(timeout_seconds)
            .map_err(|_| PyValueError::new_err("invalid timeout"))?;
        let cancellation = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        let mut limits = engine::Limits {
            timeout,
            max_facts,
            max_states,
        };
        let deadline = super::types::admission_deadline(timeout).map_err(error)?;
        py.detach(|| {
            let mut session =
                super::types::lock_before(&self.0, deadline, &cancellation).map_err(error)?;
            limits.timeout = super::types::remaining(deadline).map_err(error)?;
            session
                .run(&limits, &cancellation)
                .map(Snapshot)
                .map_err(error)
        })
    }
    fn last_completed(&self, py: Python<'_>) -> PyResult<Option<Snapshot>> {
        py.detach(|| {
            Ok(self
                .0
                .lock()
                .map_err(|_| PyRuntimeError::new_err("session lock poisoned"))?
                .last_completed()
                .map(Snapshot))
        })
    }
}
#[pyclass(name = "Snapshot", frozen)]
struct Snapshot(Arc<engine::Snapshot>);
#[pymethods]
impl Snapshot {
    #[getter]
    fn generation(&self) -> u64 {
        self.0.generation
    }
    fn rows(&self, py: Python<'_>, relation: &str) -> PyResult<Vec<Vec<Py<PyAny>>>> {
        self.0
            .relations
            .get(relation)
            .ok_or_else(|| PyKeyError::new_err(relation.to_owned()))?
            .iter()
            .map(|row| {
                row.iter()
                    .map(|value| match value {
                        engine::Value::Object(v) => Ok(super::module_values::graph(py, v.graph())?
                            .unbind()
                            .into_any()),
                        engine::Value::Integer(v) => v.into_py_any(py),
                        engine::Value::Boolean(v) => v.into_py_any(py),
                        engine::Value::Text(v) => v.as_ref().into_py_any(py),
                        engine::Value::Symbol(v) => Py::new(
                            py,
                            Symbol {
                                name: v.to_string(),
                            },
                        )
                        .map(Py::into_any),
                    })
                    .collect()
            })
            .collect()
    }
}
#[pyo3::pyfunction]
fn _scheme_process_worker(path: std::path::PathBuf, domain: u64) -> PyResult<()> {
    ascent_scheme::serve_process_worker(path, domain).map_err(super::types::source_error)
}
#[pymodule(name = "_core")]
fn ascent(module: &Bound<'_, PyModule>) -> PyResult<()> {
    let sys = module.py().import("sys")?;
    let executable: std::path::PathBuf = sys.getattr("executable")?.extract()?;
    let paths: Vec<String> = sys.getattr("path")?.extract()?;
    let mut arguments: Vec<std::ffi::OsString> = vec![
        "-c".into(),
        "import sys; sys.path[:0]=sys.argv[1:-2]; from ascent._core import _scheme_process_worker; _scheme_process_worker(sys.argv[-2], int(sys.argv[-1]))".into(),
    ];
    arguments.extend(paths.into_iter().map(std::ffi::OsString::from));
    ascent_scheme::configure_worker(ascent_scheme::WorkerProgram::new(executable, arguments))
        .map_err(super::types::source_error)?;
    module.add_function(pyo3::wrap_pyfunction!(_scheme_process_worker, module)?)?;
    module.add(
        "EngineError",
        module.py().get_type::<super::types::EngineError>(),
    )?;
    module.add(
        "ResourceLimitError",
        module.py().get_type::<super::types::ResourceLimitError>(),
    )?;
    module.add_class::<sources::FactLimits>()?;
    module.add_class::<sources::SourceSession>()?;
    module.add_class::<sources::ResultOwner>()?;
    module.add_class::<driver::RunLimits>()?;
    module.add_class::<driver::Case>()?;
    module.add_class::<driver::Observation>()?;
    module.add_class::<super::provenance::Provenance>()?;
    module.add_class::<super::provenance::ProvenanceLimits>()?;
    module.add_class::<super::program::RuleSession>()?;
    module.add_class::<super::program::RuleResult>()?;
    module.add_class::<super::program::Explanation>()?;
    module.add_class::<modules::Module>()?;
    module.add_class::<super::types::OwnedValue>()?;
    module.add_class::<super::types::ResultValue>()?;
    module.add_class::<Symbol>()?;
    module.add_class::<Term>()?;
    module.add_class::<Atom>()?;
    module.add_class::<Program>()?;
    module.add_class::<Engine>()?;
    module.add_class::<ProcessPool>()?;
    #[cfg(all(feature = "instances", target_os = "macos"))]
    module.add_class::<super::instances::InstancePool>()?;
    module.add_function(pyo3::wrap_pyfunction!(super::scheme::_scheme_call, module)?)?;
    module.add_class::<Session>()?;
    module.add_class::<Snapshot>()?;
    module.add_class::<Cancellation>()?;
    super::exports::install(module)?;
    Ok(())
}
