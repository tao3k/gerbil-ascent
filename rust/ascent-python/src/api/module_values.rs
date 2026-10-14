//! Typed Python argument and identity-preserving observation boundary.
use super::{
    types::source_error,
    types::{EngineError, OwnedValue, ResultValue, Symbol},
};
use gerbil_ascent::{GraphItem, ObjectGraph, ObjectInput as Input, ObjectNode, ValueReference};
use pyo3::{
    Bound, PyAny, PyRef, PyResult, Python,
    types::{
        PyAnyMethods, PyBool, PyDict, PyDictMethods, PyFloat, PyInt, PyList, PyListMethods,
        PyString, PyTuple, PyTupleMethods,
    },
};
fn invalid(message: &str) -> pyo3::PyErr {
    EngineError::new_err(message.to_owned())
}
pub(super) fn arguments(args: &Bound<'_, PyTuple>) -> PyResult<Vec<Input>> {
    args.iter()
        .map(|v| input(&v, 0))
        .collect::<PyResult<_>>()
        .map_err(|error| invalid(&error.to_string()))
}
pub(super) fn input(value: &Bound<'_, PyAny>, depth: usize) -> PyResult<Input> {
    if depth > 128 {
        return Err(invalid("argument nesting bound"));
    }
    if let Ok(value) = value.extract::<PyRef<'_, ResultValue>>() {
        return match &value.0 {
            super::types::CellValue::Core(v) => Ok(Input::ResultValue(v.clone())),
            super::types::CellValue::Scheme(v) => v.input().map_err(source_error),
        };
    }
    if let Ok(value) = value.extract::<PyRef<'_, OwnedValue>>() {
        return value
            .0
            .reference(None)
            .map(Input::Reference)
            .map_err(source_error);
    }
    if value.is_instance_of::<PyBool>() {
        return Ok(Input::Boolean(value.extract()?));
    }
    if value.is_instance_of::<PyInt>() {
        return Ok(Input::Integer(value.extract()?));
    }
    if value.is_instance_of::<PyFloat>() {
        return Ok(Input::Inexact(value.extract()?));
    }
    if value.is_instance_of::<PyString>() {
        return Ok(Input::Text(value.extract()?));
    }
    if let Ok(symbol) = value.extract::<PyRef<'_, Symbol>>() {
        return Ok(Input::Symbol(symbol.name.clone()));
    }
    if let Ok(items) = value.cast::<PyList>() {
        return Ok(Input::List(
            items
                .iter()
                .map(|v| input(&v, depth + 1))
                .collect::<PyResult<_>>()?,
        ));
    }
    let dict = value
        .cast::<PyDict>()
        .map_err(|_| invalid("unsupported Scheme argument"))?;
    let field = |key: &str| {
        dict.get_item(key)?
            .ok_or_else(|| invalid("missing tagged value field"))
    };
    let kind: String = field("type")?.extract()?;
    match kind.as_str() {
        "symbol" => Ok(Input::Symbol(field("value")?.extract()?)),
        "number" => Ok(Input::Number(field("value")?.extract()?)),
        "character" => {
            let value = field("value")?;
            exact_integer(&value)?;
            let code: u32 = value.extract()?;
            Ok(Input::Character(
                char::from_u32(code).ok_or_else(|| invalid("invalid character codepoint"))?,
            ))
        }
        "vector" => {
            let items = field("value")?;
            let items = items.cast::<PyList>()?;
            Ok(Input::Vector(
                items
                    .iter()
                    .map(|v| input(&v, depth + 1))
                    .collect::<PyResult<_>>()?,
            ))
        }
        "u8vector" => {
            let values = field("value")?;
            let values = values.cast::<PyList>()?;
            Ok(Input::Bytes(
                values
                    .iter()
                    .map(|v| {
                        exact_integer(&v)?;
                        v.extract()
                    })
                    .collect::<PyResult<_>>()?,
            ))
        }
        "pair" => Ok(Input::Pair(
            Box::new(input(&field("car")?, depth + 1)?),
            Box::new(input(&field("cdr")?, depth + 1)?),
        )),
        "reference" => Ok(Input::Reference(ValueReference {
            owner: field("owner")?.extract()?,
            result: field("result")?.extract()?,
            node: field("node")?.extract()?,
        })),
        _ => Err(invalid("unsupported tagged Scheme value")),
    }
}
fn tagged<'py>(py: Python<'py>, kind: &str) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    out.set_item("type", kind)?;
    Ok(out)
}
fn item<'py>(py: Python<'py>, value: &GraphItem) -> PyResult<Bound<'py, PyDict>> {
    let out = match value {
        GraphItem::Reference(id) => {
            let out = PyDict::new(py);
            out.set_item("ref", id)?;
            out
        }
        GraphItem::Null => tagged(py, "null")?,
        GraphItem::Void => tagged(py, "void")?,
        GraphItem::Boolean(value) => {
            let out = tagged(py, "boolean")?;
            out.set_item("value", value)?;
            out
        }
        GraphItem::Number(value) => {
            let out = tagged(py, "number")?;
            out.set_item("value", value)?;
            out
        }
        GraphItem::Character(value) => {
            let out = tagged(py, "character")?;
            out.set_item("value", u32::from(*value))?;
            out
        }
    };
    Ok(out)
}
pub(super) fn graph<'py>(py: Python<'py>, graph: &ObjectGraph) -> PyResult<Bound<'py, PyDict>> {
    let out = PyDict::new(py);
    out.set_item("format", "native-value-graph.v1")?;
    out.set_item("root", item(py, &graph.root)?)?;
    let nodes = PyList::empty(py);
    for (id, node) in &graph.nodes {
        let out = match node {
            ObjectNode::Text(value) => {
                let out = tagged(py, "string")?;
                out.set_item("value", value)?;
                out
            }
            ObjectNode::Symbol { name, interned } => {
                let out = tagged(py, "symbol")?;
                out.set_item("value", name)?;
                out.set_item("interned", interned)?;
                out
            }
            ObjectNode::Pair(car, cdr) => {
                let out = tagged(py, "pair")?;
                out.set_item("car", item(py, car)?)?;
                out.set_item("cdr", item(py, cdr)?)?;
                out
            }
            ObjectNode::Vector(items) => {
                let out = tagged(py, "vector")?;
                out.set_item(
                    "items",
                    items
                        .iter()
                        .map(|v| item(py, v))
                        .collect::<PyResult<Vec<_>>>()?,
                )?;
                out
            }
            ObjectNode::Bytes(items) => {
                let out = tagged(py, "u8vector")?;
                out.set_item("items", PyList::new(py, items)?)?;
                out
            }
            ObjectNode::Table(entries) => {
                let out = tagged(py, "hash-table")?;
                out.set_item(
                    "entries",
                    entries
                        .iter()
                        .map(|(a, b)| Ok(vec![item(py, a)?, item(py, b)?]))
                        .collect::<PyResult<Vec<_>>>()?,
                )?;
                out
            }
            ObjectNode::Opaque(kind) => {
                let out = tagged(py, "opaque")?;
                out.set_item("encoding", "native-reference-only")?;
                out.set_item("kind", kind)?;
                out
            }
        };
        out.set_item("id", id)?;
        nodes.append(out)?;
    }
    out.set_item("nodes", nodes)?;
    Ok(out)
}
pub(super) fn reference(
    py: Python<'_>,
    value: Result<ValueReference, gerbil_ascent::Error>,
) -> PyResult<Bound<'_, PyDict>> {
    let value = value.map_err(source_error)?;
    let out = tagged(py, "reference")?;
    out.set_item("owner", value.owner)?;
    out.set_item("result", value.result)?;
    out.set_item("node", value.node)?;
    Ok(out)
}

fn exact_integer(value: &Bound<'_, PyAny>) -> PyResult<()> {
    if value.is_instance_of::<PyBool>() || !value.is_instance_of::<PyInt>() {
        return Err(invalid("exact integer required"));
    }
    Ok(())
}
