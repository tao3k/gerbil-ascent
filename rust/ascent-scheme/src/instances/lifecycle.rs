//! Initialize the canonical upstream image; all bindings execute on its owner.
use super::bridge_error;
use gerbil_ascent::Result;
use gerbil_scheme::instances::{
    InstanceConfig, InstanceDispatcher, InstanceError, IsolatedProgram,
};
use std::{
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};
pub(super) fn start(
    owners: usize,
    root: &Path,
) -> Result<(gerbil_scheme::instances::InstancePool, PathBuf)> {
    let manifest = gerbil_scheme_python::PackageManifest::from_json(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/instance_inventory.json"
    )))
    .map_err(|e| crate::failure(&e.to_string()))?;
    let package = manifest
        .verify(root)
        .map_err(|e| crate::failure(&e.to_string()))?;
    let resources = Arc::new(
        tempfile::Builder::new()
            .prefix(&format!("ascent-resources-{}-", std::process::id()))
            .tempdir()
            .map_err(|e| crate::failure(&e.to_string()))?,
    );
    let package = package
        .copy_to(resources.path())
        .map_err(|e| crate::failure(&e.to_string()))?;
    // SAFETY: the build-owned image contains this exact Scheme archive and upstream adapter.
    let program = unsafe {
        IsolatedProgram::from_image(
            package.root().join("_owners/ascent-instance.dylib"),
            c"ascent_hybrid_call",
        )
        .map_err(bridge_error)?
        .with_exports(&[c"ascent_hybrid_bind", c"ascent_hybrid_table"])
    };
    let mut runtime = gerbil_scheme::instances::InstancePool::start(
        &program,
        InstanceConfig {
            owners,
            queue_capacity: 64,
            maximum_request_bytes: 64 * 1024 * 1024,
            maximum_reply_bytes: 64 * 1024 * 1024,
            startup_timeout: Duration::from_secs(60),
        },
    )
    .map_err(bridge_error)?;
    if runtime.owners().iter().any(|r| r.processors != 1) {
        return Err(crate::failure(
            "each instance VM must have exactly one processor",
        ));
    }
    runtime
        .retain_owner_resource(&resources)
        .map_err(bridge_error)?;
    Ok((runtime, package.root().join("_owners/lib")))
}
pub(super) fn bind(dispatcher: &InstanceDispatcher, index: usize, library: &Path) -> Result<()> {
    let library = library
        .to_str()
        .ok_or_else(|| crate::failure("non-UTF8 instance resource path"))?
        .to_owned();
    let bound = dispatcher
        .submit_native_on(index, move |vm| {
            let address = crate::ascent_hybrid_checkpoint as *const () as usize;
            let (_, bytes) = num_bigint::BigInt::from(address).to_bytes_le();
            let address = vm.big_integer(
                &gerbil_scheme::BinaryInteger::new(false, bytes)
                    .map_err(|_| InstanceError::InvalidConfig("callback address"))?,
            )?;
            let library = vm.string(&library)?;
            let input = vm.vector(&[&address, &library])?;
            drop(vm.call_export(c"ascent_hybrid_bind", &input)?);
            Ok(())
        })
        .map_err(bridge_error)?;
    bound.wait(Duration::from_secs(60)).map_err(bridge_error)?;
    Ok(())
}
