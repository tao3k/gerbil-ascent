//! Owned typed Python declarations delegate admission to the Rust library.
use super::types::{error, value};
use gerbil_ascent as engine;
use pyo3::{Bound, PyAny, PyRef, PyResult, exceptions::PyValueError, pyclass, pymethods};
#[pyclass(name = "Term", frozen)]
#[derive(Clone)]
pub(super) struct Term(engine::Term);
#[pymethods]
impl Term {
    #[staticmethod]
    fn var(id: u32) -> Self {
        Self(engine::Term::Variable(id))
    }
    #[staticmethod]
    fn literal(input: &Bound<'_, PyAny>) -> PyResult<Self> {
        Ok(Self(engine::Term::Literal(value(input)?)))
    }
    #[staticmethod]
    fn wildcard() -> Self {
        Self(engine::Term::Wildcard)
    }
}
#[pyclass(name = "Atom", frozen)]
#[derive(Clone)]
pub(super) struct Atom {
    atom: engine::Atom,
    negative: bool,
}
#[pymethods]
impl Atom {
    #[new]
    fn new(relation: String, terms: Vec<PyRef<'_, Term>>) -> Self {
        Self {
            atom: engine::Atom::new(relation, terms.into_iter().map(|t| t.0.clone()).collect()),
            negative: false,
        }
    }
    fn negated(&self) -> Self {
        Self {
            atom: self.atom.clone(),
            negative: true,
        }
    }
}
#[pyclass(name = "Program")]
#[derive(Clone, Default)]
pub(super) struct Program(pub(super) engine::Program);
#[pymethods]
impl Program {
    #[new]
    fn new() -> Self {
        Self::default()
    }
    #[staticmethod]
    fn read_rule_sources(sources: Vec<String>) -> PyResult<Self> {
        let borrowed: Vec<_> = sources.iter().map(String::as_str).collect();
        let parsed = engine::Program::read_rule_sources(&borrowed)
            .map(Self)
            .map_err(error);
        drop(sources);
        parsed
    }
    #[staticmethod]
    fn read_sources(sources: Vec<String>) -> PyResult<Self> {
        let parsed =
            engine::Program::read_sources(&sources.iter().map(String::as_str).collect::<Vec<_>>())
                .map(Self)
                .map_err(error);
        drop(sources);
        parsed
    }
    #[pyo3(signature = (name, columns, source=false))]
    fn relation(&mut self, name: String, columns: Vec<String>, source: bool) -> PyResult<()> {
        let columns = columns
            .into_iter()
            .map(|name| match name.as_str() {
                "any" => Ok(engine::Type::Any),
                "scalar" => Ok(engine::Type::Scalar),
                "integer" => Ok(engine::Type::Integer),
                "boolean" => Ok(engine::Type::Boolean),
                "text" => Ok(engine::Type::Text),
                "symbol" => Ok(engine::Type::Symbol),
                _ => Err(PyValueError::new_err("unknown column type")),
            })
            .collect::<PyResult<Vec<_>>>()?;
        self.0
            .relations
            .push(engine::Relation::new(name, columns, source));
        Ok(())
    }
    fn rule(&mut self, head: PyRef<'_, Atom>, body: Vec<PyRef<'_, Atom>>) -> PyResult<()> {
        if head.negative {
            return Err(PyValueError::new_err("negative head"));
        }
        let head_atom = head.atom.clone();
        drop(head);
        self.0.rules.push(engine::Rule {
            head: head_atom,
            body: body
                .into_iter()
                .map(|a| {
                    if a.negative {
                        engine::Clause::negative(a.atom.clone())
                    } else {
                        engine::Clause::positive(a.atom.clone())
                    }
                })
                .collect(),
        });
        Ok(())
    }
}
