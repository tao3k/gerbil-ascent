//! Publish the dependency's verified runtime assets through the upstream package owner.
use gerbil_scheme_python::PackageManifest;
use std::{env, fs, path::PathBuf};
pub(super) fn stage() -> Result<(), String> {
    let source = PathBuf::from(
        env::var_os("DEP_ASCENT_SCHEME_PROGRAM_INSTANCE_PACKAGE")
            .ok_or("missing instance package dependency metadata")?,
    );
    let manifest = PackageManifest::from_json(
        &fs::read(source.join(".gerbil-resources.json")).map_err(|e| e.to_string())?,
    )
    .map_err(|e| e.to_string())?;
    let target =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").ok_or("missing package directory")?)
            .join("../../python/src/ascent");
    for name in manifest.files.keys() {
        println!("cargo:rerun-if-changed={}", source.join(name).display());
    }
    manifest
        .verify(&source)
        .and_then(|v| v.publish_to(&target))
        .map_err(|e| e.to_string())?;
    Ok(())
}
