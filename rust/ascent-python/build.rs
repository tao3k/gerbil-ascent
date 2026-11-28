//! Stage Library sources and use `PyO3`'s standard extension linker configuration.
fn main() {
    if cfg!(feature = "extension-module") {
        pyo3_build_config::add_extension_module_link_args();
    }
    ascent_build::stage_python_sources();
}
