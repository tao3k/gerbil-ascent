//! Scalar admission and catalog field contracts.
use crate::{Data, Result, Type, Value, invalid_data as invalid};
pub(crate) fn shape(value: &Data, required: &[&str], optional: &[&str]) -> Result<()> {
    let fields = value.map()?;
    if required.iter().any(|k| !fields.contains_key(*k))
        || fields
            .keys()
            .any(|k| !required.contains(&k.as_str()) && !optional.contains(&k.as_str()))
    {
        return Err(invalid("catalog fields"));
    }
    Ok(())
}
pub(crate) fn scalar(value: &Data, ty: Type) -> Result<Value> {
    scalar_in(value, ty, &[])
}
pub(super) fn scalar_in(value: &Data, ty: Type, pool: &[Value]) -> Result<Value> {
    match value {
        Data::Integer(n) => Ok(Value::Integer(n.clone())),
        Data::Bool(v) => Ok(Value::Boolean(*v)),
        Data::Text(v) if matches!(ty, Type::Symbol | Type::Scalar) && v.len() <= 4096 => {
            Ok(Value::Symbol(v.as_str().into()))
        }
        Data::Text(v) => Ok(Value::Text(v.as_str().into())),
        Data::Map(_) => {
            shape(value, &["type", "value"], &[])?;
            let item = value.field("value")?;
            match value.field("type")?.text()? {
                "symbol" => Ok(Value::Symbol(item.text()?.into())),
                "string" => Ok(Value::Text(item.text()?.into())),
                "number" => Value::number(item.text()?),
                "pool" => pool
                    .get(item.index()?)
                    .cloned()
                    .ok_or_else(|| invalid("unknown owned value pool entry")),
                "graph" => {
                    let graph = crate::ObjectGraph::read_native(item)?;
                    crate::FrozenValue::new(0, 0, graph).map(Value::Object)
                }
                _ => Err(invalid("typed catalog scalar kind")),
            }
        }
        _ => Err(invalid("typed catalog scalar required")),
    }
}
