//! Initialize the canonical upstream image; all bindings execute on its owner.
use super::{InstancePackage, bridge_error};
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
) -> Result<(gerbil_scheme::instances::InstancePool, Vec<PathBuf>)> {
    let (snapshot, package) = crate::diagnostics::Trace::new(0, 0)
        .measure("instance-package-capture", || {
            InstancePackage::capture(root)
        })?;
    start_verified(owners, &package, snapshot.resources()?)
}
pub(super) fn start_snapshot(
    owners: usize,
    snapshot: &InstancePackage,
) -> Result<(gerbil_scheme::instances::InstancePool, Vec<PathBuf>)> {
    // The snapshot retains bytes, not a previous verification decision.
    let package = crate::diagnostics::Trace::new(0, 0)
        .measure("instance-package-verify", || snapshot.verify())?;
    start_verified(owners, &package, snapshot.resources()?)
}
fn start_verified(
    owners: usize,
    package: &gerbil_scheme_python::VerifiedPackage,
    resources: &Arc<tempfile::TempDir>,
) -> Result<(gerbil_scheme::instances::InstancePool, Vec<PathBuf>)> {
    // SAFETY: the build-owned image contains this exact Scheme archive and upstream adapter.
    let program = unsafe {
        IsolatedProgram::from_image(
            package.root().join("_owners/image/ascent-instance.dylib"),
            c"ascent_hybrid_call",
        )
        .map_err(bridge_error)?
        .with_exports(&[c"ascent_hybrid_bind", c"ascent_hybrid_table"])
    };
    let mut runtime = crate::diagnostics::Trace::new(0, 0).measure("instance-vm-setup", || {
        gerbil_scheme::instances::InstancePool::start(
            &program,
            InstanceConfig {
                owners,
                queue_capacity: 64,
                maximum_request_bytes: 64 * 1024 * 1024,
                maximum_reply_bytes: 64 * 1024 * 1024,
                startup_timeout: Duration::from_mins(1),
            },
        )
        .map_err(bridge_error)
    })?;
    if runtime.owners().iter().any(|r| r.processors != 1) {
        return Err(crate::failure(
            "each instance VM must have exactly one processor",
        ));
    }
    runtime
        .retain_owner_resource(resources)
        .map_err(bridge_error)?;
    Ok((runtime, package.load_paths()))
}
pub(super) fn bind(
    dispatcher: &InstanceDispatcher,
    index: usize,
    libraries: &[PathBuf],
) -> Result<()> {
    let libraries = libraries
        .iter()
        .map(|path| {
            path.to_str()
                .map(str::to_owned)
                .ok_or_else(|| crate::failure("non-UTF8 instance resource path"))
        })
        .collect::<Result<Vec<_>>>()?;
    let bound = dispatcher
        .submit_native_on(index, move |vm| {
            let address = crate::ascent_hybrid_checkpoint as *const () as usize;
            let (_, bytes) = num_bigint::BigInt::from(address).to_bytes_le();
            let address = vm.big_integer(
                &gerbil_scheme::BinaryInteger::new(false, bytes)
                    .map_err(|_| InstanceError::InvalidConfig("callback address"))?,
            )?;
            let strings = libraries
                .iter()
                .map(|path| vm.string(path))
                .collect::<std::result::Result<Vec<_>, _>>()?;
            let paths = vm.list(&strings.iter().collect::<Vec<_>>())?;
            let input = vm.vector(&[&address, &paths])?;
            drop(vm.call_export(c"ascent_hybrid_bind", &input)?);
            Ok(())
        })
        .map_err(bridge_error)?;
    crate::diagnostics::Trace::new(index as u64, 0)
        .measure("instance-source-context-bind", || {
            bound.wait(Duration::from_mins(1)).map_err(bridge_error)
        })?;
    Ok(())
}
