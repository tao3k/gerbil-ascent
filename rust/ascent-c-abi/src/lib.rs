//! Fixed C ABI over existing ASCENT algorithms, independent of a Scheme VM.
mod diagnostics;
mod exports;
mod operations;
mod transport;
pub use exports::{ascent_core_abi_version, ascent_core_open, open};

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(
    config = {
        asp_rust::default_asp_rust_config()
            .with_verification_profile_hint(asp_rust::RustVerificationProfileHint::new(
                "src/exports.rs",
                [
                    asp_rust::RustOwnerResponsibility::PublicApi,
                    asp_rust::RustOwnerResponsibility::ExternalDependency,
                    asp_rust::RustOwnerResponsibility::SecurityBoundary,
                    asp_rust::RustOwnerResponsibility::AvailabilityCritical,
                ],
            ))
            .with_verification_profile_hint(asp_rust::RustVerificationProfileHint::new(
                "src/operations.rs",
                [
                    asp_rust::RustOwnerResponsibility::ExternalDependency,
                    asp_rust::RustOwnerResponsibility::SecurityBoundary,
                    asp_rust::RustOwnerResponsibility::AvailabilityCritical,
                ],
            ))
    }
);
