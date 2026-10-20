//! Freeze Library-owned source bytes through the shared upstream package owner.
use gerbil_scheme_python::{ResourceTree, build_source_root, stage_source_inventory};
use std::{env, fs, io, path::PathBuf};

fn main() {
    if env::var_os("CARGO_FEATURE_RUST_RUNTIME").is_none() {
        return;
    }
    let package = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("crate"));
    let root = package
        .join("../..")
        .canonicalize()
        .expect("Library source root");
    let bridge = build_source_root().expect("compiled bridge dependency source");
    let compiler = gerbil_scheme_compiler_source::build_source_root()
        .expect("pinned build-only compiler dependency source");
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("build output"));
    let directories = [
        (root.join("rust/ascent/src"), "_sources/rust/ascent/src"),
        (
            root.join("rust/ascent-c-abi/src"),
            "_sources/rust/ascent-c-abi/src",
        ),
        (
            root.join("rust/ascent-python/src"),
            "_sources/rust/ascent-python/src",
        ),
        (
            bridge.join("crates/gerbil-scheme-python/src"),
            "_sources/bridge/crates/gerbil-scheme-python/src",
        ),
        (
            compiler.join("build-support/gerbil-scheme-rust-ir/src"),
            "_sources/compiler/build-support/gerbil-scheme-rust-ir/src",
        ),
    ];
    let files = [
        (
            root.join("rust/ascent-c-abi/Cargo.toml"),
            "_sources/rust/ascent-c-abi/Cargo.toml",
        ),
        (
            root.join("bindings/c/ascent-core.h"),
            "_sources/bindings/c/ascent-core.h",
        ),
        (
            bridge.join("include/gerbil_scheme_owned.h"),
            "_sources/bridge/include/gerbil_scheme_owned.h",
        ),
        (
            bridge.join("include/gerbil_scheme_rust.h"),
            "_sources/bridge/include/gerbil_scheme_rust.h",
        ),
        (root.join("rust/Cargo.toml"), "_sources/rust/Cargo.toml"),
        (root.join("rust/Cargo.lock"), "_sources/rust/Cargo.lock"),
        (
            root.join("rust/ascent/Cargo.toml"),
            "_sources/rust/ascent/Cargo.toml",
        ),
        (
            root.join("rust/ascent/build.rs"),
            "_sources/rust/ascent/build.rs",
        ),
        (
            root.join("rust/ascent-python/Cargo.toml"),
            "_sources/rust/ascent-python/Cargo.toml",
        ),
        (
            root.join("rust/ascent-python/build.rs"),
            "_sources/rust/ascent-python/build.rs",
        ),
        (
            root.join("python/pyproject.toml"),
            "_sources/python/pyproject.toml",
        ),
        (
            root.join("python/src/ascent/__init__.py"),
            "_sources/python/src/ascent/__init__.py",
        ),
        (
            root.join("program/rust-execution.ss"),
            "_sources/program/rust-execution.ss",
        ),
        (
            compiler.join("build-support/gerbil-scheme-rust-ir/Cargo.toml"),
            "_sources/compiler/build-support/gerbil-scheme-rust-ir/Cargo.toml",
        ),
        (compiler.join("Cargo.toml"), "_sources/compiler/Cargo.toml"),
        (compiler.join("Cargo.lock"), "_sources/compiler/Cargo.lock"),
        (bridge.join("Cargo.toml"), "_sources/bridge/Cargo.toml"),
        (bridge.join("Cargo.lock"), "_sources/bridge/Cargo.lock"),
        (
            bridge.join("crates/gerbil-scheme-python/Cargo.toml"),
            "_sources/bridge/crates/gerbil-scheme-python/Cargo.toml",
        ),
    ];
    for (path, _) in directories.iter().chain(&files) {
        let mut pending = vec![path.clone()];
        while let Some(input) = pending.pop() {
            println!("cargo:rerun-if-changed={}", input.display());
            let kind = fs::symlink_metadata(&input)
                .expect("source inventory input")
                .file_type();
            if kind.is_dir() {
                let mut entries = fs::read_dir(&input)
                    .expect("source inventory directory")
                    .map(|entry| entry.map(|item| item.path()))
                    .collect::<io::Result<Vec<_>>>()
                    .expect("source inventory entries");
                entries.sort();
                pending.extend(entries.into_iter().rev());
            } else if !kind.is_file() {
                panic!("source inventory contains a symlink or special file");
            }
        }
    }
    let trees = directories
        .iter()
        .map(|(p, n)| ResourceTree::complete(p, n))
        .chain(files.iter().map(|(p, n)| ResourceTree::file(p, n)))
        .collect::<Vec<_>>();
    stage_source_inventory(&output, &root.join("python/src/ascent"), &trees, "_sources")
        .expect("complete source publication");
}
