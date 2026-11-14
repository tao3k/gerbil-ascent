//! Map ASCENT's owned business data through upstream rooted Scheme types.
use crate::{failure, scheme_error};
use gerbil_ascent::{Data, Result};
use gerbil_scheme::{
    BigIntegerBuffer, BinaryInteger, CollectionKind, GerbilRuntime, NativeError, ObjectKind,
    RootedObjectBatch, RootedSchemeObject, SchemeObjectRef, SchemeScalar, TableEquality,
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
            // Let the upstream ABI decide its fixnum range; larger exact values
            // retain the arbitrary-precision transport. No word layout is copied.
            if let Ok(number) = isize::try_from(value) {
                match runtime.fixnum_value(number) {
                    Ok(value) => return runtime.root_value(value).map_err(scheme_error),
                    Err(NativeError::Status {
                        operation: "gerbil_scheme_rust_fixnum_from_word",
                        code,
                    }) if code == gerbil_scheme_sys::GerbilStatus::InvalidValue as i32 => {}
                    Err(error) => return Err(scheme_error(error)),
                }
            }
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
    let kind = value.as_ref().kind().map_err(scheme_error)?;
    if let Some(decoded) = decode_leaf(value.as_ref(), kind)? {
        return Ok(decoded);
    }
    match kind {
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
                .map(|index| decode_element(&snapshot, index, depth + 1))
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
                let key = decode_element(&snapshot, index, depth + 1)?;
                let item = decode_element(&snapshot, index + 1, depth + 1)?;
                values.insert(key.text()?.into(), item);
            }
            Ok(Data::Map(values))
        }
        _ => Err(failure("unsupported native application result")),
    }
}

fn decode_leaf(value: SchemeObjectRef<'_>, kind: ObjectKind) -> Result<Option<Data>> {
    let decoded = match kind {
        ObjectKind::Void => Ok(Data::Null),
        ObjectKind::Nil => Ok(Data::List(Vec::new())),
        ObjectKind::Boolean | ObjectKind::Flonum => match value.scalar().map_err(scheme_error)? {
            SchemeScalar::Boolean(value) => Ok(Data::Bool(value)),
            SchemeScalar::Flonum(value) => Ok(Data::Real(value.to_bits())),
            _ => Err(failure("native scalar projection")),
        },
        ObjectKind::ExactInteger => {
            let mut output = BigIntegerBuffer::default();
            value.copy_big_integer(&mut output).map_err(scheme_error)?;
            Ok(Data::Integer(BigInt::from_bytes_le(
                if output.value().is_negative() {
                    Sign::Minus
                } else {
                    Sign::Plus
                },
                output.value().magnitude(),
            )))
        }
        _ => return Ok(None),
    }?;
    Ok(Some(decoded))
}

fn decode_element(snapshot: &RootedObjectBatch<'_>, index: usize, depth: usize) -> Result<Data> {
    if depth > 256 {
        return Err(failure("native result nesting bound"));
    }
    let value = snapshot
        .get(index)
        .ok_or_else(|| failure("native snapshot index"))?;
    let kind = value.kind().map_err(scheme_error)?;
    if let Some(value) = decode_leaf(value, kind)? {
        return Ok(value);
    }
    // Complex children need their own recursive root; scalar children borrow
    // the snapshot's existing root, exactly as the upstream API recommends.
    decode(snapshot.root_element(index).map_err(scheme_error)?, depth)
}
