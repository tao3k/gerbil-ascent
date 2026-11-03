//! Independent single-thread VM owner interface.
//!
//! This optional boundary isolates Scheme heaps and mutable module state between
//! VM owners in one process. It is not required for rule evaluation, Session
//! branches or provenance reuse, and does not provide process fault isolation.
//! Each owner pays its own VM and source-context initialization cost. The native
//! resource migration currently fails its unchanged readiness timeout; compile
//! success alone does not qualify this route or establish a throughput advantage.
mod lifecycle;
mod owner;
mod package;
mod values;
use owner::bridge_error;
pub use owner::{InstanceOwner, InstancePool};
pub use package::InstancePackage;
