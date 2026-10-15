//! Native DSL session and retained-result ownership boundary.
mod result;
mod session;
pub use result::{RowValue, SourceResult};
pub use session::{SourceObservation, SourceSession, allocate_source_identity};
