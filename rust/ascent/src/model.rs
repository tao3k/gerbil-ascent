//! Owned typed declarations and immutable result observations.
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

/// Owned values may cross Rust threads; no Scheme heap pointer or root escapes.
/// Symbols here are named/interned values, not arbitrary Scheme object identity.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Value {
    Integer(num_bigint::BigInt),
    Object(crate::FrozenValue),
    Boolean(bool),
    Text(Arc<str>),
    Symbol(Arc<str>),
}
impl From<i64> for Value {
    fn from(value: i64) -> Self {
        Self::Integer(value.into())
    }
}
impl From<i32> for Value {
    fn from(value: i32) -> Self {
        Self::Integer(value.into())
    }
}
impl From<num_bigint::BigInt> for Value {
    fn from(value: num_bigint::BigInt) -> Self {
        Self::Integer(value)
    }
}
impl From<bool> for Value {
    fn from(value: bool) -> Self {
        Self::Boolean(value)
    }
}
impl From<&str> for Value {
    fn from(value: &str) -> Self {
        Self::Text(value.into())
    }
}

/// Declared column kind; values of different kinds remain distinct.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Type {
    Scalar,
    Any,
    Integer,
    Boolean,
    Text,
    Symbol,
}
impl Type {
    pub(crate) fn accepts(self, value: &Value) -> bool {
        self == Self::Any
            || (self == Self::Scalar
                && (matches!(
                    value,
                    Value::Integer(_) | Value::Boolean(_) | Value::Symbol(_)
                ) || matches!(value,Value::Object(v) if v.is_scalar())))
            || matches!(
                (self, value),
                (Self::Integer, Value::Integer(_))
                    | (Self::Boolean, Value::Boolean(_))
                    | (Self::Text, Value::Text(_))
                    | (Self::Symbol, Value::Symbol(_))
            )
    }
}
/// Immutable owned relation tuple, including a zero-column tuple.
pub type Row = Arc<[Value]>;

/// Variable, typed literal or existential wildcard.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Term {
    Variable(u32),
    Literal(Value),
    Wildcard,
}
/// One named relation applied to ordered terms.
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct Atom {
    pub relation: String,
    pub terms: Vec<Term>,
}
impl Atom {
    pub fn new(name: impl Into<String>, terms: Vec<Term>) -> Self {
        Self {
            relation: name.into(),
            terms,
        }
    }
}
/// Ordered relational, scalar or reduction condition.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Clause {
    Relation {
        atom: Atom,
        negative: bool,
    },
    Guard {
        inputs: Vec<u32>,
        expression: crate::Expression,
    },
    Compute {
        inputs: Vec<u32>,
        output: u32,
        expression: crate::Expression,
    },
    Reduce {
        output: u32,
        operator: crate::Reducer,
        atom: Atom,
        inputs: Vec<u32>,
    },
}
impl Clause {
    #[must_use]
    pub fn positive(atom: Atom) -> Self {
        Self::Relation {
            atom,
            negative: false,
        }
    }
    #[must_use]
    pub fn negative(atom: Atom) -> Self {
        Self::Relation {
            atom,
            negative: true,
        }
    }
}
/// A checked single-head rule with an ordered body.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Rule {
    pub head: Atom,
    pub body: Vec<Clause>,
}

/// Named typed set relation with explicit source authority.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Relation {
    pub(crate) auxiliary: bool,
    pub lattice: Option<crate::LatticeJoin>,
    pub name: String,
    pub columns: Vec<Type>,
    pub domains: Vec<Option<BTreeSet<Value>>>,
    pub rows: Vec<Row>,
    pub source: bool,
}
impl Relation {
    pub fn new(name: impl Into<String>, columns: Vec<Type>, source: bool) -> Self {
        Self {
            auxiliary: false,
            lattice: None,
            name: name.into(),
            domains: vec![None; columns.len()],
            rows: Vec::new(),
            columns,
            source,
        }
    }
    pub(crate) fn accepts(&self, row: &[Value]) -> bool {
        row.len() == self.columns.len()
            && row
                .iter()
                .zip(&self.columns)
                .zip(&self.domains)
                .all(|((value, ty), domain)| {
                    ty.accepts(value) && domain.as_ref().is_none_or(|domain| domain.contains(value))
                })
    }
}
/// Inert relation and rule declarations admitted before execution.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Program {
    pub relation_limit: Option<usize>,
    pub fact_limits: crate::FactLimits,
    pub relations: Vec<Relation>,
    pub rules: Vec<Rule>,
}

/// Immutable completed observation; this is not whole-task/model correctness.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Snapshot {
    pub generation: u64,
    pub relations: BTreeMap<String, Vec<Row>>,
}
