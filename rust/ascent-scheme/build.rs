//! Reuse the upstream compiler and its observed, fingerprinted archive builder.
mod build_support;
fn main() {
    build_support::build().expect("prepare ASCENT Scheme archive");
}
