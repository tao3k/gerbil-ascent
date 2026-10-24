//! Primitive rule-language and operator bindings only.
use pyo3::{
    Bound, PyResult,
    types::{PyModule, PyModuleMethods},
};
pub(super) fn install(module: &Bound<'_, PyModule>) -> PyResult<()> {
    super::artifacts::install(module)?;
    module.add_function(pyo3::wrap_pyfunction!(super::operators::predicate, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(super::operators::compute, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(super::operators::reduce, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::operators::dependencies,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::datalog::read_datalog,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::datalog::evaluate_datalog,
        module
    )?)?;
    Ok(())
}
