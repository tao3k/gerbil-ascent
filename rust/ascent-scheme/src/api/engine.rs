//! Public engine ownership delegates finite execution to the existing Rayon owner.
use super::{Module, invoke};
use gerbil_ascent::{Component, Data, Error, Result};
use std::{
    collections::BTreeMap,
    ops::Deref,
    sync::{Arc, Mutex, Weak},
};

/// Kernel selection after the native Scheme frontend has admitted a program.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Backend {
    Scheme,
    Rayon,
}
/// Caller-owned Rust pool and shared native module scopes.
#[derive(Clone)]
pub struct Engine {
    core: gerbil_ascent::Engine,
    backend: Option<Backend>,
    modules: Arc<Mutex<BTreeMap<String, String>>>,
    loaded_modules: Arc<Mutex<BTreeMap<String, Weak<super::module::Owner>>>>,
    owners: Arc<Owners>,
    max_source_scopes: Option<usize>,
    max_input_bytes: Option<usize>,
}
#[derive(Default)]
struct Owners {
    modules: Mutex<Vec<Weak<super::module::Owner>>>,
    sessions: Mutex<Vec<Weak<super::session::State>>>,
}
impl Deref for Engine {
    type Target = gerbil_ascent::Engine;
    fn deref(&self) -> &Self::Target {
        &self.core
    }
}
impl Engine {
    /// Construct the default caller-owned Rayon execution pool. Scheme initializes lazily.
    /// # Errors
    /// Returns invalid worker counts or pool construction errors.
    pub fn new(workers: usize) -> Result<Self> {
        Ok(Self {
            core: gerbil_ascent::Engine::new(workers)?,
            backend: None,
            modules: Arc::default(),
            loaded_modules: Arc::default(),
            owners: Arc::default(),
            max_source_scopes: None,
            max_input_bytes: None,
        })
    }
    /// Revoke this engine and release all native owner slots, including retained leases.
    pub fn shutdown(&self) {
        self.core.shutdown();
        self.close_modules();
        self.close_sessions();
    }
    pub(super) fn track_module(&self, owner: &Arc<super::module::Owner>) -> Result<()> {
        let mut owners = self.owners.modules.lock().map_err(|_| Error::Closed)?;
        super::check(self, false)?;
        owners.retain(|owner| owner.strong_count() > 0);
        owners.push(Arc::downgrade(owner));
        Ok(())
    }
    pub(super) fn track_session(&self, owner: &Arc<super::session::State>) -> Result<()> {
        let mut owners = self.owners.sessions.lock().map_err(|_| Error::Closed)?;
        super::check(self, false)?;
        owners.retain(|owner| owner.strong_count() > 0);
        owners.push(Arc::downgrade(owner));
        Ok(())
    }
    fn close_modules(&self) {
        let owners = self
            .owners
            .modules
            .lock()
            .map(|mut owners| {
                owners
                    .drain(..)
                    .filter_map(|owner| owner.upgrade())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        for owner in owners {
            owner.close();
        }
    }
    fn close_sessions(&self) {
        let owners = self
            .owners
            .sessions
            .lock()
            .map(|mut owners| {
                owners
                    .drain(..)
                    .filter_map(|owner| owner.upgrade())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        for owner in owners {
            owner.close();
        }
    }
    /// Select a kernel explicitly; automatic selection keeps opaque callbacks in Scheme.
    #[must_use]
    pub fn with_backend(mut self, backend: Backend) -> Self {
        self.backend = Some(backend);
        self
    }
    #[must_use]
    pub fn backend(&self) -> Option<Backend> {
        self.backend
    }
    /// Limit cumulative native scopes, including failed expansions and closed modules.
    /// # Errors
    /// Rejects zero; native admission preserves the process-wide count.
    pub fn with_source_scope_limit(mut self, limit: Option<usize>) -> Result<Self> {
        if limit == Some(0) {
            return Err(crate::failure(
                "source scope ceiling must be a positive integer",
            ));
        }
        self.max_source_scopes = limit;
        Ok(self)
    }
    #[must_use]
    pub fn max_source_scopes(&self) -> Option<usize> {
        self.max_source_scopes
    }
    /// Bound typed native input payloads before VM entry, without JSON encoding.
    /// # Errors
    /// Rejects zero byte ceilings.
    pub fn with_input_limit(mut self, limit: Option<usize>) -> Result<Self> {
        if limit == Some(0) {
            return Err(crate::failure(
                "input byte ceiling must be a positive integer",
            ));
        }
        self.max_input_bytes = limit;
        Ok(self)
    }
    #[must_use]
    pub fn max_input_bytes(&self) -> Option<usize> {
        self.max_input_bytes
    }
    pub(super) fn invoke(
        &self,
        operation: &str,
        fields: impl IntoIterator<Item = (&'static str, Data)>,
    ) -> Result<Data> {
        super::check(self, false)?;
        let mut fields: Vec<_> = fields.into_iter().collect();
        if let Some(limit) = self.max_input_bytes {
            let bytes = fields
                .iter()
                .try_fold(operation.len(), |sum, (key, value)| {
                    payload_bytes(value)
                        .and_then(|size| sum.checked_add(key.len())?.checked_add(size))
                })
                .ok_or_else(|| crate::failure("caller input byte bound"))?;
            if bytes > limit {
                return Err(crate::failure("caller input byte bound"));
            }
        }
        let admission;
        if fields.iter().any(|(key, _)| *key == "executionControl") {
            admission = None;
        } else {
            let limits = gerbil_ascent::Limits {
                max_states: usize::MAX,
                max_facts: usize::MAX,
                ..gerbil_ascent::Limits::default()
            };
            admission = Some(crate::control::Control::new(
                &limits,
                &gerbil_ascent::Cancellation::default(),
            )?);
            fields.push(("executionControl", admission.as_ref().unwrap().id()));
        }
        let result = invoke(operation, fields);
        drop(admission);
        result
    }
    /// Observe the original native runtime inventory through typed data.
    /// # Errors
    /// Rejects closed owners or initialization errors.
    pub fn describe(&self) -> Result<Data> {
        self.invoke("describe", [])
    }
    pub(super) fn load(
        &self,
        operation: &str,
        fields: impl IntoIterator<Item = (&'static str, Data)>,
    ) -> Result<Data> {
        let mut fields: Vec<_> = fields.into_iter().collect();
        if let Some(limit) = self.max_source_scopes {
            fields.push(("maxSourceScopes", Data::from(limit)));
        }
        self.invoke(operation, fields)
    }
    /// Load trusted Scheme declarations using the linked native loader.
    /// # Errors
    /// Returns native syntax, admission and owner errors.
    pub fn load_definitions(&self, source: &str) -> Result<Module> {
        super::check(self, false)?;
        let result = self.load(
            "dsl-open",
            [
                ("source", Data::from(source)),
                ("trusted", Data::Bool(true)),
            ],
        )?;
        Module::new(self, &result)
    }
    /// Open a native installed Scheme module; no compiler subprocess is launched.
    /// # Errors
    /// Returns native module/owner errors.
    pub fn module(&self, name: &str) -> Result<Module> {
        super::check(self, false)?;
        let source = self
            .modules
            .lock()
            .map_err(|_| Error::Closed)?
            .get(name)
            .cloned();
        let result = if let Some(source) = source {
            self.load(
                "module-source-open",
                [
                    ("source", Data::from(source)),
                    ("trusted", Data::Bool(true)),
                ],
            )?
        } else {
            self.invoke("module-open", [("module", Data::from(name))])?
        };
        let module = Module::new(self, &result)?;
        self.loaded_modules
            .lock()
            .map_err(|_| Error::Closed)?
            .insert(name.into(), Arc::downgrade(&module.0));
        Ok(module)
    }
    pub(super) fn resolve_module(&self, name: &str) -> Result<Module> {
        if let Some(owner) = self
            .loaded_modules
            .lock()
            .map_err(|_| Error::Closed)?
            .get(name)
            .and_then(Weak::upgrade)
            && owner.check().is_ok()
        {
            return Ok(Module(owner));
        }
        self.module(name)
    }
    pub(super) fn is_registered(&self, name: &str) -> Result<bool> {
        Ok(self
            .modules
            .lock()
            .map_err(|_| Error::Closed)?
            .contains_key(name))
    }
    /// Register trusted source identity for a named module.
    /// # Errors
    /// Rejects conflicting declarations and closed engines.
    pub fn register_module(&self, name: &str, source: &str) -> Result<()> {
        super::check(self, false)?;
        let mut modules = self.modules.lock().map_err(|_| Error::Closed)?;
        if let Some(old) = modules.get(name)
            && old != source
        {
            return Err(crate::failure("conflicting module source"));
        }
        modules.insert(name.into(), source.into());
        Ok(())
    }
    /// Link Scheme component definitions in their original lexical environments.
    /// # Errors
    /// Returns native manifest, dependency and syntax errors.
    pub fn load_components(&self, components: &[Component], entry: &str) -> Result<Module> {
        super::check(self, false)?;
        let sources = Data::Map(
            components
                .iter()
                .map(|c| (c.id.clone(), Data::from(c.source.clone())))
                .collect(),
        );
        let manifest = Data::object([
            ("schema", Data::from("ascent.evidence-components.v1")),
            (
                "components",
                Data::List(
                    components
                        .iter()
                        .map(|c| {
                            Data::object([
                                ("id", Data::from(c.id.clone())),
                                ("source", Data::from(c.id.clone())),
                                (
                                    "exports",
                                    Data::List(
                                        c.exports
                                            .clone()
                                            .unwrap_or_default()
                                            .into_iter()
                                            .map(Data::from)
                                            .collect(),
                                    ),
                                ),
                                (
                                    "dependencies",
                                    Data::List(
                                        c.dependencies
                                            .iter()
                                            .map(|d| {
                                                Data::object([
                                                    ("component", Data::from(d.component.clone())),
                                                    (
                                                        "bindings",
                                                        Data::List(
                                                            d.bindings
                                                                .iter()
                                                                .cloned()
                                                                .map(Data::from)
                                                                .collect(),
                                                        ),
                                                    ),
                                                ])
                                            })
                                            .collect(),
                                    ),
                                ),
                            ])
                        })
                        .collect(),
                ),
            ),
        ]);
        let result = self.load(
            "components-open",
            [
                ("components", manifest),
                ("sources", sources),
                ("entry", Data::from(entry)),
                ("trusted", Data::Bool(true)),
            ],
        )?;
        Module::new(self, &result)
    }
}
// Logical typed payload bytes: UTF-8 text/keys, binary integer magnitude plus
// sign, IEEE-754 words, one-byte booleans and eight-byte collection lengths.
fn payload_bytes(value: &Data) -> Option<usize> {
    match value {
        Data::Null => Some(0),
        Data::Bool(_) => Some(1),
        Data::Real(_) => Some(8),
        Data::Integer(value) => value.to_bytes_le().1.len().checked_add(1),
        Data::Text(value) => Some(value.len()),
        Data::List(values) => values
            .iter()
            .try_fold(8usize, |sum, value| sum.checked_add(payload_bytes(value)?)),
        Data::Map(values) => values.iter().try_fold(8usize, |sum, (key, value)| {
            sum.checked_add(key.len())?
                .checked_add(payload_bytes(value)?)
        }),
    }
}
