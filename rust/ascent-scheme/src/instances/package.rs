//! Caller-owned immutable input bytes; every new VM admission still reverifies.
use gerbil_ascent::Result;
use gerbil_scheme_python::{PackageManifest, VerifiedPackage};
use std::{path::Path, sync::Arc};

/// Captured library resources shared by independent VM pools, never Scheme state.
/// The caller and actual native owners jointly retain the private resource lease.
#[derive(Clone)]
pub struct InstancePackage {
    resources: Option<Arc<tempfile::TempDir>>,
    parent: u32,
    manifest: Arc<PackageManifest>,
}
impl InstancePackage {
    /// Capture the library-built package without compiling user code.
    /// # Errors
    /// Rejects changed, missing or aliased resources before capturing any VM.
    pub fn bundled() -> Result<Self> {
        Self::open(env!("ASCENT_INSTANCE_PACKAGE"))
    }
    /// Capture an installed package matching this library's compiled manifest.
    /// # Errors
    /// Rejects invalid resources and any source change during the verified copy.
    pub fn open(root: impl AsRef<Path>) -> Result<Self> {
        Self::capture(root.as_ref()).map(|(package, _)| package)
    }
    pub(super) fn capture(root: &Path) -> Result<(Self, VerifiedPackage)> {
        let manifest = Arc::new(
            PackageManifest::from_json(include_bytes!(concat!(
                env!("OUT_DIR"),
                "/instance_inventory.json"
            )))
            .map_err(|e| crate::failure(&e.to_string()))?,
        );
        let package = manifest
            .verify(root)
            .map_err(|e| crate::failure(&e.to_string()))?;
        let resources = Arc::new(
            tempfile::Builder::new()
                .prefix(&format!("ascent-resources-{}-", std::process::id()))
                .tempdir()
                .map_err(|e| crate::failure(&e.to_string()))?,
        );
        let verified = package
            .copy_to(resources.path())
            .map_err(|e| crate::failure(&e.to_string()))?;
        Ok((
            Self {
                resources: Some(resources),
                parent: std::process::id(),
                manifest,
            },
            verified,
        ))
    }
    pub(super) fn resources(&self) -> Result<&Arc<tempfile::TempDir>> {
        if self.parent != std::process::id() {
            return Err(crate::failure(
                "forked package resources require exec before initialization",
            ));
        }
        self.resources.as_ref().ok_or(gerbil_ascent::Error::Closed)
    }
    pub(super) fn verify(&self) -> Result<VerifiedPackage> {
        self.manifest
            .verify(self.resources()?.path())
            .map_err(|e| crate::failure(&e.to_string()))
    }
}

impl Drop for InstancePackage {
    fn drop(&mut self) {
        // A child inherited a process-local lease, not ownership of the parent's
        // files. Never remove those files while the parent may still use them.
        if self.parent == std::process::id() {
            return;
        }
        if let Some(resources) = self.resources.take() {
            std::mem::forget(resources);
        }
    }
}

#[cfg(test)]
#[path = "../../tests/unit/instance_package.rs"]
mod tests;
