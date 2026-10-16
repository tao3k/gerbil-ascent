//! `PyO3` facade over the ASCENT Rust Library.
#[cfg(all(feature = "rust-runtime", feature = "scheme-runtime"))]
compile_error!("select exactly one runtime using Cargo features; no automatic fallback");
#[cfg(not(any(feature = "rust-runtime", feature = "scheme-runtime")))]
compile_error!("an explicit runtime Cargo feature is required");
#[cfg(feature = "scheme-runtime")]
mod api;
#[cfg(feature = "rust-runtime")]
mod build_inventory;
#[cfg(feature = "rust-runtime")]
mod closure_cuts;
#[cfg(feature = "rust-runtime")]
mod core_abi;
#[cfg(feature = "rust-runtime")]
mod rust_api;
#[cfg(feature = "rust-runtime")]
mod rust_components;
#[cfg(feature = "rust-runtime")]
mod rust_graph;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(
    config = {
        asp_rust::default_asp_rust_config().with_verification_profile_hint(
        asp_rust::RustVerificationProfileHint::new("src/api/bindings.rs", [asp_rust::RustOwnerResponsibility::PublicApi])
            .with_rationale("Installed-wheel tests exercise conversion, GIL-released execution, budgets and concurrent Python callers"),
    )
    }
);
