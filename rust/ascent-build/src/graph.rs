//! Consume the package's native declarations through the Rust integration library's existing C ABI.
use gerbil_scheme::GerbilRuntime;
use gerbil_scheme_aot_build::source_workspace;
use std::path::Path;

pub fn prepare(root: &Path, output: &Path) -> Result<GerbilRuntime, String> {
    let runtime = GerbilRuntime::initialize().map_err(|error| error.to_string())?;
    let workspace = source_workspace();
    // The Library selects its standard package environment first. Its optional
    // embedding dependency then builds into that same native environment.
    for package in [root, workspace.as_path()] {
        admit(
            runtime.build_package(package.to_str().ok_or("non-UTF8 package path")?),
            "native package build",
        )?;
    }
    let directory = root.to_str().ok_or("non-UTF8 package path")?;
    admit(
        runtime.build_package_spec(directory, "gerbil-ascent-rust-spec"),
        "native embedding declaration",
    )?;
    let imports: &[&str] = if std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("macos") {
        &[
            ":gerbil/compiler/base",
            ":gerbil-ascent/rules/func",
            ":gerbil-ascent/rules/module",
        ]
    } else {
        &[]
    };
    let entry = root.join("interface/hybrid.ss");
    for source in [root.join("build.ss"), root.join("init.ss"), entry.clone()] {
        println!("cargo:rerun-if-changed={}", source.display());
    }
    admit(
        runtime.stage_package_program(
            entry.to_str().ok_or("non-UTF8 embedding entry")?,
            output.to_str().ok_or("non-UTF8 programme output")?,
            imports,
        ),
        "native programme graph",
    )?;
    Ok(runtime)
}

fn admit(result: Result<i32, gerbil_scheme::NativeError>, operation: &str) -> Result<(), String> {
    let code = result.map_err(|error| format!("{operation}: {error}"))?;
    if code != 0 {
        return Err(format!("{operation} failed with native result {code}"));
    }
    Ok(())
}
