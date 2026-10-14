//! Native module/value leases; no Scheme interpretation in Rust.
use super::{Engine, Evidence, check, id, input, invoke};
use gerbil_ascent::{Data, Error, FactLimits, ObjectInput, Result, ValueReference};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

pub(super) struct Owner {
    pub engine: Engine,
    pub id: u64,
    pub closed: AtomicBool,
    components: Vec<String>,
}
impl Owner {
    pub fn check(&self) -> Result<()> {
        check(&self.engine, self.closed.load(Ordering::Acquire))
    }
    fn close(&self) {
        if !self.closed.swap(true, Ordering::AcqRel) {
            let _ = invoke("module-close", [("owner", Data::from(self.id))]);
        }
    }
}
impl Drop for Owner {
    fn drop(&mut self) {
        self.close();
    }
}
/// Shared native lexical scope. Closing revokes its public value leases.
#[derive(Clone)]
pub struct Module(pub(super) Arc<Owner>);
impl Module {
    pub(super) fn new(engine: &Engine, result: Data) -> Result<Self> {
        let components = result
            .get("components")
            .map(|v| {
                v.list()?
                    .iter()
                    .map(|v| v.text().map(str::to_string))
                    .collect::<Result<Vec<_>>>()
            })
            .transpose()?
            .unwrap_or_default();
        Ok(Self(Arc::new(Owner {
            engine: engine.clone(),
            id: id(&result, "owner")?,
            closed: AtomicBool::new(false),
            components,
        })))
    }
    /// Call a public native export in its current lexical environment.
    /// # Errors
    /// Rejects closed owners, invalid arguments and native execution failures.
    pub fn call(
        &self,
        export: &str,
        arguments: &[ObjectInput],
        component: Option<&str>,
    ) -> Result<ModuleValue> {
        self.invoke(export, arguments, component, None)
    }
    /// Resolve a named module's native public export in this value scope.
    /// # Errors
    /// Rejects invalid exports, references and closed owners.
    pub fn call_module(
        &self,
        module: &str,
        export: &str,
        arguments: &[ObjectInput],
    ) -> Result<ModuleValue> {
        self.invoke(export, arguments, None, Some(module))
    }
    fn invoke(
        &self,
        export: &str,
        arguments: &[ObjectInput],
        component: Option<&str>,
        module: Option<&str>,
    ) -> Result<ModuleValue> {
        self.0.check()?;
        let mut fields = vec![
            ("owner", Data::from(self.0.id)),
            ("export", Data::from(export)),
            ("arguments", input::arguments(arguments, self.0.id)?),
        ];
        if let Some(v) = component {
            fields.push(("component", Data::from(v)));
        }
        if let Some(v) = module {
            fields.push(("module", Data::from(v)));
        }
        ModuleValue::new(self.clone(), self.0.engine.invoke("module-call", fields)?)
    }
    /// List selected component identities.
    /// # Errors
    /// Rejects a closed module.
    pub fn components(&self) -> Result<Vec<String>> {
        self.0.check()?;
        Ok(self.0.components.clone())
    }
    /// Revoke module values. Independently opened sessions retain their Scheme state.
    pub fn close(&self) {
        self.0.close();
    }
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.0.closed.load(Ordering::Acquire) || self.0.engine.is_closed()
    }
}
/// A retained native callable or value with explicit, independent release.
pub struct ModuleValue {
    owner: Module,
    handle: u64,
    count: usize,
    graph: Data,
    released: AtomicBool,
}
impl ModuleValue {
    fn new(owner: Module, receipt: Data) -> Result<Self> {
        Ok(Self {
            owner,
            handle: id(&receipt, "valueHandle")?,
            count: receipt.field("valueCount")?.index()?,
            graph: receipt.field("value")?.clone(),
            released: AtomicBool::new(false),
        })
    }
    fn check(&self) -> Result<()> {
        self.owner.0.check()?;
        if self.released.load(Ordering::Acquire) {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
    #[must_use]
    pub fn handle(&self) -> u64 {
        self.handle
    }
    /// Observe the native value graph without executing it again.
    /// # Errors
    /// Rejects released or closed values.
    pub fn graph(&self) -> Result<Data> {
        self.check()?;
        Ok(self.graph.clone())
    }
    /// Number of native multiple return values.
    /// # Errors
    /// Rejects released or closed values.
    pub fn value_count(&self) -> Result<usize> {
        self.check()?;
        Ok(self.count)
    }
    /// Retain an owner-bound argument reference.
    /// # Errors
    /// Rejects stale values and unknown observed graph nodes.
    pub fn reference(&self, node: Option<usize>) -> Result<ValueReference> {
        self.check()?;
        let node = if let Some(node) = node {
            if !self
                .graph
                .field("nodes")?
                .list()?
                .iter()
                .any(|v| v.field("id").and_then(Data::index) == Ok(node))
            {
                return Err(crate::failure("unknown native graph node"));
            }
            node
        } else {
            invoke(
                "module-value",
                [
                    ("owner", Data::from(self.owner.0.id)),
                    ("value", Data::from(self.handle)),
                    ("action", Data::from("reference")),
                ],
            )?
            .field("node")?
            .index()?
        };
        Ok(ValueReference {
            owner: self.owner.0.id,
            result: self.handle,
            node,
        })
    }
    /// Apply the actual native Scheme procedure retained by this lease.
    /// # Errors
    /// Rejects non-callables, invalid arguments and revoked values.
    pub fn apply(&self, arguments: &[ObjectInput]) -> Result<Self> {
        self.check()?;
        Self::new(
            self.owner.clone(),
            self.owner.0.engine.invoke(
                "module-apply",
                [
                    ("owner", Data::from(self.owner.0.id)),
                    ("value", Data::from(self.handle)),
                    ("arguments", input::arguments(arguments, self.owner.0.id)?),
                ],
            )?,
        )
    }
    /// Open the retained native Program/Evidence directly, without rerunning its constructor.
    /// # Errors
    /// Rejects non-program values, invalid limits and revoked owners.
    pub fn open_session(&self, limits: FactLimits) -> Result<Evidence> {
        self.check()?;
        let receipt = invoke(
            "value-evidence",
            [
                ("owner", Data::from(self.owner.0.id)),
                ("value", Data::from(self.handle)),
                ("factLimits", super::policy(limits)),
            ],
        )?;
        Evidence::new(&self.owner.0.engine, receipt)
    }
    /// Release native retained state exactly once.
    pub fn close(&self) {
        if !self.released.swap(true, Ordering::AcqRel) && !self.owner.is_closed() {
            let _ = invoke(
                "module-value",
                [
                    ("owner", Data::from(self.owner.0.id)),
                    ("value", Data::from(self.handle)),
                    ("action", Data::from("release")),
                ],
            );
        }
    }
}
impl Drop for ModuleValue {
    fn drop(&mut self) {
        self.close();
    }
}
