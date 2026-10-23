//! Independent VM-owner frontend for the unchanged shared semantic cases.
pub(crate) fn engine(threads: usize) -> gerbil_ascent::Result<ascent_scheme::Engine> {
    let pool = ascent_scheme::InstancePool::new(1)?;
    Ok(ascent_scheme::Engine::new(threads)?.on_instance(pool.owner(0)?))
}
