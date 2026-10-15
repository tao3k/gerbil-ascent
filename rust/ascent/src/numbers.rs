//! Closed real arithmetic on owned exact rationals and IEEE binary64 values.
use crate::{Error, FrozenValue, GraphItem, ObjectGraph, Result, Value};
use num_rational::BigRational;
use num_traits::{Signed, ToPrimitive, Zero};
use std::collections::BTreeMap;
#[derive(Clone, Debug)]
pub(crate) enum Number {
    Exact(BigRational),
    Inexact(f64),
}
impl Number {
    pub(crate) fn is_inexact(value: &Value) -> bool {
        matches!(value,Value::Object(v) if matches!(v.numeric(),Some(Self::Inexact(_))))
    }
    pub(crate) fn read(value: &Value) -> Result<Self> {
        match value {
            Value::Integer(n) => Ok(Self::Exact(BigRational::from_integer(n.clone()))),
            Value::Object(v) => v.numeric().cloned().ok_or_else(invalid),
            _ => Err(invalid()),
        }
    }
    pub(crate) fn inexact(&self) -> f64 {
        match self {
            Self::Inexact(n) => *n,
            Self::Exact(n) => n.to_f64().unwrap_or_else(|| {
                if n.is_negative() {
                    f64::NEG_INFINITY
                } else {
                    f64::INFINITY
                }
            }),
        }
    }
    pub(crate) fn units(&self) -> u64 {
        match self {
            Self::Exact(n) => (n.numer().bits() / 64 + 1).saturating_add(n.denom().bits() / 64 + 1),
            Self::Inexact(_) => 1,
        }
    }
    pub(crate) fn add(self, other: Self) -> Self {
        match (self, other) {
            (Self::Exact(a), Self::Exact(b)) => Self::Exact(a + b),
            (Self::Exact(a), Self::Inexact(b)) if a == BigRational::from_integer(0.into()) => {
                Self::Inexact(b)
            }
            (Self::Inexact(a), Self::Exact(b)) if b == BigRational::from_integer(0.into()) => {
                Self::Inexact(a)
            }
            (a, b) => Self::Inexact(a.inexact() + b.inexact()),
        }
    }
    pub(crate) fn extreme(self, other: Self, minimum: bool) -> Self {
        match (self, other) {
            (Self::Exact(a), Self::Exact(b)) => {
                Self::Exact(if minimum { a.min(b) } else { a.max(b) })
            }
            (a, b) => {
                let (a, b) = (a.inexact(), b.inexact());
                Self::Inexact(if a.is_nan() || b.is_nan() {
                    f64::NAN
                } else if a.partial_cmp(&b) == Some(std::cmp::Ordering::Equal) {
                    b
                } else if minimum {
                    a.min(b)
                } else {
                    a.max(b)
                })
            }
        }
    }
    pub(crate) fn value(self) -> Result<Value> {
        let text = match self {
            Self::Exact(n) if n.is_integer() => return Ok(Value::Integer(n.to_integer())),
            Self::Exact(n) => n.to_string(),
            Self::Inexact(n) => format_inexact(n),
        };
        FrozenValue::new(
            0,
            0,
            ObjectGraph {
                root: GraphItem::Number(text),
                nodes: BTreeMap::new().into(),
            },
        )
        .map(Value::Object)
    }
}
pub(crate) fn parse_inexact(text: &str) -> Option<f64> {
    match text {
        "+inf.0" => Some(f64::INFINITY),
        "-inf.0" => Some(f64::NEG_INFINITY),
        "+nan.0" | "-nan.0" => Some(f64::NAN),
        _ if text.contains(['.', 'e', 'E']) => text.parse().ok(),
        _ => None,
    }
}
pub(crate) fn format_inexact(value: f64) -> String {
    if value.is_nan() {
        "+nan.0".into()
    } else if value == f64::INFINITY {
        "+inf.0".into()
    } else if value == f64::NEG_INFINITY {
        "-inf.0".into()
    } else {
        format!("{value:?}")
    }
}
fn invalid() -> Error {
    Error::Evaluation("aggregate requires real numeric values".into())
}

pub(crate) fn parse_number(text: &str) -> Option<Number> {
    if let Some(value) = parse_inexact(text) {
        return Some(Number::Inexact(value));
    }
    let (a, b) = text.split_once('/').unwrap_or((text, "1"));
    let denominator = b.parse::<num_bigint::BigInt>().ok()?;
    if denominator.is_zero() {
        return None;
    }
    Some(Number::Exact(BigRational::new(
        a.parse().ok()?,
        denominator,
    )))
}

pub(crate) fn canonical_text(text: &str) -> String {
    match parse_number(text) {
        Some(Number::Exact(value)) => value.to_string(),
        Some(Number::Inexact(value)) => format_inexact(value),
        None => text.into(),
    }
}
