//! Python package layout is generated from the Rust interface; no Python runtime fallback.
use pyo3::{
    Bound, PyResult,
    types::{PyAnyMethods, PyModule, PyModuleMethods},
};
pub(super) fn install(root: &Bound<'_, PyModule>) -> PyResult<()> {
    install_evidence(root)?;
    install_frontends(root)?;
    install_interaction(root)?;
    install_module(
        root,
        "evidence",
        &[
            "EvidenceStore",
            "ComputationalEvidence",
            "identity",
            "compact_observation",
            "expand_observation",
        ],
    )?;
    install_module(
        root,
        "derivations",
        &[
            "EvidenceChain",
            "components",
            "canonical_rule",
            "evidence_graph",
            "normalize_contract",
            "check_continuation",
            "slice_program",
        ],
    )?;
    install_module(root, "trajectory", &["Trajectory"])?;
    install_module(root, "conversation", &["ResponseHistory"])?;
    install_module(
        root,
        "domain",
        &[
            "domain_check",
            "domain_contract",
            "DomainEvidence",
            "domain_checker_version",
        ],
    )?;
    install_module(
        root,
        "operators",
        &["where", "compute", "reduce", "dependencies"],
    )?;
    install_module(root, "review", &["EvidenceReview", "review_sources"])?;
    install_module(root, "datalog", &["read_datalog", "evaluate_datalog"])?;
    Ok(())
}
fn install_module(root: &Bound<'_, PyModule>, name: &str, exports: &[&str]) -> PyResult<()> {
    let module = PyModule::new(root.py(), &format!("ascent.{name}"))?;
    for export in exports {
        module.add(*export, root.getattr(*export)?)?;
    }
    root.py()
        .import("sys")?
        .getattr("modules")?
        .set_item(format!("ascent.{name}"), &module)?;
    root.add(name, module)
}

fn install_evidence(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<super::trajectory::Trajectory>()?;
    module.add_class::<super::computational::ComputationalEvidence>()?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::compact_observation,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::expand_observation,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::domain_check,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::domain_contract,
        module
    )?)?;
    module.add_class::<super::derivations::EvidenceStore>()?;
    module.add_class::<super::derivations::EvidenceChain>()?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::rows_equal,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::identity,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::components,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::evidence_graph,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::canonical_rule,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::slice_program,
        module
    )?)?;
    Ok(())
}

fn install_frontends(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<super::conversation::ResponseHistory>()?;
    module.add_function(pyo3::wrap_pyfunction!(super::operators::predicate, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(super::operators::compute, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(super::operators::reduce, module)?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::operators::dependencies,
        module
    )?)?;
    module.add_class::<super::review::EvidenceReview>()?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::review::review_sources,
        module
    )?)?;
    module.add_class::<super::domain::DomainEvidence>()?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::domain::domain_checker_version,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::normalize_contract,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::derivations::check_continuation,
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

fn install_interaction(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<super::interaction::EvidenceOperation>()?;
    module.add_class::<super::interaction::EvidenceInteraction>()?;
    module.add_class::<super::evidence_conversation::EvidenceConversation>()?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::interaction::compact_feedback,
        module
    )?)?;
    module.add_function(pyo3::wrap_pyfunction!(
        super::interaction::expand_feedback,
        module
    )?)?;
    install_module(
        module,
        "interaction",
        &[
            "EvidenceOperation",
            "EvidenceInteraction",
            "EvidenceConversation",
            "compact_feedback",
            "expand_feedback",
        ],
    )
}
