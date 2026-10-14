//! Checked rule dependency graph, including positive recursive dependencies.
mod admission;
pub(crate) use admission::{Atom, Clause, Graph, Rule};
