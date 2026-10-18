//! Map ASCENT's owned business data through upstream rooted Scheme types.
use crate::{failure, scheme_error};
use gerbil_ascent::{Data, Result};
use gerbil_scheme::{
    BigIntegerBuffer, BinaryInteger, CollectionKind, GerbilRuntime, ObjectKind, RootedObjectBatch,
    RootedSchemeObject, SchemeScalar, TableEquality,
};
use num_bigint::{BigInt, Sign};
use std::collections::BTreeMap;

pub(super) type Root<'r> = RootedSchemeObject<'r>;
pub(super) fn encode<'r>(runtime: &'r GerbilRuntime, value: &Data) -> Result<Root<'r>> {
    match value {
        Data::Null => runtime.void_object().map_err(scheme_error),
        Data::Bool(value) => runtime
            .scalar_object(SchemeScalar::Boolean(*value))
            .map_err(scheme_error),
        Data::Real(value) => runtime
            .scalar_object(SchemeScalar::Flonum(f64::from_bits(*value)))
            .map_err(scheme_error),
        Data::Integer(value) => {
            let (sign, mut bytes) = value.to_bytes_le();
            if sign == Sign::NoSign {
                bytes.clear();
            }
            let integer = BinaryInteger::new(sign == Sign::Minus, bytes).map_err(scheme_error)?;
            runtime.big_integer(&integer).map_err(scheme_error)
        }
        Data::Text(value) => runtime
            .string_from_utf8(value)
            .map(gerbil_scheme::RootedSchemeString::into_object)
            .map_err(scheme_error),
        Data::List(values) => {
            let values = values
                .iter()
                .map(|value| encode(runtime, value))
                .collect::<Result<Vec<_>>>()?;
            runtime
                .collection_from_objects(CollectionKind::List, &values.iter().collect::<Vec<_>>())
                .map(gerbil_scheme::RootedSchemeCollection::into_object)
                .map_err(scheme_error)
        }
        Data::Map(values) => {
            let entries = values
                .iter()
                .map(|(key, value)| {
                    Ok((
                        runtime
                            .string_from_utf8(key)
                            .map_err(scheme_error)?
                            .into_object(),
                        encode(runtime, value)?,
                    ))
                })
                .collect::<Result<Vec<_>>>()?;
            runtime
                .gerbil_hash_table(
                    TableEquality::Structural,
                    &entries
                        .iter()
                        .map(|(key, value)| (key, value))
                        .collect::<Vec<_>>(),
                )
                .map_err(scheme_error)
        }
    }
}
pub(super) fn decode(value: Root<'_>, depth: usize) -> Result<Data> {
    if depth > 256 {
        return Err(failure("native result nesting bound"));
    }
    match value.as_ref().kind().map_err(scheme_error)? {
        ObjectKind::Void => Ok(Data::Null),
        ObjectKind::Nil => Ok(Data::List(Vec::new())),
        ObjectKind::Boolean | ObjectKind::Flonum => {
            match value.as_ref().scalar().map_err(scheme_error)? {
                SchemeScalar::Boolean(value) => Ok(Data::Bool(value)),
                SchemeScalar::Flonum(value) => Ok(Data::Real(value.to_bits())),
                _ => Err(failure("native scalar projection")),
            }
        }
        ObjectKind::ExactInteger => {
            let mut output = BigIntegerBuffer::default();
            value
                .as_ref()
                .copy_big_integer(&mut output)
                .map_err(scheme_error)?;
            Ok(Data::Integer(BigInt::from_bytes_le(
                if output.value().is_negative() {
                    Sign::Minus
                } else {
                    Sign::Plus
                },
                output.value().magnitude(),
            )))
        }
        ObjectKind::String => value
            .into_string()
            .map_err(scheme_error)?
            .to_string()
            .into_result()
            .map(Data::Text)
            .map_err(scheme_error),
        kind @ (ObjectKind::Pair | ObjectKind::Vector) => {
            let kind = if kind == ObjectKind::Vector {
                CollectionKind::Vector
            } else {
                CollectionKind::List
            };
            let collection = value.into_collection(kind).map_err(scheme_error)?;
            let mut snapshot = RootedObjectBatch::default();
            collection.copy_into(&mut snapshot).map_err(scheme_error)?;
            let values = (0..snapshot.len())
                .map(|index| {
                    decode(
                        snapshot.root_element(index).map_err(scheme_error)?,
                        depth + 1,
                    )
                })
                .collect::<Result<Vec<_>>>()?;
            Ok(Data::List(values))
        }
        ObjectKind::GerbilHashTable | ObjectKind::GambitTable => {
            let mut snapshot = RootedObjectBatch::default();
            value
                .copy_table_entries(&mut snapshot)
                .map_err(scheme_error)?;
            let mut values = BTreeMap::new();
            for index in (0..snapshot.len()).step_by(2) {
                let key = decode(
                    snapshot.root_element(index).map_err(scheme_error)?,
                    depth + 1,
                )?;
                let item = decode(
                    snapshot.root_element(index + 1).map_err(scheme_error)?,
                    depth + 1,
                )?;
                values.insert(key.text()?.into(), item);
            }
            Ok(Data::Map(values))
        }
        _ => Err(failure("unsupported native application result")),
    }
}
