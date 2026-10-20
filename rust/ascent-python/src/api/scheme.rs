//! Qualification entry for the linked native business ABI, without Python CFFI.
use super::{packets, types::source_error};
use std::sync::OnceLock;
// The private reference-oracle entry retains its own scope. Production Engine
// calls never pass through this qualification owner.
static REFERENCE: OnceLock<gerbil_ascent::Result<ascent_scheme::ProcessOwner>> = OnceLock::new();
use pyo3::{Bound, Py, PyAny, PyResult, Python, pyfunction};

#[pyfunction]
pub(super) fn _scheme_call(py: Python<'_>, input: &Bound<'_, PyAny>) -> PyResult<Py<PyAny>> {
    let request = packets::read(input)?;
    let result = py
        .detach(|| {
            REFERENCE
                .get_or_init(|| ascent_scheme::ProcessPool::new(1)?.owner(0))
                .as_ref()
                .map_err(Clone::clone)?
                .call(request)
        })
        .map_err(source_error)?;
    packets::write(py, &result)
}
