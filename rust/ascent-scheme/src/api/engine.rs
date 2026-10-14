//! Public engine ownership delegates finite execution to the existing Rayon owner.
use super::{Module, invoke};
use gerbil_ascent::{Component, Data, Error, Result};
use std::{
    collections::BTreeMap,
    ops::Deref,
    sync::{Arc, Mutex},
};

#[derive(Clone)]
pub struct Engine {
    core: gerbil_ascent::Engine,
    modules: Arc<Mutex<BTreeMap<String, String>>>,
    max_source_scopes: Option<usize>,
    max_input_bytes: Option<usize>,
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
            modules: Arc::default(),
            max_source_scopes: None,
            max_input_bytes: None,
        })
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
        let fields: Vec<_> = fields.into_iter().collect();
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
        invoke(operation, fields)
    }
    /// Observe the original native runtime inventory through typed data.
    /// # Errors
    /// Rejects closed owners or initialization errors.
    pub fn describe(&self) -> Result<Data> {
        self.invoke("describe", [])
    }
    fn load(
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
        Module::new(self, result)
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
            invoke("module-open", [("module", Data::from(name))])?
        };
        Module::new(self, result)
    }
    /// Register trusted source identity for a named module.
    /// # Errors
    /// Rejects conflicting declarations and closed engines.
    pub fn register_module(&self, name: &str, source: &str) -> Result<()> {
        super::check(self, false)?;
        let mut modules = self.modules.lock().map_err(|_| Error::Closed)?;
        if let Some(old) = modules.get(name) {
            if old != source {
                return Err(crate::failure("conflicting module source"));
            }
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
        Module::new(self, result)
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
