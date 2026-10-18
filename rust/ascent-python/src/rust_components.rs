//! Structured component declarations enter Rust scopes, never a Python linker.
use crate::rust_api::{Evidence, Owner, error, packets};
use gerbil_ascent::{Component, Data, Dependency, EvidenceProgram, FactLimits};
use gerbil_scheme_python::ValueLimits;
use pyo3::{
    Bound, PyAny, PyRef, PyResult, Python,
    exceptions::PyValueError,
    pyclass, pymethods,
    types::{PyDict, PyTuple, PyTupleMethods},
};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

fn components(
    manifest: &Data,
    sources: &Data,
    entry: &str,
) -> gerbil_ascent::Result<Vec<Component>> {
    if manifest.field("schema")?.text()? != "ascent.evidence-components.v1" {
        return Err(gerbil_ascent::Error::InvalidProgram(
            "component manifest schema".into(),
        ));
    }
    let components = manifest
        .field("components")?
        .list()?
        .iter()
        .map(|item| {
            let file = item.field("source")?.text()?;
            Ok(Component {
                id: item.field("id")?.text()?.to_owned(),
                source: sources
                    .get(file)
                    .map(Data::text)
                    .transpose()?
                    .unwrap_or_default()
                    .to_owned(),
                exports: item.get("exports").map(names).transpose()?,
                dependencies: item
                    .field("dependencies")?
                    .list()?
                    .iter()
                    .map(|dependency| {
                        Ok(Dependency {
                            component: dependency.field("component")?.text()?.to_owned(),
                            bindings: names(dependency.field("bindings")?)?,
                        })
                    })
                    .collect::<gerbil_ascent::Result<_>>()?,
            })
        })
        .collect::<gerbil_ascent::Result<Vec<_>>>()?;
    let selected = EvidenceProgram::component_dependencies(&components, entry)?;
    for item in manifest.field("components")?.list()? {
        let id = item.field("id")?.text()?;
        if selected.iter().any(|selected| selected == id) {
            sources.field(item.field("source")?.text()?)?.text()?;
        }
    }
    Ok(components)
}
fn names(value: &Data) -> gerbil_ascent::Result<Vec<String>> {
    value
        .list()?
        .iter()
        .map(|name| name.text().map(str::to_owned))
        .collect()
}
#[pyclass(name = "Module", frozen)]
pub(super) struct Components {
    engine: gerbil_ascent::Engine,
    entries: Vec<Component>,
    entry: String,
    loaded: Vec<String>,
    closed: Arc<AtomicBool>,
}
impl Components {
    pub(super) fn new(
        engine: &Owner,
        manifest: &Bound<'_, PyAny>,
        sources: &Bound<'_, PyAny>,
        entry: &str,
        trusted: bool,
    ) -> PyResult<Self> {
        if !trusted {
            return Err(PyValueError::new_err(
                "explicit trusted DSL admission required",
            ));
        }
        engine.0.admit_source().map_err(error)?;
        let components = components(&packets::read(manifest)?, &packets::read(sources)?, entry)
            .map_err(error)?;
        let loaded = manifest
            .py()
            .detach(|| EvidenceProgram::component_ids(&components, entry))
            .map_err(error)?;
        if engine.0.is_closed() {
            return Err(PyValueError::new_err("engine owner closed"));
        }
        Ok(Self {
            engine: engine.0.clone(),
            entries: components,
            entry: entry.into(),
            loaded,
            closed: Arc::new(AtomicBool::new(false)),
        })
    }
}
#[pymethods]
impl Components {
    #[getter]
    fn components(&self) -> PyResult<Vec<String>> {
        if self.closed() {
            return Err(PyValueError::new_err("component owner closed"));
        }
        Ok(self.loaded.clone())
    }
    #[getter]
    fn closed(&self) -> bool {
        self.closed.load(Ordering::Acquire) || self.engine.is_closed()
    }
    fn close(&self) {
        self.closed.store(true, Ordering::Release);
    }
    #[pyo3(signature=(constructor,*arguments,component=None))]
    fn call(
        &self,
        py: Python<'_>,
        constructor: &str,
        arguments: &Bound<'_, PyTuple>,
        component: Option<&str>,
    ) -> PyResult<Declaration> {
        if self.closed() {
            return Err(PyValueError::new_err("component owner closed"));
        }
        if !arguments.is_empty() {
            return Err(PyValueError::new_err(
                "parameterized declarative constructors are not yet supported",
            ));
        }
        let selected = component.unwrap_or(&self.entry);
        let target = self
            .entries
            .iter()
            .find(|entry| entry.id == selected)
            .filter(|_| self.loaded.iter().any(|id| id == selected))
            .ok_or_else(|| {
                error(gerbil_ascent::Error::InvalidProgram(
                    "unselected Evidence component".into(),
                ))
            })?;
        if target
            .exports
            .as_ref()
            .is_some_and(|names| !names.iter().any(|name| name == constructor))
        {
            return Err(error(gerbil_ascent::Error::InvalidProgram(
                "hidden Evidence constructor".into(),
            )));
        }
        let entry = py
            .detach(|| EvidenceProgram::read_components(&self.entries, selected, Some(constructor)))
            .map_err(error)?;
        Ok(Declaration {
            engine: self.engine.clone(),
            entry,
            scope: self.closed.clone(),
            closed: AtomicBool::new(false),
        })
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
#[pyclass(name = "Declaration", frozen)]
pub(super) struct Declaration {
    engine: gerbil_ascent::Engine,
    entry: EvidenceProgram,
    scope: Arc<AtomicBool>,
    closed: AtomicBool,
}
#[pymethods]
impl Declaration {
    #[getter]
    fn closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
            || self.scope.load(Ordering::Acquire)
            || self.engine.is_closed()
    }
    fn close(&self) {
        self.closed.store(true, Ordering::Release);
    }
    #[pyo3(signature=(*,limits=None))]
    fn open_session(
        &self,
        py: Python<'_>,
        limits: Option<PyRef<'_, Policy>>,
    ) -> PyResult<Evidence> {
        if self.closed() {
            return Err(PyValueError::new_err("declaration owner closed"));
        }
        let limits = limits.map(|p| p.0).unwrap_or_default();
        py.detach(|| {
            self.engine
                .open_evidence_program(self.entry.clone(), limits)
        })
        .map(Evidence::owned)
        .map_err(error)
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
#[pyclass(name = "FactLimits", frozen)]
#[derive(Clone, Copy)]
pub(super) struct Policy(pub(super) FactLimits);
#[pymethods]
impl Policy {
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
    #[new]
    #[pyo3(signature=(input=None,derived=None,output=None))]
    fn new(
        input: Option<&Bound<'_, PyAny>>,
        derived: Option<&Bound<'_, PyAny>>,
        output: Option<&Bound<'_, PyAny>>,
    ) -> PyResult<Self> {
        Ok(Self(FactLimits {
            input: ceiling(input)?,
            derived: ceiling(derived)?,
            output: ceiling(output)?,
        }))
    }
    fn wire<'py>(&self, py: Python<'py>) -> PyResult<Bound<'py, PyDict>> {
        use pyo3::types::PyDictMethods;
        let out = PyDict::new(py);
        for (name, value) in [
            ("input", self.0.input),
            ("derived", self.0.derived),
            ("output", self.0.output),
        ] {
            if let Some(value) = value {
                out.set_item(name, value)?;
            }
        }
        Ok(out)
    }
}
pub(super) fn ceiling(value: Option<&Bound<'_, PyAny>>) -> PyResult<Option<usize>> {
    value
        .map(|v| {
            gerbil_scheme_python::OwnedValue::from_python(v, ValueLimits::default())?
                .positive_usize()
        })
        .transpose()
}
