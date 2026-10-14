//! Named module inventory resolves lexical imports into existing component owners.
use super::{
    Component, Dependency, Module, ModuleValue, ObjectInput, components::link, objects::fail,
    operator_values, primitives, relational,
};
use crate::{
    Engine, Result,
    source::{Datum, definitions},
};
use std::collections::{BTreeMap, BTreeSet};
fn bundled(name: &str) -> Option<&'static str> {
    match name {
        ":gerbil-ascent/evidence/execution" => {
            Some(include_str!("../../../../evidence/execution.ss"))
        }
        _ => None,
    }
}
fn builtin(name: &str) -> Option<Vec<&'static str>> {
    match name {
        ":gerbil-ascent/table/trrel-uf" => Some(super::reachability::EXPORTS.to_vec()),
        ":gerbil-ascent/program/higher-order" => Some(super::typed::EXPORTS.to_vec()),
        ":gerbil-ascent/program/aggregators" => Some(super::aggregates::EXPORTS.to_vec()),
        ":gerbil-ascent/program/interface" => Some(
            operator_values::EXPORTS
                .iter()
                .chain(relational::EXPORTS)
                .chain(super::operator_change::EXPORTS)
                .chain(super::typed::EXPORTS)
                .chain(super::aggregates::EXPORTS)
                .copied()
                .chain(
                    primitives::BUILTINS
                        .iter()
                        .copied()
                        .filter(|s| s.starts_with("gerbil-ascent-")),
                )
                .collect(),
        ),
        ":gerbil-ascent/evidence/interface" => {
            let mut names = builtin(":gerbil-ascent/program/interface")?;
            names.push("ascent-evidence-module");
            Some(names)
        }
        ":gerbil-ascent/interface/evidence-module" => {
            Some(vec!["ascent-evidence-module", "evidence-module-program"])
        }
        ":gerbil-ascent/core/relation-view" => Some(super::views::EXPORTS.to_vec()),
        ":clan/poo/object" => Some(vec![".ref"]),
        _ => None,
    }
}
impl Engine {
    /// Register a source module for subsequent owners. Existing owners keep their locations.
    /// # Errors
    /// Rejects malformed names/source, reserved library names, inventory exhaustion or closure.
    pub fn register_module(&self, name: &str, source: &str) -> Result<()> {
        self.check()?;
        label(name)?;
        definitions(source)?;
        if builtin(name).is_some() || bundled(name).is_some() {
            return Err(fail("cannot replace a library module"));
        }
        let mut inventory = self
            .module_sources
            .lock()
            .map_err(|_| fail("module registry lock poisoned"))?;
        if inventory.len() >= 64 && !inventory.contains_key(name) {
            return Err(fail("module inventory limit"));
        }
        inventory.insert(name.into(), source.into());
        Ok(())
    }
    /// Load a bundled Rust module or a registered native Scheme module, without compilation.
    /// # Errors
    /// Rejects unknown modules, bad exports/imports, cycles and failed definitions.
    pub fn module(&self, name: &str) -> Result<Module> {
        self.check()?;
        let components = collect(self, name)?;
        self.load_components(&components, name)
    }
}
impl Module {
    /// Resolve an additional named module in this owner's lexical arena, then call its export.
    /// # Errors
    /// Unknown/unexported modules, invalid imports and revoked values fail closed.
    pub fn call_module(
        &self,
        module: &str,
        export: &str,
        args: &[ObjectInput],
    ) -> Result<ModuleValue> {
        {
            let engine = {
                let state = self.lock()?;
                if self.is_closed() {
                    return Err(crate::Error::Closed);
                }
                state.engine.clone()
            };
            let components = collect(&engine, module)?;
            let selected = link(&components, module)?;
            let mut state = self.lock()?;
            if self.is_closed() {
                return Err(crate::Error::Closed);
            }
            let primitives = state
                .primitives
                .ok_or_else(|| fail("closed module scope"))?;
            for component in selected {
                if !state.scopes.contains_key(&component.id) {
                    state.load_component(component, primitives, &engine)?;
                }
            }
        }
        self.call(export, args, Some(module))
    }
}
fn label(name: &str) -> Result<()> {
    if name.starts_with(':') && name.len() <= 128 && !name.chars().any(char::is_whitespace) {
        Ok(())
    } else {
        Err(fail("absolute module identifier required"))
    }
}
fn collect(engine: &Engine, entry: &str) -> Result<Vec<Component>> {
    label(entry)?;
    let sources = engine
        .module_sources
        .lock()
        .map_err(|_| fail("module registry lock poisoned"))?
        .clone();
    let mut collector = Collector {
        sources,
        components: BTreeMap::new(),
        visiting: BTreeSet::new(),
    };
    collector.visit(entry)?;
    Ok(collector.components.into_values().collect())
}
struct Collector {
    sources: BTreeMap<String, String>,
    components: BTreeMap<String, Component>,
    visiting: BTreeSet<String>,
}
impl Collector {
    fn visit(&mut self, name: &str) -> Result<()> {
        if self.components.contains_key(name) {
            return Ok(());
        }
        if !self.visiting.insert(name.into()) {
            return Err(fail("cyclic module import"));
        }
        if self.visiting.len() + self.components.len() > 64 {
            return Err(fail("module dependency bound"));
        }
        let component = if let Some(exports) = builtin(name) {
            let names: BTreeSet<_> = exports.into_iter().collect();
            Component {
                id: name.into(),
                source: names.iter().fold(String::new(), |mut out, s| {
                    use std::fmt::Write;
                    writeln!(out, "(def {s} {s})").expect("string output");
                    out
                }),
                exports: Some(names.into_iter().map(str::to_string).collect()),
                dependencies: Vec::new(),
            }
        } else {
            self.source(name)?
        };
        self.visiting.remove(name);
        self.components.insert(name.into(), component);
        Ok(())
    }
    fn source(&mut self, name: &str) -> Result<Component> {
        let source = self
            .sources
            .get(name)
            .map(String::as_str)
            .or_else(|| bundled(name))
            .ok_or_else(|| fail("module is not registered"))?;
        let forms = definitions(source)?;
        let mut exports = Vec::new();
        let mut dependencies = Vec::new();
        let mut body = String::new();
        for form in forms {
            match &form {
                Datum::List(items) if matches!(items.first(),Some(Datum::Atom(tag)) if tag=="export") => {
                    for item in &items[1..] {
                        exports.push(symbol(item)?.to_string());
                    }
                }
                Datum::List(items) if matches!(items.first(),Some(Datum::Atom(tag)) if tag=="import") => {
                    for item in &items[1..] {
                        dependencies.push(self.import(item)?);
                    }
                }
                _ => {
                    write(&form, &mut body);
                    body.push('\n');
                }
            }
        }
        Ok(Component {
            id: name.into(),
            source: body,
            exports: Some(exports),
            dependencies,
        })
    }
    fn import(&mut self, spec: &Datum) -> Result<Dependency> {
        let (module, bindings) = match spec {
            Datum::Atom(name) => (name.as_str(), None),
            Datum::List(items)
                if matches!(items.first(),Some(Datum::Atom(tag)) if tag=="only-in")
                    && items.len() >= 2 =>
            {
                (
                    symbol(&items[1])?,
                    Some(
                        items[2..]
                            .iter()
                            .map(|d| symbol(d).map(str::to_string))
                            .collect::<Result<Vec<_>>>()?,
                    ),
                )
            }
            _ => return Err(fail("unsupported module import selector")),
        };
        label(module)?;
        self.visit(module)?;
        let bindings =
            bindings.unwrap_or_else(|| self.components[module].exports.clone().unwrap_or_default());
        Ok(Dependency {
            component: module.into(),
            bindings,
        })
    }
}
fn symbol(datum: &Datum) -> Result<&str> {
    if let Datum::Atom(value) = datum {
        Ok(value)
    } else {
        Err(fail("module identifier required"))
    }
}
fn write(datum: &Datum, out: &mut String) {
    match datum {
        Datum::Atom(value) => out.push_str(value),
        Datum::Text(value) => {
            out.push('"');
            for c in value.chars() {
                match c {
                    '\n' => out.push_str("\\n"),
                    '\r' => out.push_str("\\r"),
                    '\t' => out.push_str("\\t"),
                    '\\' => out.push_str("\\\\"),
                    '"' => out.push_str("\\\""),
                    _ => out.push(c),
                }
            }
            out.push('"');
        }
        Datum::List(items) => {
            out.push('(');
            for (i, item) in items.iter().enumerate() {
                if i != 0 {
                    out.push(' ');
                }
                write(item, out);
            }
            out.push(')');
        }
    }
}
