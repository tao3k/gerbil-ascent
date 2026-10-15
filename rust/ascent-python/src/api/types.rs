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

pub(super) fn admission_deadline(
    timeout: std::time::Duration,
) -> engine::Result<std::time::Instant> {
    std::time::Instant::now()
        .checked_add(timeout)
        .ok_or(engine::Error::Timeout)
}

pub(super) fn remaining(deadline: std::time::Instant) -> engine::Result<std::time::Duration> {
    let duration = deadline.saturating_duration_since(std::time::Instant::now());
    if duration.is_zero() {
        Err(engine::Error::Timeout)
    } else {
        Ok(duration)
    }
}

pub(super) fn lock_before<'a, T>(
    mutex: &'a std::sync::Mutex<T>,
    deadline: std::time::Instant,
    cancellation: &engine::Cancellation,
) -> engine::Result<std::sync::MutexGuard<'a, T>> {
    loop {
        if cancellation.is_canceled() {
            return Err(engine::Error::Canceled);
        }
        let time_left = remaining(deadline)?;
        match mutex.try_lock() {
            Ok(guard) => return Ok(guard),
            Err(std::sync::TryLockError::Poisoned(_)) => return Err(engine::Error::Closed),
            Err(std::sync::TryLockError::WouldBlock) => {
                std::thread::sleep(time_left.min(std::time::Duration::from_millis(1)));
            }
        }
    }
}

#[cfg(test)]
#[path = "../../tests/unit/admission.rs"]
mod admission_tests;
