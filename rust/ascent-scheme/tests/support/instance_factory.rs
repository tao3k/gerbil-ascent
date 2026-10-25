//! Independent VM-owner frontend for the unchanged shared semantic cases.
pub(crate) fn engine(threads: usize) -> gerbil_ascent::Result<ascent_scheme::Engine> {
    let pool = ascent_scheme::InstancePool::new(1)?;
    Ok(ascent_scheme::Engine::new(threads)?.on_instance(pool.owner(0)?))
}

/// Captured files are shared; every call still creates a fresh VM and engine.
pub(crate) fn engines() -> impl Fn(usize) -> gerbil_ascent::Result<ascent_scheme::Engine> {
    let package = ascent_scheme::InstancePackage::bundled();
    move |threads| {
        let package = package.as_ref().map_err(Clone::clone)?;
        let pool = ascent_scheme::InstancePool::from_snapshot(1, package)?;
        Ok(ascent_scheme::Engine::new(threads)?.on_instance(pool.owner(0)?))
    }
}
