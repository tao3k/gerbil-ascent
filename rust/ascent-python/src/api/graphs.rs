//! Rust-generated value observations; inference is never rerun for projection.
use gerbil_ascent::{Row, rows_graph};
use pyo3::{Bound, PyResult, Python, types::PyDict};
pub(super) fn rows<'py>(py: Python<'py>, rows: &[Row]) -> PyResult<Bound<'py, PyDict>> {
    let graph = rows_graph(rows).map_err(super::types::source_error)?;
    super::module_values::graph(py, &graph)
}
