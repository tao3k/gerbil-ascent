//! Package the upstream image and compiler-owned carriers without a runtime compiler.
use super::observer::Observer;
use gerbil_scheme_aot_build::{
    NativeArchiveLinkReceipt, NativeInstanceImageRequest, ProgramArchiveObserver,
    build_native_instance_image,
};
use gerbil_scheme_python::{ResourceTree, stage_resources};
use std::{
    env, fs,
    path::{Path, PathBuf},
};

pub(super) fn prepare(
    gsc: &Path,
    archive: &NativeArchiveLinkReceipt,
    prefix: &Path,
    out: &Path,
    observer: &Observer,
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
    let inputs = out.join("instance-resource-inputs");
    if inputs.exists() {
        fs::remove_dir_all(&inputs).map_err(|e| e.to_string())?;
    }
    let library = inputs.join("lib");
    stage_instance_sources(&prefix.join("lib"), &library, observer)?;
    let sdk = PathBuf::from(
        env::var_os("GERBIL_HOME").ok_or("GERBIL_HOME required for instance source carriers")?,
    )
    .join("lib");
    stage_instance_sources(&sdk, &library, observer)?;
    fs::copy(&image, inputs.join("ascent-instance.dylib")).map_err(|e| e.to_string())?;
    let stage = out.join(format!("instance-stage-{}", std::process::id()));
    let manifest = stage_resources(
        &stage,
        &[ResourceTree::complete(&inputs, "_owners")],
        &["_owners/lib".into()],
    )
    .map_err(|e| e.to_string())?;
    let package = out.join("instance-package");
    manifest
        .verify(&stage)
        .and_then(|v| v.publish_to(&package))
        .map_err(|e| e.to_string())?;
    fs::write(
        out.join("instance_inventory.json"),
        serde_json::to_vec(&manifest).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    fs::remove_dir_all(stage).map_err(|e| e.to_string())?;
    println!(
        "cargo:rustc-env=ASCENT_INSTANCE_PACKAGE={}",
        package.display()
    );
    println!("cargo::metadata=instance_package={}", package.display());
    Ok(())
}

#[cfg(feature = "instances")]
fn stage_instance_sources(
    source: &Path,
    destination: &Path,
    observer: &Observer,
) -> Result<(), String> {
    // Existing compiler-generated Scheme carriers are interpreted separately
    // by each VM. A compiled .o1 cannot be dynamically loaded into multiple VMs:
    // its C module initialization state belongs to the process. Never copy a
    // native .o1 into this source-only search directory or compile user DSL.
    std::fs::create_dir_all(destination).map_err(|e| e.to_string())?;
    for entry in std::fs::read_dir(source).map_err(|e| e.to_string())? {
        let entry = entry.map_err(|e| e.to_string())?;
        let input = entry.path();
        let output = destination.join(entry.file_name());
        if input.is_dir() {
            stage_instance_sources(&input, &output, observer)?;
        } else if input.extension().is_some_and(|e| e == "scm" || e == "ssi") {
            observer.observe_source_input(&input);
            std::fs::copy(&input, &output).map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}
