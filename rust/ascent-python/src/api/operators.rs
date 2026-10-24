//! Inert typed clause builders. Complete rule admission remains a Rust engine operation.
use super::packets;
use gerbil_ascent::Data;
use pyo3::{Bound, Py, PyAny, PyResult, Python, pyfunction, types::PyTuple};
fn field(value: &Bound<'_, PyAny>) -> PyResult<Data> {
    packets::read(value)
}
#[pyfunction(name = "where")]
#[pyo3(signature=(operator,*terms))]
pub(super) fn predicate(
    py: Python<'_>,
    operator: &str,
    terms: &Bound<'_, PyTuple>,
) -> PyResult<Py<PyAny>> {
    packets::write(
        py,
        &Data::object([
            ("mode", "where".into()),
            ("operator", operator.into()),
            ("terms", field(terms.as_any())?),
        ]),
    )
}
#[pyfunction]
#[pyo3(signature=(output,operator,*terms))]
pub(super) fn compute(
    py: Python<'_>,
    output: &str,
    operator: &str,
    terms: &Bound<'_, PyTuple>,
) -> PyResult<Py<PyAny>> {
    packets::write(
        py,
        &Data::object([
            ("mode", "compute".into()),
            ("output", output.into()),
            ("operator", operator.into()),
            ("terms", field(terms.as_any())?),
        ]),
    )
}
#[pyfunction]
#[pyo3(signature=(output,operator,relation,terms,inputs=None))]
pub(super) fn reduce(
    output: &str,
    operator: &str,
    relation: &str,
    terms: &Bound<'_, PyAny>,
    inputs: Option<&Bound<'_, PyAny>>,
) -> PyResult<Py<PyAny>> {
    packets::write(
        terms.py(),
        &Data::object([
            ("mode", "reduce".into()),
            ("output", output.into()),
            ("operator", operator.into()),
            ("relation", relation.into()),
            ("terms", field(terms)?),
            (
                "inputs",
                inputs
                    .map(field)
                    .transpose()?
                    .unwrap_or_else(|| Data::List(Vec::new())),
            ),
        ]),
    )
}
#[pyfunction]
pub(super) fn dependencies(
    clauses: &Bound<'_, PyAny>,
) -> PyResult<std::collections::BTreeSet<String>> {
    let clauses = packets::read(clauses)?;
    clauses
        .list()
        .map_err(super::types::error)?
        .iter()
        .filter_map(|c| c.get("relation"))
        .map(|n| n.text().map(str::to_string).map_err(super::types::error))
        .collect()
}
