#![cfg(all(feature = "instances", target_os = "macos"))]
//! The identical semantic cases through the upstream independent-VM adapter.
#[path = "aggregate_constructors.rs"]
mod aggregate_constructors;
#[path = "constructor_sessions.rs"]
mod constructor_sessions;
#[path = "hygiene.rs"]
mod hygiene;
#[path = "module_operators.rs"]
mod module_operators;
#[path = "module_values.rs"]
mod module_values;
#[path = "../support/mod.rs"]
mod support;
#[path = "typed.rs"]
mod typed;

#[path = "projection.rs"]
mod projection;

#[path = "concurrency.rs"]
mod concurrency;

#[path = "../support/instance_factory.rs"]
mod factory;
use factory::engine;
