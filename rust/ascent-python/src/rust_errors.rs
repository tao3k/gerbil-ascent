//! Common typed Rust errors, without VM-dependent conversion paths.
pub(super) use super::error;
pub(super) fn source_error(error: gerbil_ascent::Error) -> pyo3::PyErr {
    super::error(error)
}
