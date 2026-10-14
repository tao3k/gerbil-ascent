//! Owned Scheme definitions, lexical calls and identity-preserving object graphs.
mod components;
mod constructors;
mod evaluation;
mod evidence;
mod freeze;
mod objects;
mod observations;
mod operator_change;
mod operator_lowering;
mod operator_values;
mod owner;
mod primitives;
mod reachability;
mod reflection;
mod registry;
mod relational;
mod replacement;
mod views;
pub use components::{Component, Dependency};
pub use evidence::{Evidence, Explanation};
pub use objects::{ObjectInput, ValueReference};
pub use owner::{Module, ModuleValue};

mod aggregates;

mod closed_procedures;

mod numeric_values;

mod native_forms;

mod view_rows;

mod declarations;

mod lists;

mod typed;

mod value_bindings;

use constructors::Admission;
use evaluation::Evaluation;
use objects::{Arena, Id, Object, fail};
use operator_lowering::{fields as operator_fields, lower as lower_operator};
use operator_values::{
    columns as operator_columns, count as operator_count, index as operator_index,
    scalar as operator_scalar,
};
use relational::limits as operator_limits;
