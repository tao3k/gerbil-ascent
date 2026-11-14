//! Direct Python/native structured values, without text serialization or a Python evaluator.
use gerbil_ascent::Data;
use pyo3::{
    Bound, IntoPyObjectExt, Py, PyAny, PyResult, Python,
    exceptions::PyValueError,
    types::{
        PyAnyMethods, PyBool, PyDict, PyDictMethods, PyFloat, PyInt, PyList, PyListMethods,
        PyString, PyTuple, PyTupleMethods,
    },
};
use std::collections::BTreeMap;
pub(super) fn read(value: &Bound<'_, PyAny>) -> PyResult<Data> {
    decode(value, 0, &mut 0)
}
fn decode(value: &Bound<'_, PyAny>, depth: usize, nodes: &mut usize) -> PyResult<Data> {
    if depth > 128 || *nodes >= 1_000_000 {
        return Err(PyValueError::new_err("native data structure bound"));
    }
    *nodes += 1;
    if value.is_none() {
        return Ok(Data::Null);
    }
    if value.is_instance_of::<PyBool>() {
        return value.extract().map(Data::Bool);
    }
    if value.is_instance_of::<PyInt>() {
        return value.extract().map(Data::Integer);
    }
    if value.is_instance_of::<PyFloat>() {
        let v: f64 = value.extract()?;
        if !v.is_finite() {
            return Err(PyValueError::new_err("finite observation number required"));
        }
        return Ok(Data::Real(v.to_bits()));
    }
    if value.is_instance_of::<PyString>() {
        return value.extract().map(Data::Text);
    }
    if let Ok(values) = value.cast::<PyList>() {
        return values
            .iter()
            .map(|v| decode(&v, depth + 1, nodes))
            .collect::<PyResult<_>>()
            .map(Data::List);
    }
    if let Ok(values) = value.cast::<PyTuple>() {
        return values
            .iter()
            .map(|v| decode(&v, depth + 1, nodes))
            .collect::<PyResult<_>>()
            .map(Data::List);
    }
    if let Ok(values) = value.cast::<PyDict>() {
        let mut out = BTreeMap::new();
        for (key, value) in values {
            out.insert(key.extract()?, decode(&value, depth + 1, nodes)?);
        }
        return Ok(Data::Map(out));
    }
    Err(PyValueError::new_err("unsupported native structured value"))
}
pub(super) fn write(py: Python<'_>, value: &Data) -> PyResult<Py<PyAny>> {
    match value {
        Data::Null => Ok(py.None()),
        Data::Bool(v) => v.into_py_any(py),
        Data::Integer(v) => v.into_py_any(py),
        Data::Real(v) => f64::from_bits(*v).into_py_any(py),
        Data::Text(v) => v.into_py_any(py),
        Data::List(values) => write_list(py, values),
        Data::Map(values) => write_map(py, values),
    }
}
fn write_list(py: Python<'_>, values: &[Data]) -> PyResult<Py<PyAny>> {
    let out = PyList::empty(py);
    for value in values {
        out.append(write(py, value)?)?;
    }
    Ok(out.unbind().into_any())
}
fn write_map(py: Python<'_>, values: &BTreeMap<String, Data>) -> PyResult<Py<PyAny>> {
    let out = PyDict::new(py);
    for (key, value) in values {
        out.set_item(key, write(py, value)?)?;
    }
    Ok(out.unbind().into_any())
}
