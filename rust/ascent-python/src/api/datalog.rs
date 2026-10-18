//! Rust readers and evaluators expose owned graph data and native scalar answers.
use super::{bindings::Engine, packets, types::error};
use gerbil_ascent::{Data, DatalogRequest};
use pyo3::{
    Bound, Py, PyAny, PyResult, Python, pyfunction,
    types::{PyDict, PyDictMethods, PyList, PyListMethods, PyTuple},
};
#[pyfunction]
#[pyo3(signature=(facts,rules,queries,*,schema=None))]
pub(super) fn read_datalog(
    py: Python<'_>,
    facts: &Bound<'_, PyAny>,
    rules: &str,
    queries: &Bound<'_, PyAny>,
    schema: Option<&Bound<'_, PyAny>>,
) -> PyResult<(Py<PyAny>, Py<PyAny>)> {
    let facts = packets::read(facts)?;
    let queries = packets::read(queries)?;
    let schema = schema.map(packets::read).transpose()?;
    let graph = py.detach(|| {
        gerbil_ascent::read_datalog(&DatalogRequest {
            facts: &facts,
            source: rules,
            queries: &queries,
            schema: schema.as_ref(),
        })
        .map_err(error)
    })?;
    Ok((
        packets::write(py, &graph.program)?,
        packets::write(py, &graph.queries)?,
    ))
}
#[pyfunction]
#[pyo3(signature=(engine,facts,rules,queries,*,schema=None))]
pub(super) fn evaluate_datalog(
    py: Python<'_>,
    engine: &Engine,
    facts: &Bound<'_, PyAny>,
    rules: &str,
    queries: &Bound<'_, PyAny>,
    schema: Option<&Bound<'_, PyAny>>,
) -> PyResult<(Py<PyAny>, Py<PyAny>)> {
    let facts = packets::read(facts)?;
    let queries = packets::read(queries)?;
    let schema = schema.map(packets::read).transpose()?;
    let (answers, receipt) = py.detach(|| {
        gerbil_ascent::evaluate_datalog(
            &engine.0,
            &DatalogRequest {
                facts: &facts,
                source: rules,
                queries: &queries,
                schema: schema.as_ref(),
            },
        )
        .map_err(error)
    })?;
    Ok((write_answers(py, &answers)?, packets::write(py, &receipt)?))
}
fn write_answers(py: Python<'_>, answers: &Data) -> PyResult<Py<PyAny>> {
    let result = PyDict::new(py);
    for (label, rows) in answers.map().map_err(error)? {
        result.set_item(label, answer_rows(py, rows)?)?;
    }
    Ok(result.unbind().into_any())
}
fn answer_rows<'py>(py: Python<'py>, rows: &Data) -> PyResult<Bound<'py, PyList>> {
    let out = PyList::empty(py);
    for row in rows.list().map_err(error)? {
        let cells = row
            .list()
            .map_err(error)?
            .iter()
            .map(|v| packets::write(py, v))
            .collect::<PyResult<Vec<_>>>()?;
        out.append(PyTuple::new(py, cells)?)?;
    }
    Ok(out)
}
