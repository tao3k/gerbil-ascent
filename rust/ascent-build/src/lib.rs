//! Package orchestration; the upstream compiler owns graph and archive semantics.
mod cache;
mod graph;
mod input;
mod ledger;
mod observer;
mod policy;
#[cfg(feature = "python-sources")]
mod python_sources;

#[cfg(feature = "python-sources")]
pub use python_sources::stage_python_sources;

use gerbil_scheme_aot_build::{
    ProgramArchiveObserver, ProgramArchiveOperation, ProgramArchiveRequest,
    build_program_archive_observed, discover_gambit_gsc_from_env,
    observe_program_archive_operation, source_workspace,
};
use std::{
    env,
    path::{Path, PathBuf},
};

/// Build the consumer archive using the pinned upstream compiler.
/// # Errors
/// Preserves compiler failures and rejects incomplete or changed-input observations.
pub fn build() -> Result<(), String> {
    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").ok_or("missing package directory")?)
        .join("../..")
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let out = PathBuf::from(env::var_os("OUT_DIR").ok_or("missing OUT_DIR")?);
    inputs(&root);
    let shared = cache::Lease::acquire(&out)?;
    let observer = observer::Observer::new(
        &out,
        &shared
            .archive
            .parent()
            .ok_or("missing shared root")?
            .join("inputs"),
        &root.join(".gerbil/lib/static"),
        shared.wait_ns,
    )?;
    let result = construct(&root, &out, &shared, &observer);
    let admission = observer.finish(result.is_ok());
    // Retain the compiler's original error even when the receipt also rejects.
    result.and(admission)
}
fn construct(
    root: &Path,
    out: &Path,
    shared: &cache::Lease,
    observer: &observer::Observer,
) -> Result<(), String> {
    graph::prepare(root, shared, observer)?;
    let gsc = discover_gambit_gsc_from_env()?;
    for source in [
        &shared.graph.join("program.json"),
        &shared.graph.join("program__exe.scm"),
        &gsc,
    ] {
        observer.observe_source_input(source);
    }
    let receipt = build_program_archive_observed(
        ProgramArchiveRequest {
            manifest: &shared.graph.join("program.json"),
            gsc: &gsc,
            archive_name: "ascent_hybrid",
            linker_name: "ascent_hybrid",
            out_dir: &shared.archive,
        },
        observer,
    )?;
    observe_program_archive_operation(
        observer,
        ProgramArchiveOperation {
            phase: "private-archive",
            operation: "copy detached archive",
            subject: None,
        },
        || shared.publish(out, &receipt),
    )?;
    graph::identify(root, out, &gsc, observer)
}

fn inputs(root: &std::path::Path) {
    for key in [
        "GERBIL_HOME",
        "GERBIL_GXI",
        "GERBIL_GSC",
        "SDKROOT",
        "PKG_CONFIG_PATH",
    ] {
        println!("cargo:rerun-if-env-changed={key}");
    }
    // Directory dependencies include additions/removals, not just existing files.
    // These are the package source roots, excluding build outputs and test trees.
    for source in [
        "build.ss",
        "build-modules.ss",
        "gerbil.pkg",
        "bindings",
        "core",
        "table",
        "program",
        "applications",
        "candidate",
        "temporal",
        "interface",
        "evidence",
        "t/qualification/evidence-api-module.ss",
    ] {
        println!("cargo:rerun-if-changed={}", root.join(source).display());
    }
    let workspace = source_workspace();
    for source in ["build.ss", "gerbil.pkg", "scheme"] {
        println!(
            "cargo:rerun-if-changed={}",
            workspace.join(source).display()
        );
    }
}
