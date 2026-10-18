//! Build-only use of the pinned upstream compiler-owned AOT graph.
use gerbil_scheme_aot_build::{
    CargoDirectiveKind, ProgramArchiveRequest, build_program_archive, discover_gambit_gsc_from_env,
    discover_native_c_compiler, gerbil_command, run_native_process, source_workspace,
};
use std::{path::PathBuf, process::Command};
fn main() {
    assert_eq!(
        std::env::var("CARGO_CFG_TARGET_OS").as_deref(),
        Ok("macos"),
        "private-image VM diagnostic is Darwin-only"
    );
    for input in [
        "../../../../../core",
        "../../../../../program",
        "../../../../../table",
        "../../../../../gerbil.pkg",
    ] {
        println!("cargo:rerun-if-changed={input}");
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
    for path in [
        "../vm-program.ss",
        "../scheme-runtime.ss",
        "../vm-adapter.c",
        "../vm-runner.c",
    ] {
        println!("cargo:rerun-if-changed={path}");
    }
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../../../..")
        .canonicalize()
        .unwrap();
    let out = root.join(".cache/ascent/multivm");
    std::fs::create_dir_all(&out).unwrap();
    let library = root.join(".gerbil/lib");
    let workspace = source_workspace();
    run_native_process(
        gerbil_command(workspace.join("build.ss"))
            .arg("compile")
            .current_dir(&workspace)
            .env("GERBIL_PATH", root.join(".gerbil")),
        "prepare pinned bridge modules",
        true,
    )
    .unwrap();
    let helper = workspace.join("scheme/program-build.ss");
    let source = root.join("rust/ascent-scheme/benches/support/vm-program.ss");
    let expression = format!(
        "(import :std/make :gerbil/compiler {:?}) (make [\"rust/ascent-scheme/benches/support/scheme-runtime\" \"rust/ascent-scheme/benches/support/vm-program\"] srcdir: {:?} libdir: {:?} build-deps: {:?} optimize: #t) (gerbil-rs-stage-program {:?} {:?})",
        helper.to_str().unwrap(),
        root.to_str().unwrap(),
        library.to_str().unwrap(),
        out.join("build-deps").to_str().unwrap(),
        source.to_str().unwrap(),
        out.to_str().unwrap()
    );
    run_native_process(
        gerbil_command("gxi")
            .args(["-e", &expression])
            .current_dir(&root)
            .env("GERBIL_PATH", root.join(".gerbil")),
        "stage ASCENT VM graph",
        true,
    )
    .unwrap();
    let gsc = discover_gambit_gsc_from_env().unwrap();
    let receipt = build_program_archive(ProgramArchiveRequest {
        manifest: &out.join("program.json"),
        gsc: &gsc,
        archive_name: "ascent_vm_diagnostic",
        linker_name: "ascent_vm_diagnostic",
        out_dir: &out.join("archive"),
    })
    .unwrap();
    let object = out.join("adapter.o");
    run_native_process(
        gerbil_command(&gsc)
            .args(["-obj", "-cc-options", "-O2", "-o"])
            .arg(&object)
            .arg(root.join("rust/ascent-scheme/benches/support/vm-adapter.c")),
        "compile VM adapter",
        true,
    )
    .unwrap();
    let compiler = discover_native_c_compiler().unwrap();
    let image = out.join("ascent-vm.dylib");
    let mut link = Command::new(&compiler.program);
    link.args(["-dynamiclib", "-o"])
        .arg(&image)
        .arg(&object)
        .arg(&receipt.archive_file);
    for d in &receipt.cargo_directives {
        match d.kind {
            CargoDirectiveKind::RustcLinkSearch => {
                link.arg(format!("-L{}", d.value.trim_start_matches("native=")));
            }
            CargoDirectiveKind::RustcLinkLib => {
                let lib = d
                    .value
                    .trim_start_matches("static=")
                    .trim_start_matches("dylib=");
                if lib != receipt.archive_name {
                    link.arg(format!("-l{lib}"));
                }
            }
        }
    }
    for name in [
        "init",
        "cleanup",
        "state",
        "prepare",
        "run",
        "validate",
        "capabilities",
    ] {
        link.arg(format!("-Wl,-exported_symbol,_ascent_vm_{name}"));
    }
    run_native_process(&mut link, "link private ASCENT VM image", true).unwrap();
    run_native_process(
        Command::new(&compiler.program)
            .args(["-O2", "-pthread", "-o"])
            .arg(out.join("vm-runner"))
            .arg(root.join("rust/ascent-scheme/benches/support/vm-runner.c")),
        "compile VM host",
        true,
    )
    .unwrap();
    println!("VM image: {}", image.display());
}
