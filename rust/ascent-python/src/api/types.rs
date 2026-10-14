//! Shared Python scalar conversion, cancellation and typed exceptions.
use gerbil_ascent as engine;
use pyo3::{
    Bound, PyAny, PyErr, PyRef, PyResult,
    exceptions::{PyRuntimeError, PyValueError},
    pyclass, pymethods,
    types::{PyAnyMethods, PyBool, PyInt, PyString},
};
pyo3::create_exception!(ascent, EngineError, PyRuntimeError);
pyo3::create_exception!(ascent, ResourceLimitError, EngineError);
pub(super) fn error(error: engine::Error) -> PyErr {
    match error {
        engine::Error::InvalidProgram(message) | engine::Error::InvalidUpdate(message) => {
            PyValueError::new_err(message)
        }
        engine::Error::FactLimit
        | engine::Error::SourceFactLimit
        | engine::Error::DerivedFactLimit
        | engine::Error::OutputFactLimit
        | engine::Error::StateLimit => ResourceLimitError::new_err(error.to_string()),
        _ => PyRuntimeError::new_err(error.to_string()),
    }
}
#[pyclass(name = "Symbol", frozen, eq, hash)]
#[derive(Clone, PartialEq, Eq, Hash)]
pub(super) struct Symbol {
    #[pyo3(get)]
    pub(super) name: String,
}
#[pymethods]
impl Symbol {
    #[new]
    fn new(name: String) -> Self {
        Self { name }
    }
}
pub(super) fn value(value: &Bound<'_, PyAny>) -> PyResult<engine::Value> {
    if value.is_instance_of::<PyBool>() {
        Ok(engine::Value::Boolean(value.extract()?))
    } else if value.is_instance_of::<PyInt>() {
        Ok(engine::Value::Integer(value.extract()?))
    } else if value.is_instance_of::<PyString>() {
        Ok(engine::Value::Text(value.extract::<String>()?.into()))
    } else if let Ok(symbol) = value.extract::<PyRef<'_, Symbol>>() {
        Ok(engine::Value::Symbol(symbol.name.clone().into()))
    } else {
        Err(PyValueError::new_err(
            "expected exact integer, bool, str, or Symbol",
        ))
    }
}
#[pyclass(name = "Cancellation", frozen)]
#[derive(Default)]
pub(super) struct Cancellation(pub(super) engine::Cancellation);
#[pymethods]
impl Cancellation {
    #[new]
    fn new() -> Self {
        Self::default()
    }
    fn cancel(&self) {
        self.0.cancel();
    }
}

/// Rust-owned callable or compound value; arguments can borrow this lease directly.
#[pyclass(name = "Value", frozen)]
pub(super) struct OwnedValue(pub(super) ascent_scheme::ModuleValue);

#[pyclass(name = "ResultValue", frozen)]
pub(super) struct ResultValue(pub(super) CellValue);
#[derive(Clone)]
pub(super) enum CellValue {
    Core(engine::RowValue),
    Scheme(ascent_scheme::ResultValue),
}

pub(super) fn source_error(error: engine::Error) -> PyErr {
    let text = error.to_string();
    let exception = match error {
        engine::Error::Closed => {
            pyo3::exceptions::PyValueError::new_err("DSL owner closed or released")
        }
        engine::Error::FactLimit
        | engine::Error::SourceFactLimit
        | engine::Error::DerivedFactLimit
        | engine::Error::OutputFactLimit
        | engine::Error::StateLimit => ResourceLimitError::new_err(text),
        _ => EngineError::new_err(text),
    };
    drop(error);
    exception
}
pub(super) fn ceiling(value: Option<&Bound<'_, PyAny>>) -> PyResult<Option<usize>> {
    let Some(value) = value else { return Ok(None) };
    if value.is_none() {
        return Ok(None);
    }
    if value.is_instance_of::<PyBool>() {
        return Err(EngineError::new_err(
            "finite fact limits must be positive integers",
        ));
    }
    let n = value
        .extract::<usize>()
        .map_err(|_| EngineError::new_err("finite fact limits must be positive integers"))?;
    if n == 0 {
        return Err(EngineError::new_err(
            "finite fact limits must be positive integers",
        ));
    }
    Ok(Some(n))
}

pub(super) fn result_handle(value: &Bound<'_, PyAny>) -> PyResult<u64> {
    if value.is_instance_of::<PyBool>() {
        return Err(EngineError::new_err(
            "result handle must be a positive exact integer",
        ));
    }
    let handle = value.extract::<u64>()?;
    if handle == 0 {
        return Err(EngineError::new_err(
            "result handle must be a positive exact integer",
        ));
    }
    Ok(handle)
}
