//! Public owner boundary.
mod events;
mod owner;
pub use owner::Trajectory;
pub(crate) use owner::{State, add, increment, set, totals};
