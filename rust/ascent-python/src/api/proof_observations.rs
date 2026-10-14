//! Typed factors exposed for inspection; Rust remains the verifier.
use gerbil_ascent::{Atom, Expression, Operator, ProvenanceWitness, Reducer, Term, Value};
use pyo3::{
    Bound, PyResult, Python,
    types::{PyDict, PyDictMethods, PyList, PyListMethods},
};
pub(super) fn witnesses<'py>(
    py: Python<'py>,
    factors: &[ProvenanceWitness],
) -> PyResult<Bound<'py, PyList>> {
    let out = PyList::empty(py);
    for factor in factors {
        let item = PyDict::new(py);
        match factor {
            ProvenanceWitness::Absent(a) => {
                item.set_item("kind", "absent")?;
                item.set_item("atom", atom(py, a)?)?;
            }
            ProvenanceWitness::Guard(e) => {
                item.set_item("kind", "guard")?;
                item.set_item("expression", expression(py, e)?)?;
            }
            ProvenanceWitness::Compute {
                slot,
                expression: e,
                value,
            } => {
                item.set_item("kind", "compute")?;
                item.set_item("slot", slot)?;
                item.set_item("expression", expression(py, e)?)?;
                item.set_item("value", literal(py, value)?)?;
            }
            ProvenanceWitness::Aggregate {
                atom: a,
                operator,
                rows,
                value,
            } => {
                item.set_item("kind", "aggregate")?;
                item.set_item("atom", atom(py, a)?)?;
                item.set_item(
                    "operator",
                    match operator {
                        Reducer::Mean => "mean",
                        Reducer::Count => "count",
                        Reducer::Sum => "sum",
                        Reducer::Min => "min",
                        Reducer::Max => "max",
                    },
                )?;
                item.set_item("rows", rows)?;
                item.set_item("value", literal(py, value)?)?;
            }
        }
        out.append(item)?;
    }
    Ok(out)
}
fn literal<'py>(py: Python<'py>, value: &Value) -> PyResult<Bound<'py, PyDict>> {
    super::graphs::rows(py, &[vec![value.clone()].into()])
}
fn term<'py>(py: Python<'py>, value: &Term) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    match value {
        Term::Literal(v) => {
            out.set_item("kind", "literal")?;
            out.set_item("value", literal(py, v)?)?;
        }
        Term::Variable(slot) => {
            out.set_item("kind", "variable")?;
            out.set_item("slot", slot)?;
        }
        Term::Wildcard => out.set_item("kind", "wildcard")?,
    }
    Ok(out)
}
fn atom<'py>(py: Python<'py>, value: &Atom) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    out.set_item("relation", &value.relation)?;
    let terms = PyList::empty(py);
    for value in &value.terms {
        terms.append(term(py, value)?)?;
    }
    out.set_item("terms", terms)?;
    Ok(out)
}
fn expression<'py>(py: Python<'py>, value: &Expression) -> PyResult<Bound<'py, PyDict>> {
    match value {
        Expression::Term(t) => term(py, t),
        Expression::Call(op, args) => {
            let out = PyDict::new(py);
            out.set_item("kind", "call")?;
            out.set_item("operator", operator(*op))?;
            let values = PyList::empty(py);
            for arg in args {
                values.append(expression(py, arg)?)?;
            }
            out.set_item("operands", values)?;
            Ok(out)
        }
    }
}
fn operator(op: Operator) -> &'static str {
    match op {
        Operator::Less => "<",
        Operator::LessEqual => "<=",
        Operator::Greater => ">",
        Operator::GreaterEqual => ">=",
        Operator::NumericEqual => "=",
        Operator::Equal => "equal?",
        Operator::Add => "+",
        Operator::Subtract => "-",
        Operator::Multiply => "*",
        Operator::Not => "not",
        Operator::Even => "even?",
        Operator::Odd => "odd?",
        Operator::Zero => "zero?",
        Operator::Positive => "positive?",
        Operator::Negative => "negative?",
        Operator::And => "and",
        Operator::Or => "or",
        Operator::Identity => "identity",
    }
}
