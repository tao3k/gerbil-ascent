//! `PyO3` facade over the ASCENT Rust Library.
mod api;

#[cfg(test)]
asp_rust::asp_rust_cargo_test_gate!(
    config = {
        asp_rust::default_asp_rust_config().with_verification_profile_hint(
        asp_rust::RustVerificationProfileHint::new("src/api/bindings.rs", [asp_rust::RustOwnerResponsibility::PublicApi])
            .with_rationale("Installed-wheel tests exercise conversion, GIL-released execution, budgets and concurrent Python callers"),
    )
    }
);
