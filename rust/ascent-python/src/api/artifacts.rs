//! `PyO3` only marshals paths; Rust owns producer admission and publication.
use gerbil_ascent::artifacts as native;
use pyo3::{
    Bound, Py, PyAny, PyErr, PyResult, Python,
    exceptions::PyValueError,
    pyclass, pyfunction, pymethods,
    types::{PyAnyMethods, PyModule, PyModuleMethods},
    wrap_pyfunction,
};
use std::{path::PathBuf, sync::Mutex};
fn error(error: native::ArtifactError) -> PyErr {
    match error {
        native::ArtifactError::Io(error) => error.into(),
        native::ArtifactError::Invalid(message) => PyValueError::new_err(message),
    }
}
#[pyfunction]
fn runtime_identity(py: Python<'_>) -> PyResult<Py<PyAny>> {
    super::packets::write(py, &ascent_scheme::build_identity())
}
#[pyfunction]
fn sha(py: Python<'_>, path: PathBuf) -> PyResult<String> {
    py.detach(move || native::sha(&path)).map_err(error)
}
#[pyfunction]
#[pyo3(signature=(source,target,*,copy=false))]
fn transfer_resource(
    py: Python<'_>,
    source: PathBuf,
    target: PathBuf,
    copy: bool,
) -> PyResult<String> {
    py.detach(move || {
        if copy {
            if source.file_name() != target.file_name() {
                return Err(native::ArtifactError::Invalid(
                    "compiled generation filename changed".into(),
                ));
            }
            std::fs::copy(&source, &target).map_err(native::ArtifactError::Io)?;
            Ok("copied")
        } else {
            native::transfer_resource(&source, &target)
        }
    })
    .map(str::to_string)
    .map_err(error)
}
#[pyclass(name = "ArtifactPublication", frozen)]
struct Publication(Mutex<Option<native::Publication>>);
#[pymethods]
impl Publication {
    fn publish(&self, py: Python<'_>) -> PyResult<()> {
        let publication = self
            .0
            .lock()
            .map_err(|_| PyValueError::new_err("publication owner poisoned"))?
            .take()
            .ok_or_else(|| PyValueError::new_err("publication already consumed"))?;
        py.detach(move || publication.publish()).map_err(error)
    }
}
#[pyfunction]
#[pyo3(signature=(root,output,build_dir=None))]
fn prepare(
    py: Python<'_>,
    root: PathBuf,
    output: PathBuf,
    build_dir: Option<PathBuf>,
) -> PyResult<Publication> {
    let directory = build_dir.unwrap_or_else(|| root.join(".gerbil"));
    py.detach(move || native::Publication::prepare(&root, &output, &directory))
        .map(|p| Publication(Mutex::new(Some(p))))
        .map_err(error)
}
#[pyfunction]
#[pyo3(signature=(root,output,build_dir=None))]
fn build(
    py: Python<'_>,
    root: PathBuf,
    output: PathBuf,
    build_dir: Option<PathBuf>,
) -> PyResult<()> {
    let directory = build_dir.unwrap_or_else(|| root.join(".gerbil"));
    py.detach(move || native::build(&root, &output, &directory))
        .map_err(error)
}
#[pyclass(name = "ArtifactValidation", frozen)]
#[derive(Default)]
struct Validation(Mutex<native::ArtifactValidation>);
#[pymethods]
impl Validation {
    #[new]
    fn new() -> Self {
        Self::default()
    }
    fn has_receipt(&self, path: &Bound<'_, PyAny>) -> PyResult<bool> {
        let path = path.extract::<PathBuf>()?;
        Ok(self
            .0
            .lock()
            .map_err(|_| PyValueError::new_err("validator poisoned"))?
            .has_receipt(&path))
    }
    fn read(&self, py: Python<'_>, library: PathBuf, receipt_path: PathBuf) -> PyResult<Py<PyAny>> {
        let receipt = py
            .detach(move || {
                self.0
                    .lock()
                    .map_err(|_| native::ArtifactError::Invalid("validator poisoned".into()))?
                    .read(&library, &receipt_path)
            })
            .map_err(error)?;
        super::packets::write(py, &receipt.into_data().map_err(error)?)
    }
}
pub(super) fn install(root: &Bound<'_, PyModule>) -> PyResult<()> {
    let module = PyModule::new(root.py(), "ascent.build")?;
    module.add_function(wrap_pyfunction!(sha, &module)?)?;
    module.add_function(wrap_pyfunction!(runtime_identity, &module)?)?;
    module.add_function(wrap_pyfunction!(transfer_resource, &module)?)?;
    module.add_function(wrap_pyfunction!(prepare, &module)?)?;
    module.add_function(wrap_pyfunction!(build, &module)?)?;
    module.add_class::<Publication>()?;
    let artifact = PyModule::new(root.py(), "ascent.artifact")?;
    artifact.add_class::<Validation>()?;
    let modules = root.py().import("sys")?.getattr("modules")?;
    modules.set_item("ascent.build", &module)?;
    modules.set_item("ascent.artifact", &artifact)?;
    root.add("build", module)?;
    root.add("artifact", artifact)?;
    Ok(())
}
