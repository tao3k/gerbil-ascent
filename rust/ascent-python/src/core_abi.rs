//! Thin Python owner over fixed Core C exports; no algorithm or source evaluation.
use gerbil_scheme_python::{
    OwnedValue, ValueLimits,
    c_abi::{ForeignCallable, ForeignValue},
};
use pyo3::{
    Bound, Py, PyAny, PyRef, PyResult, Python,
    pyclass, pymethods,
    types::{PyModule, PyModuleMethods},
};
use std::{cell::RefCell, collections::BTreeMap, time::Instant};
fn failure(error: impl std::fmt::Display) -> pyo3::PyErr {
    crate::rust_api::EngineError::new_err(error.to_string())
}
fn packet<const N: usize>(fields: [(&str, OwnedValue); N]) -> OwnedValue {
    OwnedValue::Map(fields.into_iter().map(|(k, v)| (k.to_owned(), v)).collect())
}
fn text(value: &str) -> OwnedValue {
    OwnedValue::Text(value.to_owned())
}
fn ceiling(value: Option<usize>) -> OwnedValue {
    value.map_or(OwnedValue::Null, |v| OwnedValue::Integer(v.into()))
}

#[pyclass(unsendable, name = "CoreSession")]
pub(crate) struct CoreSession {
    callable: ForeignCallable,
    host: gerbil_ascent::Engine,
    diagnostics: bool,
}
impl CoreSession {
    pub(crate) fn open_graph(
        host: gerbil_ascent::Engine,
        graph: &Bound<'_, PyAny>,
        limits: gerbil_ascent::FactLimits,
        diagnostics: bool,
    ) -> PyResult<Self> {
        if host.is_closed() { return Err(failure("engine closed")); }
        let input = packet([
            ("graph", OwnedValue::from_python(graph, ValueLimits::default())?),
            ("workers", OwnedValue::Integer(host.threads().into())),
            ("diagnostics", OwnedValue::Boolean(diagnostics)),
            ("limits", packet([
                ("input", ceiling(limits.input)),
                ("derived", ceiling(limits.derived)),
                ("output", ceiling(limits.output)),
            ])),
        ]);
        Ok(Self { callable: ascent_c_abi::open(&input).map_err(failure)?, host, diagnostics })
    }
    pub(crate) fn open(
        host: gerbil_ascent::Engine,
        source: &str,
        constructor: Option<&str>,
        limits: gerbil_ascent::FactLimits,
        diagnostics: bool,
    ) -> PyResult<Self> {
        Self::open_declaration(host, [("sources", OwnedValue::List(vec![text(source)]))],
            constructor, limits, diagnostics)
    }
    pub(crate) fn open_components(
        host: gerbil_ascent::Engine,
        components: &Bound<'_, PyAny>,
        entry: &str,
        constructor: Option<&str>,
        limits: gerbil_ascent::FactLimits,
        diagnostics: bool,
    ) -> PyResult<Self> {
        Self::open_declaration(host, [
            ("components", OwnedValue::from_python(components, ValueLimits::default())?),
            ("entry", text(entry)),
        ], constructor, limits, diagnostics)
    }
    fn open_declaration<const N: usize>(
        host: gerbil_ascent::Engine,
        declaration: [(&str, OwnedValue); N],
        constructor: Option<&str>,
        limits: gerbil_ascent::FactLimits,
        diagnostics: bool,
    ) -> PyResult<Self> {
        if host.is_closed() {
            return Err(failure("engine closed"));
        }
        let mut input = packet([
            ("diagnostics", OwnedValue::Boolean(diagnostics)),
            ("constructor", constructor.map_or(OwnedValue::Null, text)),
            ("workers", OwnedValue::Integer(host.threads().into())),
            (
                "limits",
                packet([
                    ("input", ceiling(limits.input)),
                    ("derived", ceiling(limits.derived)),
                    ("output", ceiling(limits.output)),
                ]),
            ),
        ]);
        if let OwnedValue::Map(fields) = &mut input {
            fields.extend(declaration.into_iter().map(|(name, value)| (name.into(), value)));
        }
        let callable = ascent_c_abi::open(&input).map_err(failure)?;
        Ok(Self {
            callable,
            host,
            diagnostics,
        })
    }
    fn invoke(&self, input: &OwnedValue) -> PyResult<CoreValue> {
        if self.host.is_closed() {
            return Err(failure("engine closed"));
        }
        let started = self.diagnostics.then(Instant::now);
        let value = self.callable.call(input).map_err(failure)?;
        let timings = started
            .map(|v| ("host.callAndInputEncode", v.elapsed().as_nanos()))
            .into_iter()
            .collect();
        Ok(CoreValue {
            value: RefCell::new(Some(value)),
            diagnostics: self.diagnostics,
            timings: RefCell::new(timings),
        })
    }
}
#[pymethods]
impl CoreSession {
    fn diagnose(&self) -> PyResult<CoreValue> {
        self.invoke(&packet([("method", text("diagnose"))]))
    }
    fn runtime(&self) -> PyResult<CoreValue> {
        self.invoke(&packet([("method", text("runtime"))]))
    }
    fn call(&self, input: &Bound<'_, PyAny>) -> PyResult<CoreValue> {
        self.invoke(&OwnedValue::from_python(input, ValueLimits::default())?)
    }
    #[pyo3(signature=(timeout_nanoseconds=1_000_000_000,*,queries=None,result_format="graph"))]
    fn run(
        &self,
        timeout_nanoseconds: u64,
        queries: Option<Vec<String>>,
        result_format: &str,
    ) -> PyResult<CoreValue> {
        self.invoke(&packet([
            ("method", text("run")),
            ("resultFormat", text(result_format)),
            (
                "timeoutNanoseconds",
                OwnedValue::Integer(timeout_nanoseconds.into()),
            ),
            (
                "queries",
                queries.map_or(OwnedValue::Null, |q| {
                    OwnedValue::List(q.into_iter().map(OwnedValue::Text).collect())
                }),
            ),
        ]))
    }
    fn describe(&self) -> PyResult<CoreValue> {
        self.invoke(&packet([("method", text("describe"))]))
    }
    fn replace(&self, sources: &Bound<'_, PyAny>) -> PyResult<CoreValue> {
        self.invoke(&packet([
            ("method", text("replace")),
            (
                "sources",
                OwnedValue::from_python(sources, ValueLimits::default())?,
            ),
        ]))
    }
    fn explanation(&self, handle: u64, query: &str) -> PyResult<CoreValue> {
        self.invoke(&packet([
            ("method", text("explain")),
            ("handle", OwnedValue::Integer(handle.into())),
            ("query", text(query)),
        ]))
    }
    fn close(&self) -> PyResult<()> {
        self.callable.close().map_err(failure)
    }
    fn __enter__(slf: PyRef<'_, Self>) -> PyRef<'_, Self> {
        slf
    }
    fn __exit__(
        &self,
        _kind: &Bound<'_, PyAny>,
        _value: &Bound<'_, PyAny>,
        _trace: &Bound<'_, PyAny>,
    ) -> PyResult<()> {
        self.close()
    }
}

#[pyclass(unsendable, name = "CoreValue")]
pub(crate) struct CoreValue {
    value: RefCell<Option<ForeignValue>>,
    diagnostics: bool,
    timings: RefCell<BTreeMap<&'static str, u128>>,
}
#[pymethods]
impl CoreValue {
    fn __enter__(slf: PyRef<'_, Self>) -> PyResult<PyRef<'_, Self>> {
        if slf.closed() { return Err(failure("result released")); }
        Ok(slf)
    }
    fn __exit__(&self, _ty: &Bound<'_, PyAny>, _value: &Bound<'_, PyAny>, _traceback: &Bound<'_, PyAny>) {
        self.close();
    }
    fn value(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        let value = self.value.borrow();
        let started = self.diagnostics.then(Instant::now);
        let value = value
            .as_ref()
            .ok_or_else(|| failure("result released"))?
            .decode(ValueLimits::default())
            .map_err(failure)?;
        if let Some(started) = started {
            self.timings
                .borrow_mut()
                .insert("host.decodeOwned", started.elapsed().as_nanos());
        }
        let OwnedValue::Map(mut fields) = value else {
            return Err(failure("Core ABI response envelope"));
        };
        match fields.remove("ok") {
            Some(OwnedValue::Boolean(true)) => {
                let value = fields
                    .remove("value")
                    .ok_or_else(|| failure("missing Core ABI result"))?;
                let started = self.diagnostics.then(Instant::now);
                let result = value.to_python(py);
                if let Some(started) = started {
                    self.timings
                        .borrow_mut()
                        .insert("host.pythonProjection", started.elapsed().as_nanos());
                }
                result
            }
            Some(OwnedValue::Boolean(false)) => Err(failure(match fields.remove("error") {
                Some(OwnedValue::Text(v)) => v,
                _ => "missing Core ABI error".into(),
            })),
            _ => Err(failure("invalid Core ABI outcome")),
        }
    }
    fn close(&self) {
        self.value.borrow_mut().take();
    }
    #[getter]
    fn closed(&self) -> bool {
        self.value.borrow().is_none()
    }
    fn diagnose(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        packet([
            ("enabled", OwnedValue::Boolean(self.diagnostics)),
            (
                "timingsNanoseconds",
                OwnedValue::Map(
                    self.timings
                        .borrow()
                        .iter()
                        .map(|(name, value)| {
                            ((*name).to_owned(), OwnedValue::Integer((*value).into()))
                        })
                        .collect(),
                ),
            ),
        ])
        .to_python(py)
    }
}
pub(crate) fn install(module: &Bound<'_, PyModule>) -> PyResult<()> {
    module.add_class::<CoreSession>()?;
    module.add_class::<CoreValue>()?;
    module.add(
        "CORE_C_ABI_VERSION",
        ascent_c_abi::ascent_core_abi_version(),
    )?;
    Ok(())
}
