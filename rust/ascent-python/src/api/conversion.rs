//! Typed rows and descriptors cross `PyO3` without wire serialization.
use super::types::{EngineError, value};
use gerbil_ascent as engine;
use pyo3::{
    Bound, Py, PyAny, PyResult, Python,
    types::{PyAnyMethods, PyDict, PyDictMethods, PyList, PyListMethods},
};
pub(super) fn typed_value(input: &Bound<'_, PyAny>, ty: engine::Type) -> PyResult<engine::Value> {
    if ty == engine::Type::Symbol && input.is_instance_of::<pyo3::types::PyString>() {
        let name = input.extract::<String>()?;
        if name.len() > 4096 {
            return Err(EngineError::new_err("native symbol value byte bound"));
        }
        return Ok(engine::Value::Symbol(name.into()));
    }
    value(input)
}
pub(super) fn typed_rows(
    input: &Bound<'_, PyAny>,
    relation: &engine::Relation,
) -> PyResult<Vec<engine::Row>> {
    input
        .try_iter()?
        .map(|row| {
            let row = row?;
            let fields = row.try_iter()?.collect::<PyResult<Vec<_>>>()?;
            if fields.len() != relation.columns.len() {
                return Err(EngineError::new_err("source row arity"));
            }
            fields
                .iter()
                .zip(&relation.columns)
                .map(|(v, ty)| typed_value(v, *ty))
                .collect::<PyResult<Vec<_>>>()
                .map(Into::into)
        })
        .collect()
}
pub(super) fn kind(ty: engine::Type) -> &'static str {
    match ty {
        engine::Type::Any => "any",
        engine::Type::Scalar => "scalar",
        engine::Type::Integer => "integer",
        engine::Type::Boolean => "boolean",
        engine::Type::Text => "string",
        engine::Type::Symbol => "symbol",
    }
}
pub(super) fn descriptors<'py>(
    py: Python<'py>,
    relations: &[engine::Relation],
) -> PyResult<Bound<'py, PyList>> {
    let out = PyList::empty(py);
    for relation in relations {
        let item = PyDict::new(py);
        item.set_item("name", &relation.name)?;
        item.set_item("source", relation.source)?;
        let columns = PyList::empty(py);
        for (ty, domain) in relation.columns.iter().zip(&relation.domains) {
            let column = PyDict::new(py);
            column.set_item("kind", kind(*ty))?;
            if let Some(domain) = domain {
                column.set_item(
                    "domain",
                    PyList::new(
                        py,
                        domain
                            .iter()
                            .map(|v| scalar(py, v))
                            .collect::<PyResult<Vec<_>>>()?,
                    )?,
                )?;
            }
            columns.append(column)?;
        }
        item.set_item("columns", columns)?;
        out.append(item)?;
    }
    Ok(out)
}
pub(super) fn scalar(py: Python<'_>, value: &engine::Value) -> PyResult<Py<PyAny>> {
    use pyo3::IntoPyObjectExt;
    match value {
        engine::Value::Object(v) => Ok(super::module_values::graph(py, v.graph())?
            .unbind()
            .into_any()),
        engine::Value::Integer(v) => v.into_py_any(py),
        engine::Value::Boolean(v) => v.into_py_any(py),
        engine::Value::Text(v) | engine::Value::Symbol(v) => v.as_ref().into_py_any(py),
    }
}
pub(super) fn relation_rows<'py>(
    py: Python<'py>,
    rows: &[engine::Row],
) -> PyResult<Bound<'py, PyList>> {
    PyList::new(
        py,
        rows.iter()
            .map(|row| {
                PyList::new(
                    py,
                    row.iter()
                        .map(|v| scalar(py, v))
                        .collect::<PyResult<Vec<_>>>()?,
                )
            })
            .collect::<PyResult<Vec<_>>>()?,
    )
}
