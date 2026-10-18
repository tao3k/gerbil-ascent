//! Strict transport admission for independently scoped Scheme components.
use super::types::EngineError;
use gerbil_ascent::{Component, Dependency};
use pyo3::{
    Bound, PyAny, PyResult,
    types::{PyAnyMethods, PyDict, PyDictMethods, PyList, PyListMethods},
};
use std::collections::BTreeSet;
fn fields(dict: &Bound<'_, PyDict>, expected: &[&str]) -> PyResult<()> {
    if dict.len() != expected.len()
        || expected
            .iter()
            .any(|key| !dict.contains(key).unwrap_or(false))
    {
        return Err(EngineError::new_err("invalid component manifest fields"));
    }
    Ok(())
}
fn field<'py>(dict: &Bound<'py, PyDict>, key: &str) -> PyResult<Bound<'py, PyAny>> {
    dict.get_item(key)?
        .ok_or_else(|| EngineError::new_err("missing component field"))
}
pub(super) fn read(
    manifest: &Bound<'_, PyAny>,
    sources: &Bound<'_, PyAny>,
) -> PyResult<Vec<Component>> {
    let manifest = manifest.cast::<PyDict>()?;
    fields(manifest, &["schema", "components"])?;
    if field(manifest, "schema")?.extract::<String>()? != "ascent.evidence-components.v1" {
        return Err(EngineError::new_err("unsupported component schema"));
    }
    let sources = sources.cast::<PyDict>()?;
    let components = field(manifest, "components")?;
    let components = components.cast::<PyList>()?;
    let mut paths = BTreeSet::new();
    let mut out = Vec::new();
    for component in components.iter() {
        let component = component.cast::<PyDict>()?;
        fields(component, &["id", "source", "exports", "dependencies"])?;
        let path: String = field(component, "source")?.extract()?;
        paths.insert(path.clone());
        let source: String = field(sources, &path)?.extract()?;
        let dependencies = field(component, "dependencies")?;
        let dependencies = dependencies.cast::<PyList>()?;
        let mut imports = Vec::new();
        for dependency in dependencies.iter() {
            let dependency = dependency.cast::<PyDict>()?;
            fields(dependency, &["component", "bindings"])?;
            imports.push(Dependency {
                component: field(dependency, "component")?.extract()?,
                bindings: field(dependency, "bindings")?.extract()?,
            });
        }
        out.push(Component {
            id: field(component, "id")?.extract()?,
            source,
            exports: Some(field(component, "exports")?.extract()?),
            dependencies: imports,
        });
    }
    if paths.len() != sources.len() {
        return Err(EngineError::new_err("unregistered component source"));
    }
    Ok(out)
}
