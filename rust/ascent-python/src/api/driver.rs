//! Rust owns execution, clocks and complete-result comparison; Python invokes it.
use super::{
    declarations::Program,
    types::{Cancellation, error, value},
};
use gerbil_ascent::{Engine, Limits, Row};
use pyo3::{
    Py, PyAny, PyRef, PyResult, Python,
    exceptions::{PyAssertionError, PyValueError},
    pyclass, pymethods,
};
use std::{
    collections::BTreeMap,
    time::{Duration, Instant},
};

type Inputs = BTreeMap<String, Vec<Vec<Py<PyAny>>>>;
fn owned(py: Python<'_>, input: Inputs) -> PyResult<BTreeMap<String, Vec<Row>>> {
    input
        .into_iter()
        .map(|(name, rows)| {
            rows.into_iter()
                .map(|row| {
                    row.into_iter()
                        .map(|cell| value(cell.bind(py)))
                        .collect::<PyResult<Vec<_>>>()
                        .map(Into::into)
                })
                .collect::<PyResult<Vec<_>>>()
                .map(|rows| (name, rows))
        })
        .collect()
}
#[pyclass(name = "VerificationSample", frozen)]
pub(super) struct Observation {
    #[pyo3(get)]
    workers: usize,
    #[pyo3(get)]
    sample: usize,
    #[pyo3(get)]
    elapsed_ns: u128,
    #[pyo3(get)]
    facts: usize,
}
#[pyclass(name = "VerificationCase", frozen)]
pub(super) struct Case {
    program: gerbil_ascent::Program,
    sources: BTreeMap<String, Vec<Row>>,
    expected: BTreeMap<String, Vec<Row>>,
}
#[pymethods]
impl Case {
    #[new]
    fn new(
        py: Python<'_>,
        program: PyRef<'_, Program>,
        sources: Inputs,
        expected: Inputs,
    ) -> PyResult<Self> {
        let mut expected = owned(py, expected)?;
        for rows in expected.values_mut() {
            rows.sort_unstable();
            rows.dedup();
        }
        let declaration = program.0.clone();
        drop(program);
        Ok(Self {
            program: declaration,
            sources: owned(py, sources)?,
            expected,
        })
    }
    #[pyo3(signature = (workers, samples=7, limits=None, cancellation=None))]
    fn run(
        &self,
        py: Python<'_>,
        workers: Vec<usize>,
        samples: usize,
        limits: Option<PyRef<'_, RunLimits>>,
        cancellation: Option<PyRef<'_, Cancellation>>,
    ) -> PyResult<Vec<Observation>> {
        if workers.is_empty() || samples == 0 {
            return Err(PyValueError::new_err(
                "workers and samples must be nonempty",
            ));
        }
        let limits = limits.map(|l| l.0.clone()).unwrap_or_default();
        let cancellation = cancellation.map(|c| c.0.clone()).unwrap_or_default();
        py.detach(|| self.execute(workers, samples, &limits, &cancellation))
    }
}
impl Case {
    fn execute(
        &self,
        workers: Vec<usize>,
        samples: usize,
        limits: &Limits,
        cancellation: &gerbil_ascent::Cancellation,
    ) -> PyResult<Vec<Observation>> {
        let mut output = Vec::new();
        for threads in workers {
            let engine = Engine::new(threads).map_err(error)?;
            for sample in 0..=samples {
                let started = Instant::now();
                let mut session = engine.open(self.program.clone()).map_err(error)?;
                session
                    .replace_sources(self.sources.clone())
                    .map_err(error)?;
                let result = session.run(limits, cancellation).map_err(error)?;
                let elapsed_ns = started.elapsed().as_nanos();
                if result.relations != self.expected {
                    return Err(PyAssertionError::new_err(format!(
                        "complete result mismatch: workers={threads} sample={sample}"
                    )));
                }
                if sample != 0 {
                    output.push(Observation {
                        workers: threads,
                        sample: sample - 1,
                        elapsed_ns,
                        facts: result.relations.values().map(Vec::len).sum(),
                    });
                }
            }
        }
        Ok(output)
    }
}

#[pyclass(name = "Limits", frozen)]
pub(super) struct RunLimits(Limits);
#[pymethods]
impl RunLimits {
    #[new]
    #[pyo3(signature = (timeout_seconds=30.0, max_facts=1_000_000, max_states=10_000_000))]
    fn new(timeout_seconds: f64, max_facts: usize, max_states: usize) -> PyResult<Self> {
        Ok(Self(Limits {
            timeout: Duration::try_from_secs_f64(timeout_seconds)
                .map_err(|_| PyValueError::new_err("invalid timeout"))?,
            max_facts,
            max_states,
        }))
    }
}
