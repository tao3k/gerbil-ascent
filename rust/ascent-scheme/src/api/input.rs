//! Convert typed arguments, keeping reference authority bound to its native owner.
use gerbil_ascent::{Data, ObjectInput, Result, Value};
fn tagged(kind: &str, value: Data) -> Data {
    Data::object([("type", Data::from(kind)), ("value", value)])
}
pub(super) fn arguments(values: &[ObjectInput], owner: u64) -> Result<Data> {
    values
        .iter()
        .map(|v| input(v, owner))
        .collect::<Result<Vec<_>>>()
        .map(Data::List)
}
pub(super) fn source_arguments(values: &[ObjectInput]) -> Result<Data> {
    values
        .iter()
        .map(source_input)
        .collect::<Result<Vec<_>>>()
        .map(Data::List)
}
fn source_input(value: &ObjectInput) -> Result<Data> {
    Ok(match value {
        ObjectInput::Reference(reference) => Data::object([
            ("type", Data::from("module-reference")),
            ("owner", Data::from(reference.owner)),
            ("result", Data::from(reference.result)),
            ("node", Data::from(reference.node)),
        ]),
        ObjectInput::List(values) => source_arguments(values)?,
        ObjectInput::Vector(values) => tagged("vector", source_arguments(values)?),
        ObjectInput::Pair(a, b) => Data::object([
            ("type", Data::from("pair")),
            ("car", source_input(a)?),
            ("cdr", source_input(b)?),
        ]),
        _ => input(value, 0)?,
    })
}
pub(super) fn input(value: &ObjectInput, owner: u64) -> Result<Data> {
    Ok(match value {
        ObjectInput::Integer(v) => Data::Integer(v.clone()),
        ObjectInput::Boolean(v) => Data::Bool(*v),
        ObjectInput::Text(v) => Data::from(v.clone()),
        ObjectInput::Symbol(v) => tagged("symbol", Data::from(v.clone())),
        ObjectInput::Number(v) => tagged("number", Data::from(v.clone())),
        ObjectInput::Rational(v) => tagged("number", Data::from(v.to_string())),
        ObjectInput::Inexact(v) => Data::Real(v.to_bits()),
        ObjectInput::Character(v) => tagged("character", Data::from(u64::from(u32::from(*v)))),
        ObjectInput::Bytes(v) => tagged(
            "u8vector",
            Data::List(v.iter().map(|v| Data::from(usize::from(*v))).collect()),
        ),
        ObjectInput::List(v) => arguments(v, owner)?,
        ObjectInput::Vector(v) => tagged("vector", arguments(v, owner)?),
        ObjectInput::Pair(a, b) => Data::object([
            ("type", Data::from("pair")),
            ("car", input(a, owner)?),
            ("cdr", input(b, owner)?),
        ]),
        ObjectInput::SourceReference {
            owner,
            generation,
            result,
            node,
        } => Data::object([
            ("type", Data::from("source-reference")),
            ("owner", Data::from(*owner)),
            ("generation", Data::from(*generation)),
            ("result", Data::from(*result)),
            ("node", Data::from(*node)),
        ]),
        ObjectInput::Reference(v) => {
            if v.owner != owner {
                return Err(crate::failure("foreign native value reference"));
            }
            Data::object([
                ("type", Data::from("reference")),
                ("result", Data::from(v.result)),
                ("node", Data::from(v.node)),
            ])
        }
        ObjectInput::Value(v) => scalar(v),
        ObjectInput::ResultValue(v) => scalar(&v.value()?),
    })
}
fn scalar(value: &Value) -> Data {
    match value {
        Value::Integer(v) => Data::Integer(v.clone()),
        Value::Boolean(v) => Data::Bool(*v),
        Value::Text(v) => tagged("string", Data::from(v.to_string())),
        Value::Symbol(v) => tagged("symbol", Data::from(v.to_string())),
        Value::Object(value) => value.native_input(),
    }
}
pub(super) fn owned(value: &ObjectInput, ty: gerbil_ascent::Type) -> Result<Value> {
    Ok(match value {
        ObjectInput::Integer(v) => Value::Integer(v.clone()),
        ObjectInput::Boolean(v) => Value::Boolean(*v),
        ObjectInput::Symbol(v) => Value::Symbol(v.as_str().into()),
        ObjectInput::Text(v)
            if matches!(
                ty,
                gerbil_ascent::Type::Symbol | gerbil_ascent::Type::Scalar
            ) =>
        {
            Value::Symbol(v.as_str().into())
        }
        ObjectInput::Text(v) => Value::Text(v.as_str().into()),
        ObjectInput::Rational(v) => Value::number(&v.to_string())?,
        ObjectInput::Number(v) => Value::number(v)?,
        ObjectInput::Inexact(v) => Value::inexact(*v)?,
        ObjectInput::Character(v) => freeze(gerbil_ascent::ObjectGraph {
            root: gerbil_ascent::GraphItem::Character(*v),
            nodes: std::sync::Arc::default(),
        })?,
        ObjectInput::Bytes(v) => freeze(gerbil_ascent::ObjectGraph {
            root: gerbil_ascent::GraphItem::Reference(1),
            nodes: std::collections::BTreeMap::from([(
                1,
                gerbil_ascent::ObjectNode::Bytes(v.clone()),
            )])
            .into(),
        })?,
        ObjectInput::List(values) => collection(values, false, None)?,
        ObjectInput::Vector(values) => collection(values, true, None)?,
        ObjectInput::Pair(a, b) => collection(&[*a.clone(), *b.clone()], false, Some(()))?,
        ObjectInput::Value(v) => v.clone(),
        ObjectInput::ResultValue(v) => v.value()?,
        _ => {
            return Err(crate::failure(
                "finite projection requires matching native scalar data",
            ));
        }
    })
}

fn freeze(graph: gerbil_ascent::ObjectGraph) -> Result<Value> {
    let identity = gerbil_ascent::allocate_source_identity()?;
    gerbil_ascent::FrozenValue::new(identity, identity, graph).map(Value::Object)
}
fn collection(values: &[ObjectInput], vector: bool, pair: Option<()>) -> Result<Value> {
    use gerbil_ascent::{GraphItem, ObjectNode, Row};
    let values = values
        .iter()
        .map(|v| owned(v, gerbil_ascent::Type::Any))
        .collect::<Result<Vec<_>>>()?;
    let mut graph = gerbil_ascent::rows_graph(&[Row::from(values)])?;
    let GraphItem::Reference(root) = graph.root else {
        return Err(crate::failure("owned collection root"));
    };
    let ObjectNode::Pair(row, _) = &graph.nodes[&root] else {
        return Err(crate::failure("owned collection row"));
    };
    let row = row.clone();
    if !vector && pair.is_none() {
        graph.root = row;
        return freeze(graph);
    }
    let mut cursor = row;
    let mut items = vec![];
    while let GraphItem::Reference(id) = cursor {
        let ObjectNode::Pair(car, cdr) = &graph.nodes[&id] else {
            return Err(crate::failure("owned collection shape"));
        };
        items.push(car.clone());
        cursor = cdr.clone();
    }
    let id = graph.nodes.keys().next_back().copied().unwrap_or(0) + 1;
    let node = if pair.is_some() {
        ObjectNode::Pair(items[0].clone(), items[1].clone())
    } else {
        ObjectNode::Vector(items)
    };
    std::sync::Arc::make_mut(&mut graph.nodes).insert(id, node);
    graph.root = GraphItem::Reference(id);
    freeze(graph)
}
