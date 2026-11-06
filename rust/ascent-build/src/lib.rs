//! Native package and archive consumption. Gerbil and its Rust integration library own build state.
mod graph;
#[cfg(feature = "instances")]
mod instance_resources;
#[cfg(feature = "python-sources")]
mod python_instances;
#[cfg(feature = "python-sources")]
mod python_sources;
#[cfg(feature = "python-sources")]
pub use python_sources::stage_python_sources;

use gerbil_scheme_aot_build::{
    CargoDirectiveKind, ProgramArchiveObservation, ProgramArchiveObserver, ProgramArchiveRequest,
    build_program_archive_observed, discover_gambit_gsc_from_env,
};
use sha2::{Digest, Sha256};
use std::{
    env, fs,
    io::Read,
    path::{Path, PathBuf},
};

/// Consume the package through its native build entry and the Rust integration library archive API.
/// # Errors
/// Propagates native build, compiler, Rust integration library and link failures.
pub fn build() -> Result<(), String> {
    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").ok_or("missing package directory")?)
        .join("../..")
        .canonicalize()
        .map_err(|e| e.to_string())?;
    let out = PathBuf::from(env::var_os("OUT_DIR").ok_or("missing OUT_DIR")?);
    let graph = out.join("program");
    let runtime = graph::prepare(&root, &graph)?;
    let gsc = discover_gambit_gsc_from_env()?;
    let receipt = build_program_archive_observed(
        ProgramArchiveRequest {
            manifest: &graph.join("program.json"),
            gsc: &gsc,
            archive_name: "ascent_hybrid",
            linker_name: "ascent_hybrid",
            out_dir: &out.join("archive"),
        },
        &CargoInputs,
    )?;
    for directive in &receipt.cargo_directives {
        match directive.kind {
            CargoDirectiveKind::RustcLinkSearch => {
                println!("cargo:rustc-link-search={}", directive.value);
            }
            CargoDirectiveKind::RustcLinkLib => {
                println!("cargo:rustc-link-lib={}", directive.value);
            }
        }
    }
    // The protocol binds the produced program bytes, not another directory inventory.
    let mut input = fs::File::open(&receipt.archive_file).map_err(|e| e.to_string())?;
    let mut hash = Sha256::new();
    let mut buffer = [0_u8; 16384];
    loop {
        let count = input.read(&mut buffer).map_err(|e| e.to_string())?;
        if count == 0 {
            break;
        }
        hash.update(&buffer[..count]);
    }
    println!(
        "cargo:rustc-env=ASCENT_NATIVE_PROGRAM_SHA256={:x}",
        hash.finalize()
    );
    #[cfg(feature = "instances")]
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        instance_resources::prepare(&runtime, &gsc, &receipt, &graph, &out)?;
    }
    drop(runtime);
    Ok(())
}

// Forward the Rust integration library's actual consumed inputs to Cargo; retain no parallel index.
struct CargoInputs;
impl ProgramArchiveObserver for CargoInputs {
    fn observe(&self, event: ProgramArchiveObservation<'_>) {
        eprintln!("{event}");
    }
    fn observe_source_input(&self, path: &Path) {
        println!("cargo:rerun-if-changed={}", path.display());
    }
}
