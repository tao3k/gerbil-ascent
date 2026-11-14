//! Public relational frontends; application objects belong to POO Flow.
use pyo3::{
    Bound, PyResult,
    types::{PyAnyMethods, PyModule, PyModuleMethods},
    wrap_pyfunction,
};
pub(super) fn install(root: &Bound<'_, PyModule>) -> PyResult<()> {
    let module = PyModule::new(root.py(), "ascent.datalog")?;
    module.add_function(wrap_pyfunction!(super::datalog::read_datalog, &module)?)?;
    module.add_function(wrap_pyfunction!(super::datalog::evaluate_datalog, &module)?)?;
    root.py()
        .import("sys")?
        .getattr("modules")?
        .set_item("ascent.datalog", &module)?;
    root.add("datalog", module)
}
