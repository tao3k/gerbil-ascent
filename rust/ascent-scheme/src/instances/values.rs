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
// These owner-local counters are diagnostic only. They do not report cumulative
// allocation and are never enabled for admitted throughput measurements.
fn observe<T>(
    vm: &NativeSession<'_>,
    operation: &str,
    phase: &str,
    action: impl FnOnce() -> Result<T>,
) -> Result<T> {
    let before = vm.diagnostics();
    let started = std::time::Instant::now();
    let result = action();
    let elapsed = started.elapsed().as_micros();
    if let Some((before, after)) = before.zip(vm.diagnostics()) {
        crate::diagnostics::emit(format!(
            "ASCENT-INSTANCE-PHASE pid={} owner={} operation={operation} phase={phase} elapsed_us={elapsed} success={} gc_user_us={} gc_system_us={} gc_real_us={} owner_cpu_us={} roots_before={} roots_after={} gc_count={}",
            std::process::id(),
            vm.owner_index(),
            result.is_ok(),
            (after[0] - before[0]) * 1e6,
            (after[1] - before[1]) * 1e6,
            (after[2] - before[2]) * 1e6,
            (after[3] - before[3]) * 1e6,
            before[4],
            after[4],
            after[5] - before[5],
        ));
    } else {
        crate::diagnostics::emit(format!(
            "ASCENT-INSTANCE-PHASE pid={} owner={} operation={operation} phase={phase} elapsed_us={elapsed} success={} usage=unavailable",
            std::process::id(),
            vm.owner_index(),
            result.is_ok(),
        ));
    }
    result
}
pub(super) fn call(vm: &NativeSession<'_>, request: &Data) -> Result<Data> {
    if !crate::diagnostics::enabled() {
        let request = encode(vm, request)?;
        let response = vm.call(&request).map_err(bridge_error)?;
        return crate::application::decode_response(decode(vm, &response, 0)?);
    }
    let operation = request
        .get("operation")
        .and_then(|v| v.text().ok())
        .unwrap_or("-");
    let request = observe(vm, operation, "encode", || encode(vm, request))?;
    let response = observe(vm, operation, "evaluate", || {
        vm.call(&request).map_err(bridge_error)
    })?;
    observe(vm, operation, "decode", || {
        crate::application::decode_response(decode(vm, &response, 0)?)
    })
}
