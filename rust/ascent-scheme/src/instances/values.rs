//! Business data adapters over upstream owner-local roots and native conversions.
use super::bridge_error;
use gerbil_ascent::{Data, Result};
use gerbil_scheme::{
    BinaryInteger, ObjectKind, SchemeScalar,
    instances::{NativeRoot, NativeSession},
};
use num_bigint::{BigInt, Sign};
use std::collections::BTreeMap;

pub(super) fn encode<'v>(vm: &NativeSession<'v>, data: &Data) -> Result<NativeRoot<'v>> {
    match data {
        Data::Null => vm.void_object().map_err(bridge_error),
        Data::Bool(v) => vm.scalar(SchemeScalar::Boolean(*v)).map_err(bridge_error),
        Data::Real(v) => vm
            .scalar(SchemeScalar::Flonum(f64::from_bits(*v)))
            .map_err(bridge_error),
        Data::Integer(v) => {
            let (sign, mut bytes) = v.to_bytes_le();
            if sign == Sign::NoSign {
                bytes.clear();
            }
            let integer =
                BinaryInteger::new(sign == Sign::Minus, bytes).map_err(crate::scheme_error)?;
            vm.big_integer(&integer).map_err(bridge_error)
        }
        Data::Text(v) => vm.string(v).map_err(bridge_error),
        Data::List(v) => {
            let children = v
                .iter()
                .map(|v| encode(vm, v))
                .collect::<Result<Vec<_>>>()?;
            vm.list(&children.iter().collect::<Vec<_>>())
                .map_err(bridge_error)
        }
        Data::Map(v) => {
            let mut children = Vec::with_capacity(v.len() * 2);
            for (key, value) in v {
                children.push(vm.string(key).map_err(bridge_error)?);
                children.push(encode(vm, value)?);
            }
            let entries = vm
                .vector(&children.iter().collect::<Vec<_>>())
                .map_err(bridge_error)?;
            // This build-owned rooted export selects the existing Gerbil hash
            // type. Upstream NativeSession::table constructs a Gambit table.
            vm.call_export(c"ascent_hybrid_table", &entries)
                .map_err(bridge_error)
        }
    }
}
pub(super) fn decode(vm: &NativeSession<'_>, value: &NativeRoot<'_>, depth: usize) -> Result<Data> {
    if depth > 256 {
        return Err(crate::failure("native result nesting bound"));
    }
    match vm.kind(value).map_err(bridge_error)? {
        ObjectKind::Void => Ok(Data::Null),
        ObjectKind::Nil => Ok(Data::List(Vec::new())),
        ObjectKind::Boolean | ObjectKind::Flonum => {
            match vm.copy_scalar(value).map_err(bridge_error)? {
                SchemeScalar::Boolean(v) => Ok(Data::Bool(v)),
                SchemeScalar::Flonum(v) => Ok(Data::Real(v.to_bits())),
                _ => Err(crate::failure("native scalar projection")),
            }
        }
        ObjectKind::ExactInteger => {
            let v = vm.copy_big_integer(value).map_err(bridge_error)?;
            Ok(Data::Integer(BigInt::from_bytes_le(
                if v.is_negative() {
                    Sign::Minus
                } else {
                    Sign::Plus
                },
                v.magnitude(),
            )))
        }
        ObjectKind::String => vm.copy_string(value).map(Data::Text).map_err(bridge_error),
        ObjectKind::Pair | ObjectKind::Vector => vm
            .elements(value)
            .map_err(bridge_error)?
            .iter()
            .map(|v| decode(vm, v, depth + 1))
            .collect::<Result<Vec<_>>>()
            .map(Data::List),
        ObjectKind::GerbilHashTable | ObjectKind::GambitTable => {
            let entries = vm.elements(value).map_err(bridge_error)?;
            if entries.len() % 2 != 0 {
                return Err(crate::failure("native table entries arity"));
            }
            let mut out = BTreeMap::new();
            for pair in entries.as_chunks::<2>().0 {
                let key = decode(vm, &pair[0], depth + 1)?;
                out.insert(key.text()?.to_owned(), decode(vm, &pair[1], depth + 1)?);
            }
            Ok(Data::Map(out))
        }
        _ => Err(crate::failure("unsupported native application result")),
    }
}
pub(super) fn call(vm: &NativeSession<'_>, request: &Data) -> Result<Data> {
    let request = encode(vm, request)?;
    let response = vm.call(&request).map_err(bridge_error)?;
    crate::application::decode_response(decode(vm, &response, 0)?)
}
