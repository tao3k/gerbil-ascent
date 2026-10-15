//! Artifact source identities frozen by the actual library build.
include!(concat!(env!("OUT_DIR"), "/compiled_identity.rs"));
include!(concat!(env!("OUT_DIR"), "/runtime_identity.rs"));
/// Inspect inputs compiled into this library, without entering Scheme or compiling anything.
#[must_use]
pub fn build_identity() -> gerbil_ascent::Data {
    gerbil_ascent::Data::object([
        ("schema", gerbil_ascent::Data::from("ascent.rust-build.v1")),
        ("sourceInputs", compiled_inputs()),
        ("runtimeInputs", runtime_inputs()),
        ("rayon", gerbil_ascent::Data::Bool(cfg!(feature = "rayon"))),
    ])
}
