use gerbil_scheme_aot_build::gerbil_command;
use std::{env, fs, path::PathBuf, process::Stdio};

fn main() {
    let root = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("package"))
        .join("../..")
        .canonicalize()
        .expect("source root");
    let source = root.join("program/rust-execution.ss");
    println!("cargo:rerun-if-changed={}", source.display());
    for key in ["GERBIL_HOME", "GERBIL_GXI", "GERBIL_GSC"] {
        println!("cargo:rerun-if-env-changed={key}");
    }
    let mut command = gerbil_command("gxi");
    command.arg(&source);
    command
        .current_dir(&root)
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    // gerbil_command applies the bridge's selected toolchain environment. Only
    // this build-time compiler runs Scheme; the produced library has no VM.
    let output = command.output().expect("execute Scheme IR producer");
    assert!(output.status.success(), "Scheme IR producer failed");
    let input = String::from_utf8(output.stdout).expect("compiler IR UTF-8");
    let mut generated = String::from("// Generated from program/rust-execution.ss; do not edit.\n");
    for line in input.lines().filter(|line| !line.is_empty()) {
        generated.push_str("#[inline]\n");
        generated.push_str(
            &gerbil_scheme_rust_ir::compile_function_json(line).expect("admitted typed Scheme IR"),
        );
    }
    fs::write(
        PathBuf::from(env::var_os("OUT_DIR").expect("output")).join("execution.rs"),
        generated,
    )
    .expect("publish generated Rust");
}
