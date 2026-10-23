//! Thin ASCENT application binding over gerbil-scheme-rust.
mod application;
mod control;
mod dag;
mod diagnostics;
mod ffi;
mod values;
pub use dag::Dag;
mod process_checkpoint;
mod process_wire;
mod process_worker;
mod service;
pub use application::Runtime;
pub(crate) use application::{failure, scheme_error};
pub use process_worker::serve as serve_process_worker;
pub use service::{
    ProcessOwner, ProcessPool, ProcessReceipt, ProcessStatistics, WorkerProgram, configure_worker,
};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(
    config = {
        asp_rust::default_asp_rust_config().with_verification_profile_hint(
            asp_rust::RustVerificationProfileHint::new("src/lib.rs", [asp_rust::RustOwnerResponsibility::PublicApi])
                .with_rationale("The native test enters the original Scheme DSL through the linked C ABI and checks owned conversions, callable semantics and failure recovery")
        )
    }
);

#[cfg(test)]
#[path = "../tests/unit/runtime.rs"]
mod tests;

mod api;
#[doc(hidden)]
#[path = "../benches/support/hybrid.rs"]
pub mod benchmark;
pub use api::{
    Backend, Engine, Explanation, Module, ModuleValue, ResultValue, RuleResult, RuleSession,
    SchemeProvenance, Source,
};

mod identity;
pub use identity::build_identity;
