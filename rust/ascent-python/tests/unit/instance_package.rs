//! Python calls the Rust snapshot and pool API; Rust owns all semantic assertions.
use super::{InstancePackage, InstancePool};
use pyo3::types::{PyDict, PyDictMethods};
use pyo3::{Py, PyResult, Python, types::PyAnyMethods};

#[test]
fn python_pools_retain_shared_package_after_its_python_owner_is_dropped() {
    let captured = ascent_scheme::InstancePackage::bundled().unwrap();
    Python::initialize();
    Python::attach(|py| -> PyResult<()> {
        let package = Py::new(py, InstancePackage(captured))?;
        let keywords = PyDict::new(py);
        keywords.set_item("package", &package)?;
        let kind = py.get_type::<InstancePool>();
        let first = kind.call((1,), Some(&keywords))?;
        let second = kind.call((1,), Some(&keywords))?;
        drop(keywords);
        drop(package);
        let retired = first.call_method0("shutdown")?;
        assert_eq!(retired.get_item("joined")?.extract::<usize>()?, 1);
        assert_eq!(retired.get_item("pending")?.extract::<usize>()?, 0);
        let engine = second.call_method1("engine", (0,))?;
        let trust = PyDict::new(py);
        trust.set_item("trusted", true)?;
        let module = engine.call_method("dsl", ("(def (answer) (+ 40 2))",), Some(&trust))?;
        let answer = module.call_method1("call", ("answer",))?;
        let observed = answer
            .getattr("graph")?
            .get_item("root")?
            .get_item("value")?
            .extract::<String>()?;
        assert_eq!(observed, "42");
        answer.call_method0("close")?;
        module.call_method0("close")?;
        engine.call_method0("shutdown")?;
        let retired = second.call_method0("shutdown")?;
        for (field, wanted) in [("joined", 1), ("pending", 0), ("panicked", 0)] {
            assert_eq!(retired.get_item(field)?.extract::<usize>()?, wanted);
        }
        Ok(())
    })
    .unwrap();
}
