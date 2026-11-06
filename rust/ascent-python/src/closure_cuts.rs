//! Thin owned ABI calls to the existing compressed closure and cut algorithms.
use crate::rust_api::{Owner, error, request_bound};
use gerbil_scheme_python::{OwnedValue, ValueLimits, c_abi::ForeignCallable};
use pyo3::{Bound, Py, PyAny, PyRef, PyResult, Python, pyclass, pymethods};
use std::{cell::Cell, collections::BTreeMap, rc::Rc};

fn packet(method: &str, fields: impl IntoIterator<Item = (String, OwnedValue)>) -> OwnedValue {
    let mut values = BTreeMap::from([("method".into(), OwnedValue::Text(method.into()))]);
    values.extend(fields);
    OwnedValue::Map(values)
}
fn invoke(
    owner: &ForeignCallable,
    host: &gerbil_ascent::Engine,
    input: &OwnedValue,
) -> PyResult<OwnedValue> {
    if host.is_closed() {
        return Err(error(gerbil_ascent::Error::Closed));
    }
    request_bound(host.request_limit(), input)?;
    let result = owner
        .call(input)
        .map_err(error)?
        .decode(ValueLimits::default())
        .map_err(error)?;
    let OwnedValue::Map(mut fields) = result else {
        return Err(error("Core ABI packet required"));
    };
    if fields.remove("ok") != Some(OwnedValue::Boolean(true)) {
        return Err(error(format!("{:?}", fields.remove("error"))));
    }
    fields
        .remove("value")
        .ok_or_else(|| error("Core ABI value required"))
}

#[pyclass(unsendable, name = "Reachability")]
pub(super) struct Closure {
    owner: Rc<ForeignCallable>,
    host: gerbil_ascent::Engine,
    closed: Cell<bool>,
}
impl Closure {
    pub(super) fn open(host: &Owner) -> PyResult<Self> {
        host.0.admit_source().map_err(error)?;
        let captures = OwnedValue::Map(BTreeMap::new());
        request_bound(host.0.request_limit(), &captures)?;
        Ok(Self {
            owner: Rc::new(ascent_c_abi::open_reachability(&captures).map_err(error)?),
            host: host.0.clone(),
            closed: Cell::new(false),
        })
    }
    fn call(
        &self,
        method: &str,
        fields: impl IntoIterator<Item = (String, OwnedValue)>,
    ) -> PyResult<OwnedValue> {
        if self.closed.get() {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        invoke(&self.owner, &self.host, &packet(method, fields))
    }
}
#[pymethods]
impl Closure {
    #[pyo3(signature=(edge,*,budget=usize::MAX))]
    fn insert(&self, edge: &Bound<'_, PyAny>, budget: usize) -> PyResult<usize> {
        let OwnedValue::Integer(value) = self.call(
            "insert",
            [
                (
                    "edge".into(),
                    OwnedValue::from_python(edge, ValueLimits::default())?,
                ),
                ("budget".into(), OwnedValue::Integer(budget.into())),
            ],
        )?
        else {
            return Err(error("integer admission count required"));
        };
        usize::try_from(value).map_err(error)
    }
    fn resources(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        self.call("resources", [])?.to_python(py)
    }
    fn validate(&self) -> PyResult<bool> {
        let OwnedValue::Boolean(value) = self.call("validate", [])? else {
            return Err(error("boolean validation required"));
        };
        Ok(value)
    }
    fn freeze(&self) -> PyResult<Cut> {
        let id = self.call("freeze", [])?.positive_usize().map_err(error)?;
        Ok(Cut {
            owner: self.owner.clone(),
            host: self.host.clone(),
            id,
            closed: Cell::new(false),
        })
    }
    fn close(&self) -> PyResult<()> {
        if !self.closed.get() && !self.host.is_closed() {
            self.call("close-state", [])?;
        }
        self.closed.set(true);
        Ok(())
    }
    fn __enter__(slf: PyRef<'_, Self>) -> PyRef<'_, Self> {
        slf
    }
    fn __exit__(
        &self,
        _ty: &Bound<'_, PyAny>,
        _value: &Bound<'_, PyAny>,
        _traceback: &Bound<'_, PyAny>,
    ) -> PyResult<()> {
        self.close()
    }
}

#[pyclass(unsendable, name = "ReachabilitySnapshot")]
pub(super) struct Cut {
    owner: Rc<ForeignCallable>,
    host: gerbil_ascent::Engine,
    id: usize,
    closed: Cell<bool>,
}
impl Cut {
    fn call(
        &self,
        method: &str,
        fields: impl IntoIterator<Item = (String, OwnedValue)>,
    ) -> PyResult<OwnedValue> {
        if self.closed.get() {
            return Err(error(gerbil_ascent::Error::Closed));
        }
        invoke(
            &self.owner,
            &self.host,
            &packet(
                method,
                std::iter::once(("cut".into(), OwnedValue::Integer(self.id.into()))).chain(fields),
            ),
        )
    }
}
#[pymethods]
impl Cut {
    #[pyo3(signature=(columns=None,key=None,*,limit=usize::MAX))]
    fn rows(
        &self,
        py: Python<'_>,
        columns: Option<Vec<usize>>,
        key: Option<&Bound<'_, PyAny>>,
        limit: usize,
    ) -> PyResult<Py<PyAny>> {
        let columns = OwnedValue::List(
            columns
                .unwrap_or_default()
                .into_iter()
                .map(|v| OwnedValue::Integer(v.into()))
                .collect(),
        );
        let key = key
            .map(|v| OwnedValue::from_python(v, ValueLimits::default()))
            .transpose()?
            .unwrap_or(OwnedValue::List(vec![]));
        self.call(
            "rows",
            [
                ("columns".into(), columns),
                ("key".into(), key),
                ("limit".into(), OwnedValue::Integer(limit.into())),
            ],
        )?
        .to_python(py)
    }
    fn contains(&self, row: &Bound<'_, PyAny>) -> PyResult<bool> {
        let OwnedValue::Boolean(value) = self.call(
            "contains",
            [(
                "row".into(),
                OwnedValue::from_python(row, ValueLimits::default())?,
            )],
        )?
        else {
            return Err(error("boolean membership required"));
        };
        Ok(value)
    }
    #[pyo3(signature=(other,*,budget=usize::MAX))]
    fn difference(&self, py: Python<'_>, other: &Self, budget: usize) -> PyResult<Py<PyAny>> {
        if other.closed.get() || !Rc::ptr_eq(&self.owner, &other.owner) {
            return Err(error("released or foreign cut owner"));
        }
        self.call(
            "difference",
            [
                ("other".into(), OwnedValue::Integer(other.id.into())),
                ("budget".into(), OwnedValue::Integer(budget.into())),
            ],
        )?
        .to_python(py)
    }
    fn resources(&self, py: Python<'_>) -> PyResult<Py<PyAny>> {
        self.call("cut-resources", [])?.to_python(py)
    }
    fn close(&self) -> PyResult<()> {
        if !self.closed.get() && !self.host.is_closed() {
            self.call("release-cut", [])?;
        }
        self.closed.set(true);
        Ok(())
    }
    fn __enter__(slf: PyRef<'_, Self>) -> PyRef<'_, Self> {
        slf
    }
    fn __exit__(
        &self,
        _ty: &Bound<'_, PyAny>,
        _value: &Bound<'_, PyAny>,
        _traceback: &Bound<'_, PyAny>,
    ) -> PyResult<()> {
        self.close()
    }
}
