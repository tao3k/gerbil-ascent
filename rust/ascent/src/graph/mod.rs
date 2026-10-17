//! Checked rule dependency graph, including positive recursive dependencies.
mod admission;
mod certificate;
mod descriptor_stream;
pub(crate) use admission::{Atom, Clause, Graph, Rule};
