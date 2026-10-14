//! Thin ASCENT application binding over gerbil-scheme-rust.
mod application;
mod dag;
mod ffi;
mod values;
pub use dag::Dag;
mod service;
pub use application::Runtime;
pub(crate) use application::{failure, native_error};
pub use service::call;

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
#[path = "../tests/unit/native.rs"]
mod tests;

mod api;
#[doc(hidden)]
pub mod benchmark;
pub use api::{
    Engine, Evidence, EvidenceResult, Explanation, Module, ModuleValue, ResultValue, Source,
};
