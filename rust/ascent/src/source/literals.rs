//! Structured datum constants use the existing immutable object graph types.
use super::{
    lowering::name,
    reader::{Datum, invalid},
};
use crate::{FrozenValue, GraphItem, ObjectGraph, ObjectNode, Result, Value};
use std::collections::BTreeMap;

/// Explicit graph data retains sharing, cycles and opaque identity without host code.
pub(super) fn graph(form: &[Datum]) -> Result<Value> {
    use super::lowering::list;
    fn id(d: &Datum) -> Result<usize> {
        name(d)?
            .parse()
            .map_err(|_| invalid("graph node ID required"))
    }
    fn edge(d: &Datum) -> Result<GraphItem> {
        match d {
            Datum::List(v) if v.is_empty() => Ok(GraphItem::Null),
            Datum::List(v) if matches!(v.first(), Some(Datum::Atom(s)) if s == "ref") => {
                let [_, target] = v.as_slice() else {
                    return Err(invalid("graph ref arity"));
                };
                Ok(GraphItem::Reference(id(target)?))
            }
            Datum::List(v) if matches!(v.first(), Some(Datum::Atom(s)) if s == "character") => {
                let [_, value] = v.as_slice() else {
                    return Err(invalid("graph character arity"));
                };
                let code = name(value)?
                    .parse::<u32>()
                    .map_err(|_| invalid("Unicode scalar required"))?;
                char::from_u32(code)
                    .map(GraphItem::Character)
                    .ok_or_else(|| invalid("Unicode scalar required"))
            }
            Datum::Atom(s) if s == "#t" => Ok(GraphItem::Boolean(true)),
            Datum::Atom(s) if s == "#f" => Ok(GraphItem::Boolean(false)),
            Datum::Atom(s) if crate::numbers::parse_number(s).is_some() => {
                Ok(GraphItem::Number(s.clone()))
            }
            _ => Err(invalid("graph scalar or reference required")),
        }
    }
    let [_, root, declarations] = form else {
        return Err(invalid("object-graph root/nodes required"));
    };
    let mut nodes = BTreeMap::new();
    for declaration in list(declarations)? {
        if nodes.len() >= 65_536 {
            return Err(invalid("structured literal node bound"));
        }
        let [key, kind, fields @ ..] = list(declaration)? else {
            return Err(invalid("graph node shape"));
        };
        let node = match (name(kind)?, fields) {
            ("vector", values) => {
                ObjectNode::Vector(values.iter().map(edge).collect::<Result<_>>()?)
            }
            ("u8vector", values) => ObjectNode::Bytes(
                values
                    .iter()
                    .map(|value| {
                        name(value)?
                            .parse::<u8>()
                            .map_err(|_| invalid("byte in 0..255 required"))
                    })
                    .collect::<Result<_>>()?,
            ),
            ("pair", [a, b]) => ObjectNode::Pair(edge(a)?, edge(b)?),
            ("table", entries) => ObjectNode::Table(
                entries
                    .iter()
                    .map(|entry| {
                        let [a, b] = list(entry)? else {
                            return Err(invalid("graph table entry"));
                        };
                        Ok((edge(a)?, edge(b)?))
                    })
                    .collect::<Result<_>>()?,
            ),
            ("opaque", [Datum::Text(label)]) => ObjectNode::Opaque(label.clone()),
            ("text", [Datum::Text(text)]) => ObjectNode::Text(text.clone()),
            ("symbol", [Datum::Text(label), Datum::Atom(interned)])
                if matches!(interned.as_str(), "#t" | "#f") =>
            {
                ObjectNode::Symbol {
                    name: label.clone(),
                    interned: interned == "#t",
                }
            }
            _ => return Err(invalid("unsupported graph node kind/fields")),
        };
        if nodes.insert(id(key)?, node).is_some() {
            return Err(invalid("duplicate graph node ID"));
        }
    }
    let identity = crate::allocate_source_identity()?;
    Ok(Value::Object(FrozenValue::new(
        identity,
        identity,
        ObjectGraph {
            root: edge(root)?,
            nodes: nodes.into(),
        },
    )?))
}

pub(super) fn freeze(datum: &Datum) -> Result<Value> {
    let mut nodes = BTreeMap::new();
    let root = item(datum, &mut nodes)?;
    let identity = crate::allocate_source_identity()?;
    Ok(Value::Object(FrozenValue::new(
        identity,
        identity,
        ObjectGraph {
            root,
            nodes: nodes.into(),
        },
    )?))
}
fn allocate(node: ObjectNode, nodes: &mut BTreeMap<usize, ObjectNode>) -> Result<GraphItem> {
    if nodes.len() >= 65_536 {
        return Err(invalid("structured literal node bound"));
    }
    let id = nodes.len();
    nodes.insert(id, node);
    Ok(GraphItem::Reference(id))
}
fn item(datum: &Datum, nodes: &mut BTreeMap<usize, ObjectNode>) -> Result<GraphItem> {
    match datum {
        Datum::Atom(s) if s == "#t" => Ok(GraphItem::Boolean(true)),
        Datum::Atom(s) if s == "#f" => Ok(GraphItem::Boolean(false)),
        Datum::Atom(s) if crate::numbers::parse_number(s).is_some() => {
            Ok(GraphItem::Number(s.clone()))
        }
        Datum::Atom(s) => {
            name(datum)?;
            allocate(
                ObjectNode::Symbol {
                    name: s.clone(),
                    interned: true,
                },
                nodes,
            )
        }
        Datum::Text(s) => allocate(ObjectNode::Text(s.clone()), nodes),
        Datum::Vector(values) => {
            let values = values
                .iter()
                .map(|v| item(v, nodes))
                .collect::<Result<_>>()?;
            allocate(ObjectNode::Vector(values), nodes)
        }
        Datum::List(values) => {
            let mut tail = GraphItem::Null;
            for value in values.iter().rev() {
                let head = item(value, nodes)?;
                tail = allocate(ObjectNode::Pair(head, tail), nodes)?;
            }
            Ok(tail)
        }
    }
}
