//! Checked rule dependency graph, including positive recursive dependencies.
mod admission;
mod certificate;
pub(crate) use admission::{Atom, Clause, Graph, Rule};
