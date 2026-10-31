//! The upstream compiler owns graph and archive construction.
fn main() {
    ascent_build::build().expect("prepare ASCENT Scheme archive");
}
