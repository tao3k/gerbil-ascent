//! Pure source functions lower hygienically into closed Rust expression trees.
use super::{
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::{BTreeMap, BTreeSet};
#[derive(Clone, Debug)]
pub(super) struct Function {
    parameters: Vec<String>,
    body: Datum,
    constant: bool,
    rules: Option<super::macros::Rules>,
}
impl Function {
    pub(super) fn scoped(&self, environment: &BTreeMap<String, String>) -> Self {
        let environment = environment
            .iter()
            .filter(|(name, _)| !self.parameters.contains(name))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();
        Self {
            parameters: self.parameters.clone(),
            body: scope_calls(&self.body, &environment),
            constant: self.constant,
            rules: self.rules.as_ref().map(|rules| rules.scoped(&environment)),
        }
    }
    pub(super) fn constant(body: &Datum) -> Result<Self> {
        super::lowering::literal(body)?;
        Ok(Self {
            parameters: vec![],
            body: body.clone(),
            constant: true,
            rules: None,
        })
    }
    pub(super) fn read(signature: &Datum, body: &Datum) -> Result<(String, Self)> {
        let (label, parameters) = list(signature)?
            .split_first()
            .ok_or_else(|| invalid("function signature required"))?;
        let parameters = parameters
            .iter()
            .map(|p| name(p).map(str::to_owned))
            .collect::<Result<Vec<_>>>()?;
        if parameters.iter().collect::<BTreeSet<_>>().len() != parameters.len() {
            return Err(invalid("duplicate pure function parameter"));
        }
        Ok((
            name(label)?.into(),
            Self {
                parameters,
                body: body.clone(),
                constant: false,
                rules: None,
            },
        ))
    }
    pub(super) fn rules(items: &[Datum]) -> Result<(String, Self)> {
        let (label, rules) = super::macros::Rules::read(items)?;
        Ok((
            label,
            Self {
                parameters: vec![],
                body: Datum::List(vec![]),
                constant: false,
                rules: Some(rules),
            },
        ))
    }
}
pub(super) fn expand(
    form: &Datum,
    functions: &BTreeMap<String, Function>,
    depth: usize,
) -> Result<Datum> {
    expand_at(form, functions, depth, &mut 0)
}
fn expand_at(
    form: &Datum,
    functions: &BTreeMap<String, Function>,
    depth: usize,
    nodes: &mut usize,
) -> Result<Datum> {
    if *nodes >= 65_536 {
        return Err(invalid("pure function expansion node bound"));
    }
    *nodes += 1;
    if depth > 128 {
        return Err(invalid("pure function expansion bound or recursive cycle"));
    }
    if let Datum::Atom(label) = form
        && let Some(function) = functions.get(label)
        && function.constant
    {
        return expand_at(&function.body, functions, depth + 1, nodes);
    }
    let Datum::List(items) = form else {
        return Ok(form.clone());
    };
    if matches!(items.first(),Some(Datum::Atom(tag)) if tag == "quote") {
        return Ok(form.clone());
    }
    if let Some(Datum::Atom(label)) = items.first()
        && let Some(function) = functions.get(label)
    {
        if let Some(rules) = &function.rules {
            return expand_at(&rules.apply(form, *nodes)?, functions, depth + 1, nodes);
        }
        if items.len() - 1 != function.parameters.len() {
            return Err(invalid("pure function argument arity"));
        }
        let bindings = function
            .parameters
            .iter()
            .cloned()
            .zip(items[1..].iter().cloned())
            .collect::<BTreeMap<_, _>>();
        return expand_at(
            &substitute(&function.body, &bindings),
            functions,
            depth + 1,
            nodes,
        );
    }
    items
        .iter()
        .map(|item| expand_at(item, functions, depth + 1, nodes))
        .collect::<Result<Vec<_>>>()
        .map(Datum::List)
}
pub(super) fn scope_calls(form: &Datum, environment: &BTreeMap<String, String>) -> Datum {
    let Datum::List(items) = form else {
        return form.clone();
    };
    if matches!(items.first(),Some(Datum::Atom(tag)) if tag == "quote") {
        return form.clone();
    }
    if let [Datum::Atom(tag), Datum::Atom(binding)] = items.as_slice()
        && tag == "include"
        && let Some(qualified) = environment.get(binding)
    {
        return Datum::List(vec![
            Datum::Atom(tag.clone()),
            Datum::Atom(qualified.clone()),
        ]);
    }
    if let [Datum::Atom(tag), Datum::Atom(binding), label] = items.as_slice()
        && tag == "relational-export"
        && let Some(qualified) = environment.get(binding)
    {
        return Datum::List(vec![
            Datum::Atom(tag.clone()),
            Datum::Atom(qualified.clone()),
            label.clone(),
        ]);
    }
    let mut items = items
        .iter()
        .map(|item| scope_calls(item, environment))
        .collect::<Vec<_>>();
    if let Some(Datum::Atom(label)) = items.first_mut()
        && let Some(qualified) = environment.get(label)
    {
        *label = qualified.clone();
    }
    Datum::List(items)
}
fn substitute(form: &Datum, bindings: &BTreeMap<String, Datum>) -> Datum {
    match form {
        Datum::Atom(label) => bindings.get(label).cloned().unwrap_or_else(|| form.clone()),
        Datum::List(items) if !matches!(items.first(),Some(Datum::Atom(tag)) if tag == "quote") => {
            Datum::List(
                items
                    .iter()
                    .map(|item| substitute(item, bindings))
                    .collect(),
            )
        }
        _ => form.clone(),
    }
}
