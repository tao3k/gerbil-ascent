//! Semantic integration test harness for the original Scheme API and both runtimes.
#[path = "integration/aggregate_constructors.rs"]
mod aggregate_constructors;
#[path = "integration/constructor_sessions.rs"]
mod constructor_sessions;
#[path = "integration/hygiene.rs"]
mod hygiene;
#[path = "integration/module_operators.rs"]
mod module_operators;
#[path = "integration/module_values.rs"]
mod module_values;
#[path = "support/mod.rs"]
mod support;
#[path = "integration/typed.rs"]
mod typed;

#[path = "integration/projection.rs"]
mod projection;

#[path = "integration/concurrency.rs"]
mod concurrency;

#[path = "support/process_factory.rs"]
mod factory;
use factory::{engine, engines};
