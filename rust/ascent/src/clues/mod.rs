//! Public clue-exchange owner boundary.
mod exchange;
mod slices;
pub use exchange::{ClueExchange, clue_sexpr, read_clue_request};
use exchange::{RULES, data_rows, evaluate, invalid, rows};
