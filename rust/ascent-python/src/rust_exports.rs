//! Public evidence interfaces reuse the existing Rust-owned implementations.
use pyo3::{
    Bound, PyResult,
    types::{PyAnyMethods, PyModule, PyModuleMethods},
    wrap_pyfunction,
};

fn publish(root: &Bound<'_, PyModule>, child: &Bound<'_, PyModule>) -> PyResult<()> {
    root.py()
        .import("sys")?
        .getattr("modules")?
        .set_item(child.name()?, child)
}
pub(super) fn install(root: &Bound<'_, PyModule>) -> PyResult<()> {
    let derivations = PyModule::new(root.py(), "ascent.derivations")?;
    derivations.add_class::<super::derivations::EvidenceChain>()?;
    derivations.add_function(wrap_pyfunction!(
        super::derivations::components,
        &derivations
    )?)?;
    derivations.add_function(wrap_pyfunction!(
        super::derivations::canonical_rule,
        &derivations
    )?)?;
    derivations.add_function(wrap_pyfunction!(
        super::derivations::evidence_graph,
        &derivations
    )?)?;
    derivations.add_function(wrap_pyfunction!(
        super::derivations::normalize_contract,
        &derivations
    )?)?;
    derivations.add_function(wrap_pyfunction!(
        super::derivations::check_continuation,
        &derivations
    )?)?;
    derivations.add_function(wrap_pyfunction!(
        super::derivations::slice_program,
        &derivations
    )?)?;
    publish(root, &derivations)?;
    root.add("derivations", derivations)?;
    let trajectory = PyModule::new(root.py(), "ascent.trajectory")?;
    trajectory.add_class::<super::trajectory::Trajectory>()?;
    publish(root, &trajectory)?;
    root.add("trajectory", trajectory)?;
    interaction(root)?;
    memory(root)?;
    Ok(())
}
fn interaction(root: &Bound<'_, PyModule>) -> PyResult<()> {
    let module = PyModule::new(root.py(), "ascent.interaction")?;
    module.add_class::<super::interaction::EvidenceOperation>()?;
    module.add_class::<super::interaction::EvidenceInteraction>()?;
    module.add_class::<super::evidence_conversation::EvidenceConversation>()?;
    module.add_function(wrap_pyfunction!(
        super::interaction::compact_feedback,
        &module
    )?)?;
    module.add_function(wrap_pyfunction!(
        super::interaction::expand_feedback,
        &module
    )?)?;
    publish(root, &module)?;
    root.add("interaction", module)?;
    let module = PyModule::new(root.py(), "ascent.conversation")?;
    module.add_class::<super::conversation::ResponseHistory>()?;
    publish(root, &module)?;
    root.add("conversation", module)
}
fn memory(root: &Bound<'_, PyModule>) -> PyResult<()> {
    let module = PyModule::new(root.py(), "ascent.domain")?;
    module.add_class::<super::domain::DomainEvidence>()?;
    module.add_function(wrap_pyfunction!(super::derivations::domain_check, &module)?)?;
    module.add_function(wrap_pyfunction!(
        super::derivations::domain_contract,
        &module
    )?)?;
    module.add_function(wrap_pyfunction!(
        super::domain::domain_checker_version,
        &module
    )?)?;
    publish(root, &module)?;
    root.add("domain", module)?;
    let module = PyModule::new(root.py(), "ascent.review")?;
    module.add_class::<super::review::EvidenceReview>()?;
    module.add_function(wrap_pyfunction!(super::review::review_sources, &module)?)?;
    publish(root, &module)?;
    root.add("review", module)
}
pub(super) fn evidence(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<super::derivations::EvidenceStore>()?;
    module.add_function(wrap_pyfunction!(super::derivations::rows_equal, module)?)?;
    module.add_function(wrap_pyfunction!(
        super::derivations::compact_observation,
        module
    )?)?;
    module.add_function(wrap_pyfunction!(
        super::derivations::expand_observation,
        module
    )?)?;
    Ok(())
}
