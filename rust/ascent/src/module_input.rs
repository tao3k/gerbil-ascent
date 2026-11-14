//! Typed native arguments and component declarations; no language evaluation.
use num_bigint::BigInt;
use num_rational::BigRational;
/// Typed argument boundary; no wire serialization or Python objects enter the owner.
#[derive(Clone, Debug)]
pub enum ObjectInput {
    ResultValue(crate::RowValue),
    Value(crate::Value),
    Integer(BigInt),
    Rational(BigRational),
    Inexact(f64),
    Boolean(bool),
    Number(String),
    Character(char),
    Text(String),
    Symbol(String),
    List(Vec<Self>),
    Pair(Box<Self>, Box<Self>),
    Vector(Vec<Self>),
    Bytes(Vec<u8>),
    Reference(ValueReference),
    /// Live cell authority in a native source generation, checked on VM entry.
    SourceReference {
        owner: u64,
        generation: u64,
        result: u64,
        node: usize,
    },
}
/// Reference authority is validated against its originating live value lease.
#[derive(Clone, Debug)]
pub struct ValueReference {
    pub owner: u64,
    pub result: u64,
    pub node: usize,
}

/// Selected bindings imported from one independently scoped component.
#[derive(Clone, Debug)]
pub struct Dependency {
    pub component: String,
    pub bindings: Vec<String>,
}
/// Source definitions and explicit component linkage authority.
#[derive(Clone, Debug)]
pub struct Component {
    pub id: String,
    pub source: String,
    pub exports: Option<Vec<String>>,
    pub dependencies: Vec<Dependency>,
}
