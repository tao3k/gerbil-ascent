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
        ObjectInput::Value(v) => scalar(v)?,
        ObjectInput::ResultValue(v) => scalar(&v.value()?)?,
    })
}
fn scalar(value: &Value) -> Result<Data> {
    Ok(match value {
        Value::Integer(v) => Data::Integer(v.clone()),
        Value::Boolean(v) => Data::Bool(*v),
        Value::Text(v) => Data::from(v.to_string()),
        Value::Symbol(v) => tagged("symbol", Data::from(v.to_string())),
        Value::Object(_) => {
            return Err(crate::failure(
                "native complex input requires its owning result reference",
            ));
        }
    })
}
pub(super) fn owned(value: &ObjectInput, ty: gerbil_ascent::Type) -> Result<Value> {
    Ok(match value {
        ObjectInput::Integer(v) => Value::Integer(v.clone()),
        ObjectInput::Boolean(v) => Value::Boolean(*v),
        ObjectInput::Symbol(v) => Value::Symbol(v.as_str().into()),
        ObjectInput::Text(v) if ty == gerbil_ascent::Type::Symbol => {
            Value::Symbol(v.as_str().into())
        }
        ObjectInput::Text(v) => Value::Text(v.as_str().into()),
        ObjectInput::Value(v) => v.clone(),
        ObjectInput::ResultValue(v) => v.value()?,
        _ => {
            return Err(crate::failure(
                "finite projection requires matching native scalar data",
            ));
        }
    })
}
