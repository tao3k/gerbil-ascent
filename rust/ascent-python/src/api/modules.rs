//! Rust-owned module and callable-value lifetimes exposed through `PyO3`.
use super::{
    components, module_values, sources::FactLimits, types::OwnedValue, types::source_error,
};
use ascent_scheme as engine;
use pyo3::{
    Bound, PyAny, PyRef, PyResult, Python,
    exceptions::PyValueError,
    pyclass, pymethods,
    types::{PyDict, PyDictMethods, PyTuple},
};
#[pyclass(name = "Module", frozen)]
pub(super) struct Module(pub(super) engine::Module);
impl Module {
    fn check(&self) -> PyResult<()> {
        if self.0.is_closed() {
            Err(PyValueError::new_err("module owner closed"))
        } else {
            Ok(())
        }
    }
}
#[pymethods]
impl Module {
    #[pyo3(signature=(export,*arguments,component=None,limits=None))]
    fn rules(
        &self,
        py: Python<'_>,
        export: &str,
        arguments: &Bound<'_, PyTuple>,
        component: Option<&str>,
        limits: Option<PyRef<'_, FactLimits>>,
    ) -> PyResult<super::program::RuleSession> {
        let policy = limits.map(|v| v.0).unwrap_or_default();
        let args = module_values::arguments(arguments)?;
        py.detach(|| {
            self.0
                .call(export, &args, component)
                .and_then(|value| value.open_session(policy))
        })
        .map(super::program::RuleSession)
        .map_err(source_error)
    }
    #[pyo3(signature=(export,*arguments,module=None,component=None))]
    fn call(
        &self,
        py: Python<'_>,
        export: &str,
        arguments: &Bound<'_, PyTuple>,
        module: Option<&str>,
        component: Option<&str>,
    ) -> PyResult<OwnedValue> {
        self.check()?;
        let args = module_values::arguments(arguments)?;
        py.detach(|| match module {
            Some(module) => self.0.call_module(module, export, &args),
            None => self.0.call(export, &args, component),
        })
        .map(OwnedValue)
        .map_err(source_error)
    }
    #[getter]
    fn components<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyTuple>> {
        PyTuple::new(py, self.0.components().map_err(source_error)?)
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
#[pymethods]
impl OwnedValue {
    #[pyo3(signature=(*,limits=None))]
    fn open_session(
        &self,
        py: Python<'_>,
        limits: Option<PyRef<'_, super::sources::FactLimits>>,
    ) -> PyResult<super::program::RuleSession> {
        let limits = limits.map(|v| v.0).unwrap_or_default();
        py.detach(|| self.0.open_session(limits))
            .map(super::program::RuleSession)
            .map_err(source_error)
    }

    #[pyo3(signature=(*,limits=None))]
    fn project_session(
        &self,
        py: Python<'_>,
        limits: Option<PyRef<'_, super::sources::FactLimits>>,
    ) -> PyResult<super::sources::SourceSession> {
        let policy = limits.map(|p| p.0).unwrap_or_default();
        py.detach(|| self.0.project_session(policy))
            .map(super::sources::SourceSession::owned)
            .map_err(source_error)
    }
    #[getter]
    fn graph<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let graph = py
            .detach(|| self.0.graph())
            .map_err(|e| PyValueError::new_err(e.to_string()))?;
        super::packets::write(py, &graph)?
            .bind(py)
            .cast::<PyDict>()
            .cloned()
            .map_err(Into::into)
    }
    #[getter]
    fn receipt<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        let out = PyDict::new(py);
        out.set_item("valueHandle", self.0.handle())?;
        out.set_item("valueCount", self.0.value_count().map_err(source_error)?)?;
        out.set_item("value", self.graph(py)?)?;
        Ok(out)
    }
    #[pyo3(signature=(node=None))]
    fn reference<'py>(&self, py: Python<'py>, node: Option<usize>) -> PyResult<Bound<'py, PyDict>> {
        self.0
            .value_count()
            .map_err(|e| PyValueError::new_err(e.to_string()))?;
        let reference = if node.is_none() {
            self.0.reference(None)
        } else {
            py.detach(|| self.0.reference(node))
        };
        module_values::reference(py, reference)
    }
    #[pyo3(signature=(*arguments))]
    fn apply(&self, py: Python<'_>, arguments: &Bound<'_, PyTuple>) -> PyResult<Self> {
        self.0
            .value_count()
            .map_err(|e| PyValueError::new_err(e.to_string()))?;
        let args = module_values::arguments(arguments)?;
        py.detach(|| self.0.apply(&args))
            .map(Self)
            .map_err(source_error)
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
pub(super) fn load(
    engine: &engine::Engine,
    py: Python<'_>,
    source: &str,
    trusted: bool,
) -> PyResult<Module> {
    if !trusted {
        return Err(PyValueError::new_err(
            "trusted host Scheme execution must be explicitly authorized",
        ));
    }
    py.detach(|| engine.load_definitions(source))
        .map(Module)
        .map_err(source_error)
}
pub(super) fn load_components(
    engine: &engine::Engine,
    py: Python<'_>,
    manifest: &Bound<'_, PyAny>,
    sources: &Bound<'_, PyAny>,
    entry: &str,
    trusted: bool,
) -> PyResult<Module> {
    if !trusted {
        return Err(PyValueError::new_err(
            "trusted host Scheme execution must be explicitly authorized",
        ));
    }
    let definitions = components::read(manifest, sources)?;
    py.detach(|| engine.load_components(&definitions, entry))
        .map(Module)
        .map_err(source_error)
}
