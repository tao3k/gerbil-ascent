//! Finite typed functions are inert native descriptions; execution holds no construction callbacks.
mod constructors;
mod normalization;
mod types;
pub(super) use types::EXPORTS;
