//! Embedded source manifest, verified by the upstream package owner after install.
use gerbil_ascent::Data;
use gerbil_scheme_python::{PackageManifest, VerifiedPackage};
use pyo3::{
    Bound, Py, PyAny, PyResult, Python,
    exceptions::PyValueError,
    pyclass, pyfunction, pymethods,
    types::{PyAnyMethods, PyModule, PyModuleMethods},
    wrap_pyfunction,
};
use std::{collections::BTreeMap, path::PathBuf};

fn failure(e: impl std::fmt::Display) -> pyo3::PyErr {
    PyValueError::new_err(e.to_string())
}

#[pyclass(name = "PackageManifest", frozen)]
struct Inventory(PackageManifest);
#[pymethods]
impl Inventory {
    #[new]
    fn new(json: &[u8]) -> PyResult<Self> {
        Ok(Self(PackageManifest::from_json(json)?))
    }
    fn verify(&self, py: Python<'_>, root: &Bound<'_, PyAny>) -> PyResult<Verified> {
        let root = root.extract::<PathBuf>()?;
        py.detach(|| self.0.verify(&root))
            .map(Verified)
            .map_err(Into::into)
    }
}

#[pyclass(name = "VerifiedPackage", frozen)]
struct Verified(VerifiedPackage);
#[pymethods]
impl Verified {
    #[getter]
    fn root(&self) -> PathBuf {
        self.0.root().to_owned()
    }
    fn reverify(&self, py: Python<'_>) -> PyResult<Self> {
        py.detach(|| self.0.reverify())
            .map(Self)
            .map_err(Into::into)
    }
    fn copy_to(&self, py: Python<'_>, destination: &Bound<'_, PyAny>) -> PyResult<Self> {
        let destination = destination.extract::<PathBuf>()?;
        py.detach(|| self.0.copy_to(&destination))
            .map(Self)
            .map_err(Into::into)
    }
    fn publish_to(&self, py: Python<'_>, destination: &Bound<'_, PyAny>) -> PyResult<Self> {
        let destination = destination.extract::<PathBuf>()?;
        py.detach(|| self.0.publish_to(&destination))
            .map(Self)
            .map_err(Into::into)
    }
}
#[pyfunction]
fn runtime_identity(py: Python<'_>) -> PyResult<Py<PyAny>> {
    let manifest = PackageManifest::from_json(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/source_inventory.json"
    )))
    .map_err(failure)?;
    let root = py
        .import("ascent")?
        .getattr("__file__")?
        .extract::<PathBuf>()?
        .parent()
        .ok_or_else(|| failure("installed package parent required"))?
        .canonicalize()?;
    let resource = py.detach(|| manifest.verify(&root)).map_err(failure)?;
    let files = &resource.manifest().files;
    let sources = files
        .iter()
        .map(|(name, item)| {
            (
                name.trim_start_matches("_sources/").to_owned(),
                Data::Text(item.sha256.clone()),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let origins = files
        .iter()
        .map(|(name, item)| {
            (
                name.trim_start_matches("_sources/").to_owned(),
                Data::Text(item.origin.clone()),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let runtime = files
        .iter()
        .map(|(name, item)| {
            (
                root.join(name).to_string_lossy().into_owned(),
                Data::Text(item.sha256.clone()),
            )
        })
        .collect::<BTreeMap<_, _>>();
    let packaged = files
        .iter()
        .map(|(name, item)| (name.clone(), Data::Text(item.sha256.clone())))
        .collect::<BTreeMap<_, _>>();
    let mapping = files
        .keys()
        .map(|name| {
            (
                root.join(name).to_string_lossy().into_owned(),
                Data::Text(name.clone()),
            )
        })
        .collect::<BTreeMap<_, _>>();
    super::rust_api::packets::write(py, &Data::object([
        ("schema", "ascent.rust-build.v1".into()),
        ("backend", "rust".into()),
        ("rayon", cfg!(feature="rayon").into()),
        ("sourceInputs", Data::Map(sources)),
        ("sourceOrigins", Data::Map(origins)),
        ("runtimeInputs", Data::Map(runtime)),
        ("packageInputs", Data::Map(packaged)),
        ("runtimePackagePaths", Data::Map(mapping)),
        ("sourceRoot", root.join("_sources").to_string_lossy().to_string().into()),
        ("inventoryScope", "local Rust/PyO3/bridge sources and build inputs; transitive dependency revisions in Cargo.lock".into()),
    ]))
}
pub(super) fn install(root: &Bound<'_, PyModule>) -> PyResult<()> {
    let build = PyModule::new(root.py(), "ascent.build")?;
    build.add_function(wrap_pyfunction!(runtime_identity, &build)?)?;
    build.add_class::<Inventory>()?;
    build.add_class::<Verified>()?;
    root.py()
        .import("sys")?
        .getattr("modules")?
        .set_item("ascent.build", &build)?;
    root.add("build", build)?;
    Ok(())
}
