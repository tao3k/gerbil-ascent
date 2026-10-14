//! Public owner boundary.
mod clauses;
mod owner;
pub use owner::Catalog;
pub(crate) use owner::{read_relation, scalar, shape};
