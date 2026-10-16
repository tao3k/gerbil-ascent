//! ASCENT packet mapping; the upstream bridge owns C layout and allocation.
use gerbil_ascent::{Data, Error, Result};
use gerbil_scheme_python::OwnedValue;

pub(super) fn read(value: OwnedValue) -> Result<Data> {
    Ok(match value {
        OwnedValue::Null => Data::Null,
        OwnedValue::Boolean(v) => Data::Bool(v),
        OwnedValue::Integer(v) => Data::Integer(v),
        OwnedValue::Real(v) => Data::Real(v.to_bits()),
        OwnedValue::Text(v) => Data::Text(v),
        OwnedValue::List(v) => Data::List(v.into_iter().map(read).collect::<Result<_>>()?),
        OwnedValue::Map(v) => Data::Map(
            v.into_iter()
                .map(|(k, v)| Ok((k, read(v)?)))
                .collect::<Result<_>>()?,
        ),
        OwnedValue::Bytes(_) => {
            return Err(Error::InvalidUpdate(
                "bytes require an explicit graph value".into(),
            ));
        }
    })
}
pub(super) fn write(value: &Data) -> OwnedValue {
    match value {
        Data::Null => OwnedValue::Null,
        Data::Bool(v) => OwnedValue::Boolean(*v),
        Data::Integer(v) => OwnedValue::Integer(v.clone()),
        Data::Real(v) => OwnedValue::Real(f64::from_bits(*v)),
        Data::Text(v) => OwnedValue::Text(v.clone()),
        Data::List(v) => OwnedValue::List(v.iter().map(write).collect()),
        Data::Map(v) => OwnedValue::Map(v.iter().map(|(k, v)| (k.clone(), write(v))).collect()),
    }
}
