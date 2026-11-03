//! Consume the Rust integration library expander closure and Rust integration library resource publication directly.
use gerbil_scheme::GerbilRuntime;
use gerbil_scheme_aot_build::{
    NativeArchiveLinkReceipt, NativeInstanceImageRequest, build_native_instance_image,
};
use gerbil_scheme_python::{ModuleClosure, ModuleRoot, ResourceTree, stage_module_closure};
use std::{fs, path::Path};

pub(super) fn prepare(
    runtime: &GerbilRuntime,
    gsc: &Path,
    archive: &NativeArchiveLinkReceipt,
    graph: &Path,
    out: &Path,
) -> Result<(), String> {
    let image = build_native_instance_image(NativeInstanceImageRequest {
        gsc,
        archive,
        linker_symbol: "___LNK_ascent__hybrid",
        output: &out.join("ascent-instance.dylib"),
        exports: &[
            "ascent_hybrid_call",
            "ascent_hybrid_bind",
            "ascent_hybrid_table",
        ],
    })?;
    let closure_output = graph.join("load-closure.json");
    let result = runtime
        .stage_package_load_closure(
            &[":gerbil-ascent/rules/func", ":gerbil-ascent/rules/module"],
            closure_output.to_str().ok_or("UTF8 closure path")?,
        )
        .map_err(|error| error.to_string())?;
    if result != 0 {
        return Err(format!("native module closure failed with result {result}"));
    }
    let closure: ModuleClosure = serde_json::from_slice(
        &fs::read(graph.join("load-closure.json")).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    let sdk = gsc
        .parent()
        .and_then(Path::parent)
        .ok_or("invalid GSC path")?
        .join("lib");
    let prefix =
        std::env::var_os("GERBIL_PATH").ok_or("native package environment missing GERBIL_PATH")?;
    let application = Path::new(&prefix).join("lib");
    let stage = out.join(format!("instance-stage-{}", std::process::id()));
    let manifest = stage_module_closure(
        &stage,
        &closure,
        &[
            ModuleRoot {
                source: &application,
                destination: "_owners/application/lib",
            },
            ModuleRoot {
                source: &sdk,
                destination: "_owners/sdk/lib",
            },
        ],
        &[ResourceTree::file(
            &image,
            "_owners/image/ascent-instance.dylib",
        )],
    )
    .map_err(|e| e.to_string())?;
    let package = out.join("instance-package");
    manifest
        .verify(&stage)
        .and_then(|p| p.publish_to(&package))
        .map_err(|e| e.to_string())?;
    fs::write(
        out.join("instance_inventory.json"),
        serde_json::to_vec(&manifest).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    println!(
        "cargo:rustc-env=ASCENT_INSTANCE_PACKAGE={}",
        package.display()
    );
    println!("cargo::metadata=instance_package={}", package.display());
    Ok(())
}
