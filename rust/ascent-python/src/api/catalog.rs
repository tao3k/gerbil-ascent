//! Typed Python catalog conversion, with no JSON serialization or evaluation.
use super::{conversion as sources, types::EngineError};
use gerbil_ascent as engine;
use pyo3::{
    Bound, PyAny, PyResult, Python,
    types::{PyDict, PyList},
    types::{PyDictMethods, PyListMethods},
};
use std::collections::BTreeMap;
pub(super) struct Catalog {
    pub program: engine::Program,
    pub sources: BTreeMap<String, Vec<engine::Row>>,
    pub queries: Vec<String>,
}
pub(super) fn read(input: &Bound<'_, PyAny>) -> PyResult<Catalog> {
    let value = super::packets::read(input)?;
    let catalog = engine::Catalog::read(&value).map_err(super::types::source_error)?;
    Ok(Catalog {
        program: catalog.program,
        sources: BTreeMap::new(),
        queries: catalog.queries,
    })
}
fn write_term<'py>(py: Python<'py>, input: &engine::Term) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    match input {
        engine::Term::Variable(id) => out.set_item("var", format!("v{id}"))?,
        engine::Term::Literal(value) => out.set_item("const", sources::scalar(py, value)?)?,
        engine::Term::Wildcard => out.set_item("wildcard", true)?,
    }
    Ok(out)
}
fn write_atom<'py>(
    py: Python<'py>,
    input: &engine::Atom,
    negative: bool,
) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    out.set_item("relation", &input.relation)?;
    out.set_item("not", negative)?;
    out.set_item(
        "terms",
        PyList::new(
            py,
            input
                .terms
                .iter()
                .map(|t| write_term(py, t))
                .collect::<PyResult<Vec<_>>>()?,
        )?,
    )?;
    Ok(out)
}
fn write_clause<'py>(py: Python<'py>, input: &engine::Clause) -> PyResult<Bound<'py, PyDict>> {
    match input {
        engine::Clause::Relation { atom, negative } => write_atom(py, atom, *negative),
        engine::Clause::Guard {
            expression: engine::Expression::Call(operator, operands),
            ..
        } => {
            let name = match operator {
                engine::Operator::Less => "<",
                engine::Operator::Even => "even?",
                _ => {
                    return Err(EngineError::new_err(
                        "no finite typed catalog guard projection",
                    ));
                }
            };
            let out = PyDict::new(py);
            out.set_item("mode", "where")?;
            out.set_item("operator", name)?;
            let terms = operands
                .iter()
                .map(|e| match e {
                    engine::Expression::Term(t) => write_term(py, t),
                    engine::Expression::Call(..) => Err(EngineError::new_err(
                        "no nested typed catalog guard projection",
                    )),
                })
                .collect::<PyResult<Vec<_>>>()?;
            out.set_item("terms", PyList::new(py, terms)?)?;
            Ok(out)
        }
        _ => Err(EngineError::new_err("no typed catalog operator projection")),
    }
}
pub(super) fn write<'py>(
    py: Python<'py>,
    program: &engine::Program,
) -> PyResult<Bound<'py, PyDict>> {
    if program.relation_limit.is_some()
        || program.relations.iter().any(|r| {
            r.lattice.is_some()
                || r.columns
                    .iter()
                    .any(|ty| matches!(ty, engine::Type::Any | engine::Type::Scalar))
        })
    {
        return Err(EngineError::new_err(
            "dynamic Scheme values and lattices have no finite typed catalog catalog projection",
        ));
    }
    let out = PyDict::new(py);
    let relations = sources::descriptors(py, &program.relations)?;
    for (declaration, relation) in program.relations.iter().zip(relations.iter()) {
        if !declaration.rows.is_empty() {
            relation
                .cast::<PyDict>()?
                .set_item("rows", sources::relation_rows(py, &declaration.rows)?)?;
        }
    }
    out.set_item("relations", relations)?;
    let rules = PyList::empty(py);
    for rule in &program.rules {
        let item = PyDict::new(py);
        item.set_item(
            "head",
            PyList::new(py, [write_atom(py, &rule.head, false)?])?,
        )?;
        item.set_item(
            "body",
            PyList::new(
                py,
                rule.body
                    .iter()
                    .map(|c| write_clause(py, c))
                    .collect::<PyResult<Vec<_>>>()?,
            )?,
        )?;
        rules.append(item)?;
    }
    out.set_item("rules", rules)?;
    Ok(out)
}
pub(super) fn projection<'py>(
    py: Python<'py>,
    program: &engine::Program,
) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    match write(py, program) {
        Ok(program) => {
            out.set_item("status", "supported")?;
            out.set_item("program", program)?;
        }
        Err(error) if error.is_instance_of::<EngineError>(py) => {
            out.set_item("status", "unsupported")?;
            out.set_item(
                "reason",
                "native DSL expressions have no finite typed catalog catalog projection",
            )?;
        }
        Err(error) => return Err(error),
    }
    Ok(out)
}
