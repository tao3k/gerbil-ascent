//! Component inventory validation precedes evaluation, including unselected cycles.
use super::objects::fail;
use crate::Result;
use std::collections::{BTreeMap, BTreeSet};
/// Selected bindings imported from one independently scoped component.
#[derive(Clone, Debug)]
pub struct Dependency {
    pub component: String,
    pub bindings: Vec<String>,
}
/// Source definitions and explicit component linkage authority.
#[derive(Clone, Debug)]
pub struct Component {
    pub id: String,
    pub source: String,
    pub exports: Option<Vec<String>>,
    pub dependencies: Vec<Dependency>,
}
pub(super) fn link<'a>(components: &'a [Component], entry: &str) -> Result<Vec<&'a Component>> {
    if components.is_empty() || components.len() > 64 {
        return Err(fail("component inventory bound"));
    }
    let index = components
        .iter()
        .map(index_component)
        .collect::<Result<BTreeMap<_, _>>>()?;
    if index.len() != components.len() {
        return Err(fail("duplicate component"));
    }
    validate_inventory(components, &index)?;
    let mut state = BTreeMap::new();
    let mut order = Vec::new();
    visit(entry, &index, &mut state, &mut order)?;
    let selected = order.clone();
    validate_all_cycles(components, &index, &mut state, &mut order)?;
    Ok(selected)
}
fn visit<'a>(
    id: &str,
    index: &BTreeMap<&str, &'a Component>,
    state: &mut BTreeMap<String, bool>,
    order: &mut Vec<&'a Component>,
) -> Result<()> {
    match state.get(id) {
        Some(true) => return Ok(()),
        Some(false) => return Err(fail("cyclic component dependency")),
        None => (),
    }
    let component = index
        .get(id)
        .ok_or_else(|| fail("unknown component entry"))?;
    state.insert(id.into(), false);
    for dependency in &component.dependencies {
        visit(&dependency.component, index, state, order)?;
    }
    state.insert(id.into(), true);
    order.push(component);
    Ok(())
}
fn label(value: &str) -> Result<()> {
    if value.is_empty() || value.len() > 128 {
        Err(fail("invalid component label"))
    } else {
        Ok(())
    }
}
fn labels(values: &[String]) -> Result<()> {
    let mut seen = BTreeSet::new();
    for value in values {
        label(value)?;
        if !seen.insert(value) {
            return Err(fail("duplicate component binding"));
        }
    }
    Ok(())
}

fn validate_imports(component: &Component, index: &BTreeMap<&str, &Component>) -> Result<()> {
    let mut imported = Vec::new();
    for dependency in &component.dependencies {
        label(&dependency.component)?;
        labels(&dependency.bindings)?;
        validate_dependency(dependency, index)?;
        imported.extend(dependency.bindings.iter().cloned());
    }
    labels(&imported)
}

fn validate_component(component: &Component) -> Result<()> {
    label(&component.id)?;
    if let Some(exports) = &component.exports {
        labels(exports)?;
    }
    Ok(())
}
fn validate_dependency(dependency: &Dependency, index: &BTreeMap<&str, &Component>) -> Result<()> {
    let target = index
        .get(dependency.component.as_str())
        .ok_or_else(|| fail("missing component dependency"))?;
    let exports: BTreeSet<_> = target
        .exports
        .as_ref()
        .ok_or_else(|| fail("dependency needs explicit exports"))?
        .iter()
        .collect();
    if dependency
        .bindings
        .iter()
        .any(|binding| !exports.contains(binding))
    {
        return Err(fail("dependency binding not exported"));
    }
    Ok(())
}

fn index_component(component: &Component) -> Result<(&str, &Component)> {
    validate_component(component)?;
    Ok((component.id.as_str(), component))
}

fn validate_inventory(components: &[Component], index: &BTreeMap<&str, &Component>) -> Result<()> {
    for component in components {
        validate_imports(component, index)?;
    }
    Ok(())
}
fn validate_all_cycles<'a>(
    components: &[Component],
    index: &BTreeMap<&str, &'a Component>,
    state: &mut BTreeMap<String, bool>,
    order: &mut Vec<&'a Component>,
) -> Result<()> {
    for component in components {
        visit(&component.id, index, state, order)?;
    }
    Ok(())
}
