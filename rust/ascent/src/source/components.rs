//! Explicit component scopes and binding authority for declarative Evidence.
use super::{
    evidence::{EvidenceProgram, definition, lower_entry},
    reader::{Datum, invalid, read_all},
};
use crate::{Component, Result};
use std::collections::{BTreeMap, BTreeSet};

#[derive(Default)]
struct Scope {
    fragments: BTreeMap<String, Datum>,
    entries: BTreeMap<String, Vec<Datum>>,
    functions: BTreeMap<String, super::functions::Function>,
}
impl Scope {
    fn read(component: &Component) -> Result<Self> {
        let mut scope = Self::default();
        for form in read_all(&component.source)? {
            definition(
                &form,
                &mut scope.fragments,
                &mut scope.entries,
                &mut scope.functions,
            )?;
        }
        Ok(scope)
    }
    fn contains(&self, name: &str) -> bool {
        self.fragments.contains_key(name)
            || self.entries.contains_key(name)
            || self.functions.contains_key(name)
    }
}
impl EvidenceProgram {
    /// Validate selected component scopes before exposing a callable owner.
    /// # Errors
    /// Rejects unknown/cyclic dependencies, hidden imports and ambiguous bindings.
    pub fn validate_components(components: &[Component], entry: &str) -> Result<()> {
        Self::component_ids(components, entry).map(|_| ())
    }
    /// Read the admitted component closure without a host-side dependency traversal.
    /// # Errors
    /// Rejects cycles, hidden imports and ambiguous selected bindings.
    pub fn component_ids(components: &[Component], entry: &str) -> Result<Vec<String>> {
        let index = component_index(components)?;
        let mut scopes = BTreeMap::new();
        visit(entry, &index, &mut BTreeSet::new(), &mut scopes)?;
        for id in scopes.keys() {
            environment(id, &index, &scopes)?;
        }
        Ok(scopes.into_keys().collect())
    }
    /// Link selected exports in Library-owned scopes, never a host-side DAG.
    /// # Errors
    /// Rejects cycles, duplicate IDs, hidden bindings and unsupported definitions.
    pub fn read_components(
        components: &[Component],
        entry: &str,
        constructor: Option<&str>,
    ) -> Result<Self> {
        let index = component_index(components)?;
        let mut scopes = BTreeMap::new();
        visit(entry, &index, &mut BTreeSet::new(), &mut scopes)?;
        linked_entry(entry, constructor, &index, &scopes)
    }
}
fn component_index(components: &[Component]) -> Result<BTreeMap<String, &Component>> {
    let mut index = BTreeMap::new();
    for component in components {
        if component.id.is_empty() || index.insert(component.id.clone(), component).is_some() {
            return Err(invalid("duplicate or empty Evidence component ID"));
        }
    }
    Ok(index)
}
fn visit(
    id: &str,
    index: &BTreeMap<String, &Component>,
    stack: &mut BTreeSet<String>,
    scopes: &mut BTreeMap<String, Scope>,
) -> Result<()> {
    if scopes.contains_key(id) {
        return Ok(());
    }
    if !stack.insert(id.to_owned()) {
        return Err(invalid("cyclic Evidence component dependency"));
    }
    let component = index
        .get(id)
        .ok_or_else(|| invalid("unknown Evidence component"))?;
    for dependency in &component.dependencies {
        visit(&dependency.component, index, stack, scopes)?;
    }
    scopes.insert(id.to_owned(), Scope::read(component)?);
    stack.remove(id);
    Ok(())
}
fn exported(component: &Component, scope: &Scope, name: &str) -> bool {
    scope.contains(name)
        && component
            .exports
            .as_ref()
            .is_none_or(|names| names.iter().any(|n| n == name))
}
fn qualified(id: &str, name: &str) -> String {
    format!("{id}::{name}")
}
fn environment(
    id: &str,
    index: &BTreeMap<String, &Component>,
    scopes: &BTreeMap<String, Scope>,
) -> Result<BTreeMap<String, String>> {
    let component = index[id];
    let scope = &scopes[id];
    let mut env = scope
        .fragments
        .keys()
        .chain(scope.entries.keys())
        .chain(scope.functions.keys())
        .map(|n| (n.clone(), qualified(id, n)))
        .collect::<BTreeMap<_, _>>();
    for dependency in &component.dependencies {
        for binding in &dependency.bindings {
            let target = index[&dependency.component];
            if !exported(target, &scopes[&dependency.component], binding)
                || env
                    .insert(binding.clone(), qualified(&dependency.component, binding))
                    .is_some()
            {
                return Err(invalid("hidden or ambiguous Evidence component binding"));
            }
        }
    }
    Ok(env)
}
fn rename(form: &Datum, env: &BTreeMap<String, String>) -> Result<Datum> {
    let Datum::List(items) = form else {
        return Ok(form.clone());
    };
    if matches!(items.first(),Some(Datum::Atom(tag)) if tag == "quote") {
        return Ok(form.clone());
    }
    if let [Datum::Atom(tag), Datum::Atom(binding), label] = items.as_slice()
        && tag == "relational-export"
    {
        return Ok(Datum::List(vec![
            Datum::Atom(tag.clone()),
            Datum::Atom(
                env.get(binding)
                    .ok_or_else(|| invalid("unbound scoped relational graph"))?
                    .clone(),
            ),
            label.clone(),
        ]));
    }
    if let [Datum::Atom(tag), Datum::Atom(binding)] = items.as_slice()
        && tag == "include"
    {
        return Ok(Datum::List(vec![
            Datum::Atom(tag.clone()),
            Datum::Atom(
                env.get(binding)
                    .ok_or_else(|| invalid("unbound scoped Evidence include"))?
                    .clone(),
            ),
        ]));
    }
    let mut renamed = items
        .iter()
        .map(|child| rename(child, env))
        .collect::<Result<Vec<_>>>()?;
    if let Some(Datum::Atom(label)) = renamed.first_mut()
        && let Some(qualified) = env.get(label)
    {
        *label = qualified.clone();
    }
    Ok(Datum::List(renamed))
}
fn linked_entry(
    id: &str,
    constructor: Option<&str>,
    index: &BTreeMap<String, &Component>,
    scopes: &BTreeMap<String, Scope>,
) -> Result<EvidenceProgram> {
    let scope = &scopes[id];
    let available = scope
        .entries
        .keys()
        .filter(|n| exported(index[id], scope, n))
        .collect::<Vec<_>>();
    let label = match constructor {
        Some(name) if available.iter().any(|n| n.as_str() == name) => name.to_owned(),
        None if available.len() == 1 => available[0].clone(),
        _ => return Err(invalid("select one exported Evidence constructor")),
    };
    let mut fragments = BTreeMap::new();
    let mut functions = BTreeMap::new();
    for (owner, scope) in scopes {
        let env = environment(owner, index, scopes)?;
        for (name, function) in &scope.functions {
            functions.insert(qualified(owner, name), function.scoped(&env));
        }
        for (name, fragment) in &scope.fragments {
            fragments.insert(qualified(owner, name), rename(fragment, &env)?);
        }
    }
    let env = environment(id, index, scopes)?;
    let body = scope.entries[&label]
        .iter()
        .map(|f| rename(f, &env))
        .collect::<Result<Vec<_>>>()?;
    let body = body
        .iter()
        .map(|form| super::functions::expand(form, &functions, 0))
        .collect::<Result<Vec<_>>>()?;
    let fragments = fragments
        .into_iter()
        .map(|(name, form)| Ok((name, super::functions::expand(&form, &functions, 0)?)))
        .collect::<Result<BTreeMap<_, _>>>()?;
    lower_entry(label, &body, &fragments)
}
