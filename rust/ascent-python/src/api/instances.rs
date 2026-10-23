//! `PyO3` leases preserve the same upstream single-thread VM owner affinity.
use super::bindings::{Engine, identities};
use gerbil_ascent::Data;
use pyo3::{
    Bound, Py, PyAny, PyResult, Python, exceptions::PyValueError, pyclass, pymethods,
    types::PyAnyMethods,
};
use std::time::Duration;
#[pyclass(name = "InstancePool", frozen)]
pub(super) struct InstancePool(ascent_scheme::InstancePool);
#[pymethods]
impl InstancePool {
    #[new]
    #[pyo3(signature=(owners=12))]
    fn new(py: Python<'_>, owners: usize) -> PyResult<Self> {
        let file = py
            .import("ascent")?
            .getattr("__file__")?
            .extract::<std::path::PathBuf>()?;
        let root = file
            .parent()
            .ok_or_else(|| PyValueError::new_err("installed package parent required"))?;
        py.detach(|| ascent_scheme::InstancePool::from_package(owners, root))
            .map(Self)
            .map_err(super::types::source_error)
    }
    #[pyo3(signature=(index, workers=1, *, max_source_scopes=None, max_input_bytes=None, backend=None, work_distribution="adaptive"))]
    fn engine(
        &self,
        index: usize,
        workers: usize,
        max_source_scopes: Option<&Bound<'_, PyAny>>,
        max_input_bytes: Option<&Bound<'_, PyAny>>,
        backend: Option<&str>,
        work_distribution: &str,
    ) -> PyResult<Engine> {
        let owner = self.0.owner(index).map_err(super::types::source_error)?;
        let engine = Engine::new(
            Some(workers),
            max_source_scopes,
            max_input_bytes,
            backend,
            work_distribution,
        )?;
        Ok(Engine(engine.0.on_instance(owner)))
    }
    fn identities(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        identities(py, self.0.receipts())
    }
    #[pyo3(signature=(timeout_seconds=30.0))]
    fn shutdown(&self, py: Python<'_>, timeout_seconds: f64) -> PyResult<Py<PyAny>> {
        let timeout = Duration::try_from_secs_f64(timeout_seconds)
            .map_err(|_| PyValueError::new_err("timeout must be finite and nonnegative"))?;
        let receipt = py
            .detach(|| self.0.shutdown(timeout))
            .map_err(super::types::source_error)?;
        super::packets::write(
            py,
            &Data::object([
                ("joined", Data::from(receipt.joined)),
                ("pending", Data::from(receipt.pending)),
                ("panicked", Data::from(receipt.panicked)),
                (
                    "owners",
                    Data::List(
                        receipt
                            .owners
                            .into_iter()
                            .map(|owner| {
                                Data::object([
                                    ("owner", Data::from(owner.owner)),
                                    (
                                        "roots_before_cleanup",
                                        Data::Integer(owner.roots_before_cleanup.into()),
                                    ),
                                    ("status", Data::Integer(owner.status.into())),
                                ])
                            })
                            .collect(),
                    ),
                ),
            ]),
        )
    }
}
