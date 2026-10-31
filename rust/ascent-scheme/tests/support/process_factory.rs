//! Ordinary process-owner frontend for the shared semantic cases.
pub(crate) fn engine(threads: usize) -> gerbil_ascent::Result<ascent_scheme::Engine> {
    ascent_scheme::Engine::new(threads)
}

pub(crate) fn engines() -> impl Fn(usize) -> gerbil_ascent::Result<ascent_scheme::Engine> {
    engine
}
