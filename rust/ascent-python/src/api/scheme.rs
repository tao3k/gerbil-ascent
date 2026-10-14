//! Qualification entry for the linked native business ABI, without Python CFFI.
use super::{packets, types::source_error};
use pyo3::{Bound, Py, PyAny, PyResult, Python, pyfunction};

#[pyfunction]
pub(super) fn _scheme_call(py: Python<'_>, input: &Bound<'_, PyAny>) -> PyResult<Py<PyAny>> {
    let request = packets::read(input)?;
    let result = py
        .detach(|| ascent_scheme::call(request))
        .map_err(source_error)?;
    packets::write(py, &result)
}
