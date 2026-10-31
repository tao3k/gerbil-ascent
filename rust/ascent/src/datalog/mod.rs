//! Inert relational text is read into native graphs; downstream compilation is never required.
mod inference;
mod lexer;
mod parser;
mod reader;
pub use reader::{DatalogGraph, DatalogRequest, evaluate_datalog, read_datalog};
