//! Native module DSL forms reuse typed rule lowering and freeze evaluated initial rows.
use super::{
    constructors::Admission,
    evaluation::Evaluation,
    objects::{EnvId, Id, Object, fail},
};
use crate::{Result, source::Datum};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
impl Evaluation<'_> {
    pub(super) fn ascent_form(
        &mut self,
        datum: &Datum,
        env: EnvId,
        depth: usize,
    ) -> Result<Vec<Id>> {
        let Datum::List(forms) = datum else {
            return Err(fail("native ascent form required"));
        };
        let forms = expand_local(&forms[1..])?;
        let includes = self.included_forms(&forms, env, depth)?;
        let mut lowered = Vec::new();
        let mut initial = BTreeMap::new();
        let mut names = BTreeSet::new();
        for (position, form) in forms.iter().enumerate() {
            self.check(depth)?;
            if let Some((program, root)) = includes.get(&position) {
                lowered.push(crate::source::NativePart::Included(program.clone()));
                initial.insert(format!("#include-{position}"), *root);
            } else {
                lowered.push(crate::source::NativePart::Declaration(
                    self.initial_declaration(form, env, depth, &mut initial, &mut names)?,
                ));
            }
        }
        let mut program = crate::source::native_parts(lowered)?;
        let admission = Admission::new(self.arena, self.arena.identity)?;
        for relation in &mut program.relations {
            if let Some(id) = initial.get(&relation.name) {
                relation.rows = admission.rows(*id)?;
            }
            // Native ascent does not grant mutation authority. The evidence/program
            // constructor explicitly declares source handles when mutation is wanted.
            relation.source = false;
        }
        if !program.relations.is_empty() {
            crate::graph::Graph::build(program.clone())?;
        }
        self.arena
            .add(Object::Compiled(
                Arc::new(program),
                initial.into_values().collect(),
            ))
            .map(|id| vec![id])
    }
    fn included_forms(
        &mut self,
        forms: &[Datum],
        env: EnvId,
        depth: usize,
    ) -> Result<BTreeMap<usize, (crate::Program, Id)>> {
        forms
            .iter()
            .enumerate()
            .filter_map(|(i, form)| {
                let Datum::List(items) = form else {
                    return None;
                };
                (items.first() == Some(&Datum::Atom("include".into()))).then_some((i, items))
            })
            .map(|(i, items)| {
                let [_, expression] = items.as_slice() else {
                    return Err(fail("include requires one fragment expression"));
                };
                let root = self.single(expression, env, depth + 1)?;
                let Object::Compiled(program, _) = self.arena.get(root)? else {
                    return Err(fail("include requires a native fragment"));
                };
                Ok((i, ((**program).clone(), root)))
            })
            .collect()
    }
    fn initial_declaration(
        &mut self,
        form: &Datum,
        env: EnvId,
        depth: usize,
        initial: &mut BTreeMap<String, Id>,
        names: &mut BTreeSet<String>,
    ) -> Result<Datum> {
        let Datum::List(items) = form else {
            return Ok(form.clone());
        };
        if !matches!(items.first(),Some(Datum::Atom(name)) if name=="relation" || name=="lattice") {
            return Ok(form.clone());
        }
        let [_, Datum::Atom(name), _, rest @ ..] = items.as_slice() else {
            return Err(fail("native relation declaration shape"));
        };
        if !names.insert(name.clone()) {
            return Err(fail("duplicate native relation declaration"));
        }
        if rest.is_empty() {
            return Ok(form.clone());
        }
        if items.first() == Some(&Datum::Atom("lattice".into())) {
            let [rows, join] = rest else {
                return Err(fail("lattice rows and join required"));
            };
            initial.insert(name.clone(), self.single(rows, env, depth + 1)?);
            let join = self.single(join, env, depth + 1)?;
            let name = match self.arena.get(join)? {
                Object::Procedure(super::objects::Procedure::Builtin(name @ ("min" | "max"))) => {
                    *name
                }
                _ => return Err(fail("lattice join requires a checked numeric semilattice")),
            };
            return Ok(Datum::List(vec![
                items[0].clone(),
                items[1].clone(),
                items[2].clone(),
                Datum::List(Vec::new()),
                Datum::Atom(name.into()),
            ]));
        }
        let [rows] = rest else {
            return Err(fail(
                "native relation storage/provider form requires lowering",
            ));
        };
        initial.insert(name.clone(), self.single(rows, env, depth + 1)?);
        Ok(Datum::List(items[..3].to_vec()))
    }
}

struct LocalMacro {
    parameters: Vec<String>,
    body: Vec<Datum>,
}
fn expand_local(forms: &[Datum]) -> Result<Vec<Datum>> {
    let mut macros = BTreeMap::new();
    let mut result = Vec::new();
    for form in forms {
        expand_form(form, &mut macros, &mut result, 0)?;
    }
    Ok(result)
}
fn expand_form(
    form: &Datum,
    macros: &mut BTreeMap<String, LocalMacro>,
    output: &mut Vec<Datum>,
    depth: usize,
) -> Result<()> {
    if depth > 64 || output.len() >= 512 {
        return Err(fail("local DSL expansion bound"));
    }
    let Datum::List(items) = form else {
        return Err(fail("DSL declaration must be a form"));
    };
    if items.first() == Some(&Datum::Atom("macro".into())) {
        let [_, Datum::Atom(name), Datum::List(parameters), body @ ..] = items.as_slice() else {
            return Err(fail("local macro declaration shape"));
        };
        let parameters = parameters
            .iter()
            .map(|p| match p {
                Datum::List(pair) if pair.len() == 2 && pair[1] == Datum::Atom("ident".into()) => {
                    match &pair[0] {
                        Datum::Atom(name) => Ok(name.clone()),
                        _ => Err(fail("macro parameter identity")),
                    }
                }
                _ => Err(fail("local macro requires typed identifier parameters")),
            })
            .collect::<Result<Vec<_>>>()?;
        if parameters.iter().collect::<BTreeSet<_>>().len() != parameters.len()
            || macros
                .insert(
                    name.clone(),
                    LocalMacro {
                        parameters,
                        body: body.to_vec(),
                    },
                )
                .is_some()
        {
            return Err(fail("duplicate local macro binding"));
        }
        return Ok(());
    }
    if let Some(Datum::Atom(name)) = items.first()
        && let Some(definition) = macros.get(name)
    {
        if definition.parameters.len() + 1 != items.len()
            || items[1..].iter().any(|p| !matches!(p, Datum::Atom(_)))
        {
            return Err(fail("local macro argument shape"));
        }
        let captures = definition
            .parameters
            .iter()
            .cloned()
            .zip(items[1..].iter().cloned())
            .collect::<BTreeMap<_, _>>();
        let expanded = definition
            .body
            .iter()
            .map(|f| substitute(f, &captures))
            .collect::<Vec<_>>();
        for form in expanded {
            expand_form(&form, macros, output, depth + 1)?;
        }
        return Ok(());
    }
    output.push(form.clone());
    Ok(())
}
pub(super) fn substitute(form: &Datum, captures: &BTreeMap<String, Datum>) -> Datum {
    match form {
        Datum::Atom(name) => captures.get(name).cloned().unwrap_or_else(|| form.clone()),
        Datum::List(items) => Datum::List(items.iter().map(|v| substitute(v, captures)).collect()),
        Datum::Text(_) => form.clone(),
    }
}

/// Check declarative syntax at load time even when its constructor has not run.
pub(super) fn validate_syntax(datum: &Datum) -> Result<()> {
    let Datum::List(items) = datum else {
        return Ok(());
    };
    if items.first() == Some(&Datum::Atom("quote".into())) {
        return Ok(());
    }
    if matches!(items.first(),Some(Datum::Atom(tag)) if tag=="ascent" || tag=="ascent-fragment") {
        for (index, form) in items[1..].iter().enumerate() {
            let Datum::List(parts) = form else {
                return Err(fail("DSL declaration form required"));
            };
            match parts.first() {
                Some(Datum::Atom(tag))
                    if tag == "bounds" && (parts.len() != 4 || index + 2 != items.len()) =>
                {
                    return Err(fail("bounds must end the declaration sequence"));
                }
                Some(Datum::Atom(tag)) if tag == "relation" && !(3..=4).contains(&parts.len()) => {
                    return Err(fail("native relation declaration shape"));
                }
                _ => {}
            }
        }
    }
    items.iter().try_for_each(validate_syntax)
}
