//! Map ASCENT's owned business data through upstream rooted Scheme types.
use crate::{failure, scheme_error};
use gerbil_ascent::{Data, Result};
use gerbil_scheme::{
    BigIntegerBuffer, BinaryInteger, CollectionKind, GerbilRuntime, NativeError, NumericBuffer,
    ObjectKind, RootedObjectBatch, RootedSchemeObject, SchemeObjectRef, SchemeScalar,
    TableEquality,
};
use num_bigint::{BigInt, Sign};
use std::collections::BTreeMap;

pub(super) type Root<'r> = RootedSchemeObject<'r>;

pub(super) fn encode<'r>(runtime: &'r GerbilRuntime, value: &Data) -> Result<Root<'r>> {
    encode_shaped(runtime, value, InputShape::Ordinary)
}

pub(super) fn encode_source_request<'r>(
    runtime: &'r GerbilRuntime,
    value: &Data,
) -> Result<Root<'r>> {
    encode_shaped(runtime, value, InputShape::SourceRequest)
}

#[derive(Clone, Copy)]
enum InputShape {
    Ordinary,
    SourceRequest,
    SourceGroups,
    SourceUpdate,
    SourceRows,
}

fn encode_shaped<'r>(
    runtime: &'r GerbilRuntime,
    value: &Data,
    shape: InputShape,
) -> Result<Root<'r>> {
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
            if let InputShape::SourceRows = shape
                && let Some(packet) = integer_source_packet(values)
            {
                return runtime.numeric_vector(&packet).map_err(scheme_error);
            }
            let child = match shape {
                InputShape::SourceGroups => InputShape::SourceUpdate,
                _ => InputShape::Ordinary,
            };
            let values = values
                .iter()
                .map(|value| encode_shaped(runtime, value, child))
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
                        encode_shaped(
                            runtime,
                            value,
                            match (shape, key.as_str()) {
                                (InputShape::SourceRequest, "sources") => InputShape::SourceGroups,
                                (InputShape::SourceUpdate, "rows") => InputShape::SourceRows,
                                _ => InputShape::Ordinary,
                            },
                        )?,
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
fn integer_source_packet(rows: &[Data]) -> Option<Vec<i64>> {
    let width = rows.first()?.list().ok()?.len();
    if width == 0 {
        return None;
    }
    let size = rows.len().checked_mul(width)?.checked_add(2)?;
    let mut packet = Vec::new();
    packet.try_reserve_exact(size).ok()?;
    packet.extend([i64::try_from(rows.len()).ok()?, i64::try_from(width).ok()?]);
    for row in rows {
        let cells = row.list().ok()?;
        if cells.len() != width {
            return None;
        }
        for cell in cells {
            let Data::Integer(value) = cell else {
                return None;
            };
            packet.push(i64::try_from(value).ok()?);
        }
    }
    Some(packet)
}

// BEGIN GENERATED PROJECTION ROW SHAPES
#[derive(Clone, Copy)]
enum ReplyShape {
    Ordinary,
    SourceEnvelope,
    SourceResult,
    Relations,
    RowSet,
    Program,
    ProgramRelations,
    ProgramRelation,
}

impl ReplyShape {
    fn element_child(self, index: usize) -> Self {
        match (self, index) {
            (Self::SourceEnvelope, 1) => Self::SourceResult,
            (Self::ProgramRelations, _) => Self::ProgramRelation,
            _ => Self::Ordinary,
        }
    }

    fn field_child(self, key: &str) -> Self {
        match (self, key) {
            (Self::SourceResult, "relations") => Self::Relations,
            (Self::SourceResult, "program") => Self::Program,
            (Self::Relations, _) | (Self::ProgramRelation, "rows") => Self::RowSet,
            (Self::Program, "relations") => Self::ProgramRelations,
            _ => Self::Ordinary,
        }
    }
}
// END GENERATED PROJECTION ROW SHAPES

pub(super) fn decode(value: Root<'_>, packed_rows: bool) -> Result<Data> {
    let shape = if packed_rows {
        ReplyShape::SourceEnvelope
    } else {
        ReplyShape::Ordinary
    };
    let kind = value.as_ref().kind().map_err(scheme_error)?;
    if let Some(decoded) = decode_leaf(value.as_ref(), kind, shape)? {
        return Ok(decoded);
    }
    decode_object(value, kind, 0, shape)
}

fn decode_object(
    value: Root<'_>,
    kind: ObjectKind,
    depth: usize,
    shape: ReplyShape,
) -> Result<Data> {
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
                .map(|index| {
                    let child = shape.element_child(index);
                    decode_element(&snapshot, index, depth + 1, child)
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
                let key = decode_element(&snapshot, index, depth + 1, ReplyShape::Ordinary)?;
                let child = shape.field_child(key.text()?);
                let item = decode_element(&snapshot, index + 1, depth + 1, child)?;
                values.insert(key.text()?.into(), item);
            }
            Ok(Data::Map(values))
        }
        _ => Err(failure("unsupported native application result")),
    }
}

fn decode_leaf(
    value: SchemeObjectRef<'_>,
    kind: ObjectKind,
    shape: ReplyShape,
) -> Result<Option<Data>> {
    let decoded = match kind {
        ObjectKind::Void => Ok(Data::Null),
        ObjectKind::Nil => Ok(Data::List(Vec::new())),
        ObjectKind::Boolean | ObjectKind::Flonum => match value.scalar().map_err(scheme_error)? {
            SchemeScalar::Boolean(value) => Ok(Data::Bool(value)),
            SchemeScalar::Flonum(value) => Ok(Data::Real(value.to_bits())),
            _ => Err(failure("native scalar projection")),
        },
        ObjectKind::ExactInteger => decode_integer(value),
        ObjectKind::Other if matches!(shape, ReplyShape::RowSet) => {
            let mut packet = NumericBuffer::<i64>::default();
            value.copy_numeric(&mut packet).map_err(scheme_error)?;
            decode_integer_rows(packet.as_slice())
        }
        _ => return Ok(None),
    }?;
    Ok(Some(decoded))
}

pub(super) fn decode_integer_rows(packet: &[i64]) -> Result<Data> {
    let invalid = || failure("invalid native integer rows");
    let [count, width, cells @ ..] = packet else {
        return Err(invalid());
    };
    let count = usize::try_from(*count).map_err(|_| invalid())?;
    let width = usize::try_from(*width).map_err(|_| invalid())?;
    if count == 0 || width == 0 || count.checked_mul(width) != Some(cells.len()) {
        return Err(invalid());
    }
    Ok(Data::List(
        cells
            .chunks_exact(width)
            .map(|row| Data::List(row.iter().map(|&cell| Data::Integer(cell.into())).collect()))
            .collect(),
    ))
}

fn decode_integer(value: SchemeObjectRef<'_>) -> Result<Data> {
    match value.scalar() {
        Ok(SchemeScalar::Fixnum(word)) => return Ok(Data::Integer(word.into())),
        Err(NativeError::Status {
            operation: "object scalar",
            code,
        }) if code == gerbil_scheme_sys::GerbilStatus::InvalidValue as i32 => {}
        Err(error) => return Err(scheme_error(error)),
        Ok(_) => return Err(failure("native exact integer projection")),
    }
    // Rooted exact integers outside the bridge's fixnum range retain the
    // arbitrary-precision signed magnitude transfer.
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

fn decode_element(
    snapshot: &RootedObjectBatch<'_>,
    index: usize,
    depth: usize,
    shape: ReplyShape,
) -> Result<Data> {
    if depth > 256 {
        return Err(failure("native result nesting bound"));
    }
    let value = snapshot
        .get(index)
        .ok_or_else(|| failure("native snapshot index"))?;
    let kind = value.kind().map_err(scheme_error)?;
    if let Some(value) = decode_leaf(value, kind, shape)? {
        return Ok(value);
    }
    // Promotion retains the same object. Reuse the kind observed on the
    // snapshot slot and let the owned decoder manage the new root.
    decode_object(
        snapshot.root_element(index).map_err(scheme_error)?,
        kind,
        depth,
        shape,
    )
}
