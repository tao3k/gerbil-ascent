//! Runtime Scheme data reader and typed declaration lowering.
mod components;
mod declarations;
mod evidence;
mod explanation;
mod functions;
mod graphs;
mod literals;
mod local_rules;
mod lowering;
mod macros;
mod reader;
mod recorded;
mod structural;
pub(crate) use reader::{Datum, read as read_datum};
pub use evidence::EvidenceProgram;
pub use explanation::EvidenceExplanation;
