//! Identity of the actual SDK-built native program, used by worker handshakes.
/// Compare worker programs without scanning installed source or runtime directories.
#[must_use]
pub fn build_identity() -> gerbil_ascent::Data {
    gerbil_ascent::Data::object([
        ("program", gerbil_ascent::Data::from("ascent_hybrid")),
        (
            "archiveSha256",
            gerbil_ascent::Data::from(env!("ASCENT_NATIVE_PROGRAM_SHA256")),
        ),
    ])
}
