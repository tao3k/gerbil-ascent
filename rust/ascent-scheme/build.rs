//! The upstream compiler owns the native graph and archive construction.
use gerbil_scheme_aot_build::{
    CargoDirectiveKind, ProgramArchiveRequest, build_program_archive, discover_gambit_gsc_from_env,
    gerbil_command, run_native_process, source_workspace,
};
use std::{env, path::PathBuf};

fn main() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap();
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap());
    for directory in [
        "interface",
        "evidence",
        "program",
        "core",
        "table",
        "candidate",
        "applications",
    ] {
        println!("cargo:rerun-if-changed={}", root.join(directory).display());
    }
    for key in [
        "GERBIL_HOME",
        "GERBIL_GXI",
        "GERBIL_GSC",
        "SDKROOT",
        "PKG_CONFIG_PATH",
    ] {
        println!("cargo:rerun-if-env-changed={key}");
    }
    let workspace = source_workspace();
    for source in [
        "build.ss",
        "gerbil.pkg",
        "scheme/runtime.ss",
        "scheme/runtime.ssi",
        "scheme/runtime-collections.ss",
        "scheme/runtime-object-kinds.ss",
        "scheme/runtime-composites.ss",
        "scheme/utf8.ss",
        "scheme/program-build.ss",
    ] {
        println!(
            "cargo:rerun-if-changed={}",
            workspace.join(source).display()
        );
    }
    run_native_process(
        gerbil_command(workspace.join("build.ss"))
            .arg("compile")
            .current_dir(&workspace)
            .env("GERBIL_PATH", root.join(".gerbil")),
        "prepare upstream native bridge modules",
        true,
    )
    .unwrap();
    let expression = format!(
        "(import :std/make :gerbil/compiler {:?}) (make [\"interface/evidence-module\" \"interface/engine-api\" \"interface/hybrid\"] srcdir: {:?} libdir: {:?} build-deps: {:?} optimize: #t) (gerbil-rs-stage-program {:?} {:?})",
        workspace.join("scheme/program-build.ss").to_str().unwrap(),
        root.to_str().unwrap(),
        root.join(".gerbil/lib").to_str().unwrap(),
        out.join("build-deps").to_str().unwrap(),
        root.join("interface/hybrid.ss").to_str().unwrap(),
        out.to_str().unwrap()
    );
    run_native_process(
        gerbil_command("gxi")
            .args(["-e", &expression])
            .current_dir(&root)
            .env("GERBIL_PATH", root.join(".gerbil")),
        "compile and stage native ASCENT hybrid graph",
        true,
    )
    .unwrap();
    let gsc = discover_gambit_gsc_from_env().unwrap();
    let receipt = build_program_archive(ProgramArchiveRequest {
        manifest: &out.join("program.json"),
        gsc: &gsc,
        archive_name: "ascent_hybrid",
        linker_name: "ascent_hybrid",
        out_dir: &out.join("archive"),
    })
    .unwrap();
    for directive in receipt.cargo_directives {
        match directive.kind {
            CargoDirectiveKind::RustcLinkSearch => {
                println!("cargo:rustc-link-search={}", directive.value)
            }
            CargoDirectiveKind::RustcLinkLib => {
                println!("cargo:rustc-link-lib={}", directive.value)
            }
        }
    }
}
