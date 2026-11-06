//! Closed numeric lattice joins that execute without host callbacks.
use crate::{Error, Result, Value};
use num_rational::BigRational;
/// Numeric semilattice on the last column; all preceding columns form the key.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LatticeJoin {
    Min,
    Max,
}
impl LatticeJoin {
    pub(crate) fn improves(self, candidate: &Value, prior: &Value) -> Result<bool> {
        let a = numeric(candidate)?;
        let b = numeric(prior)?;
        Ok(match self {
            Self::Min => a < b,
            Self::Max => a > b,
        })
    }
}
pub(crate) fn numeric(value: &Value) -> Result<BigRational> {
    match value {
        Value::Integer(v) => Ok(BigRational::from_integer(v.clone())),
        Value::Object(v) => v
            .number()
            .ok_or_else(|| Error::Evaluation("numeric lattice value required".into())),
        _ => Err(Error::Evaluation("numeric lattice value required".into())),
    }
}
