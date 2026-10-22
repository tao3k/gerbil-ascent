//! Execution ownership boundary for Scheme-generated composition and Rust kernels.
mod budget;
mod expressions;
mod facts;
mod kernels;
mod lattice;
mod matching;
mod ordinal;
mod policy;
mod values;
pub(crate) use budget::Budget;
pub use budget::{Cancellation, Limits};
pub(crate) use facts::{Fact, FactSet};
pub(crate) use kernels::{Batch, Round, Store, apply_rule, evaluate};
pub(crate) use matching::{Bindings, MatchState};
pub(crate) use policy::request_fanout;

pub(crate) use values::{Cell, Pattern, Values};

mod reductions;
pub use kernels::{compose_graphs, make_projection_graph, make_transitive_graph};

pub(crate) mod work;
