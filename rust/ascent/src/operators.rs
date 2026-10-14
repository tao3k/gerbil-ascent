//! Owned scalar expressions, with Scheme truth and exact integer operators.
use crate::Term;

/// Closed expression tree loaded from the native DSL, never a host callback.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Expression {
    Term(Term),
    Call(Operator, Vec<Self>),
}
/// Closed pure operators supported by native ASCENT guard/compute forms.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Operator {
    Less,
    LessEqual,
    Greater,
    GreaterEqual,
    NumericEqual,
    Equal,
    Add,
    Subtract,
    Multiply,
    Not,
    Even,
    Odd,
    Zero,
    Positive,
    Negative,
    And,
    Or,
    Identity,
}
impl Operator {
    pub(crate) fn named(name: &str) -> Option<Self> {
        Some(match name {
            "<" => Self::Less,
            "<=" => Self::LessEqual,
            ">" => Self::Greater,
            ">=" => Self::GreaterEqual,
            "=" => Self::NumericEqual,
            "equal?" => Self::Equal,
            "+" => Self::Add,
            "-" => Self::Subtract,
            "*" => Self::Multiply,
            "not" => Self::Not,
            "even?" => Self::Even,
            "odd?" => Self::Odd,
            "zero?" => Self::Zero,
            "positive?" => Self::Positive,
            "negative?" => Self::Negative,
            "and" => Self::And,
            "or" => Self::Or,
            "identity" => Self::Identity,
            _ => return None,
        })
    }
    pub(crate) fn arity(self, count: usize) -> bool {
        match self {
            Self::And | Self::Or => true,
            Self::Not
            | Self::Even
            | Self::Odd
            | Self::Zero
            | Self::Positive
            | Self::Negative
            | Self::Identity => count == 1,
            _ => count == 2,
        }
    }
}
/// Reducers read a completed lower stratum; empty min/max produce no binding.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Reducer {
    Mean,
    Count,
    Sum,
    Min,
    Max,
}
impl Reducer {
    pub(crate) fn named(name: &str) -> Option<Self> {
        Some(match name {
            "mean" => Self::Mean,
            "count" => Self::Count,
            "sum" => Self::Sum,
            "min" => Self::Min,
            "max" => Self::Max,
            _ => return None,
        })
    }
}
