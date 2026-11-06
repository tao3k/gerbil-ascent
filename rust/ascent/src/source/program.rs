//! Declarative Evidence entry points lower directly to the Rust relational engine.
use super::{
    lowering::{append, finish, list, name},
    reader::{Datum, invalid, read_all},
};
use crate::{Program, Result};
use std::collections::{BTreeMap, BTreeSet, HashSet};

/// Explicit source authority and query bindings, independent of proof projection.
#[derive(Clone, Debug)]
pub struct RuleProgram {
    pub constructor: String,
    pub sources: BTreeSet<String>,
    pub outputs: Vec<String>,
    pub output_aliases: BTreeMap<String, String>,
    pub program: Program,
    pub explanation: Option<super::RuleExplanation>,
}

impl RuleProgram {
    /// Read declarative definitions and reusable fragments without entering a VM.
    /// Unsupported executable definitions are errors, never a backend fallback.
    /// # Errors
    /// Rejects invalid sources, ambiguous constructors and unsupported definitions.
    pub fn read_sources(sources: &[&str], constructor: Option<&str>) -> Result<Self> {
        let mut fragments = BTreeMap::new();
        let mut entries = BTreeMap::new();
        let mut functions = BTreeMap::new();
        let forms = sources
            .iter()
            .map(|source| read_all(source))
            .collect::<Result<Vec<_>>>()?;
        for form in forms.iter().flatten() {
            definition(form, &mut fragments, &mut entries, &mut functions)?;
        }
        let selected = match constructor {
            Some(label) => label.to_owned(),
            None if entries.len() == 1 => entries
                .keys()
                .next()
                .cloned()
                .ok_or_else(|| invalid("missing Evidence constructor"))?,
            None => return Err(invalid("select one Evidence constructor explicitly")),
        };
        let body = entries
            .get(&selected)
            .ok_or_else(|| invalid("unknown Evidence constructor"))?;
        let body = body
            .iter()
            .map(|form| super::functions::expand(form, &functions, 0))
            .collect::<Result<Vec<_>>>()?;
        let fragments = fragments
            .into_iter()
            .map(|(name, form)| Ok((name, super::functions::expand(&form, &functions, 0)?)))
            .collect::<Result<BTreeMap<_, _>>>()?;
        lower_entry(selected, &body, &fragments)
    }
}

pub(super) fn lower_entry(
    selected: String,
    body: &[Datum],
    fragments: &BTreeMap<String, Datum>,
) -> Result<RuleProgram> {
    if let [form] = body
        && tag(list(form)?) == Some("make-recorded-module")
    {
        return super::recorded::lower(selected, form, fragments);
    }
    let mut input = None;
    let mut output = None;
    let mut forms = Vec::new();
    let mut explanation = None;
    let body = body
        .iter()
        .map(|form| super::graphs::resolve(form, fragments))
        .collect::<Result<Vec<_>>>()?;
    for form in &body {
        let items = list(form)?;
        match tag(items) {
            Some("sources") => binding(&mut input, &items[1..], false)?,
            Some("outputs") => binding(&mut output, &items[1..], true)?,
            Some("explain") => {
                let [_, value] = items else {
                    return Err(invalid("one explanation definition required"));
                };
                if explanation.is_some() {
                    return Err(invalid("duplicate explanation definition"));
                }
                explanation = Some(super::RuleExplanation::read(value));
            }
            _ => expand(form, fragments, &mut BTreeSet::new(), &mut forms)?,
        }
    }
    let inputs = input.ok_or_else(|| invalid("Evidence sources declaration required"))?;
    let outputs = output.ok_or_else(|| invalid("Evidence outputs declaration required"))?;
    let fragment = Datum::List(
        std::iter::once(Datum::Atom("ascent".into()))
            .chain(forms)
            .collect(),
    );
    let mut program = Program::default();
    append(
        &mut program,
        &mut BTreeMap::new(),
        &mut HashSet::new(),
        &fragment,
        true,
    )?;
    let mut program = finish(program)?;
    let declared: BTreeSet<_> = program.relations.iter().map(|r| r.name.clone()).collect();
    if inputs
        .iter()
        .chain(&outputs)
        .any(|(_, target)| !declared.contains(target))
    {
        return Err(invalid(
            "Evidence source/output names an undeclared relation",
        ));
    }
    let sources: BTreeSet<_> = inputs.into_iter().map(|(_, target)| target).collect();
    if outputs
        .iter()
        .any(|(alias, target)| alias != target && declared.contains(alias))
    {
        return Err(invalid("Evidence output alias shadows a declared relation"));
    }
    let output_aliases = outputs.iter().cloned().collect();
    let outputs = outputs.into_iter().map(|(alias, _)| alias).collect();
    for relation in &mut program.relations {
        relation.source = sources.contains(&relation.name);
    }
    crate::graph::Graph::build(program.clone())?;
    Ok(RuleProgram {
        constructor: selected,
        sources,
        outputs,
        output_aliases,
        program,
        explanation,
    })
}

pub(super) fn definition(
    form: &Datum,
    fragments: &mut BTreeMap<String, Datum>,
    entries: &mut BTreeMap<String, Vec<Datum>>,
    functions: &mut BTreeMap<String, super::functions::Function>,
) -> Result<()> {
    let items = list(form)?;
    match tag(items) {
        Some("defrules") => {
            let (label, rules) = super::functions::Function::rules(items)?;
            if functions.insert(label, rules).is_some() {
                return Err(invalid("duplicate macro binding"));
            }
        }
        Some("def") => {
            let [_, label, bodies @ ..] = items else {
                return Err(invalid("definition requires binding and body"));
            };
            if bodies.is_empty() {
                return Err(invalid("definition body required"));
            }
            let sequence;
            let fragment = if let [body] = bodies {
                body
            } else {
                if !matches!(label, Datum::List(_)) {
                    return Err(invalid("immutable binding requires one value"));
                }
                sequence = Datum::List(
                    std::iter::once(Datum::Atom("begin".into()))
                        .chain(bodies.iter().cloned())
                        .collect(),
                );
                &sequence
            };
            if matches!(label, Datum::List(_)) {
                if let [label] = list(label)?
                    && matches!(fragment, Datum::List(items) if tag(items) == Some("make-recorded-module"))
                {
                    if entries
                        .insert(name(label)?.into(), vec![fragment.clone()])
                        .is_some()
                    {
                        return Err(invalid("duplicate Evidence constructor"));
                    }
                    return Ok(());
                }
                let (label, function) = super::functions::Function::read(label, fragment)?;
                if functions.insert(label, function).is_some() {
                    return Err(invalid("duplicate pure function binding"));
                }
                return Ok(());
            }
            if matches!(fragment, Datum::List(items) if tag(items) == Some("relational-op-fragment"))
            {
                if fragments
                    .insert(name(label)?.into(), super::graphs::fragment(fragment)?)
                    .is_some()
                {
                    return Err(invalid("duplicate relational graph binding"));
                }
                return Ok(());
            }
            if !matches!(fragment, Datum::List(items) if tag(items) == Some("ascent-fragment")) {
                let value = super::functions::Function::constant(fragment)?;
                if functions.insert(name(label)?.into(), value).is_some() {
                    return Err(invalid("duplicate immutable binding"));
                }
                return Ok(());
            }
            if fragments
                .insert(name(label)?.to_owned(), fragment.clone())
                .is_some()
            {
                return Err(invalid("duplicate Evidence Fragment binding"));
            }
        }
        Some("define-program") => {
            let [_, signature, body @ ..] = items else {
                return Err(invalid("Evidence constructor signature required"));
            };
            let [label] = list(signature)? else {
                return Err(invalid(
                    "parameterized Evidence constructors are not supported",
                ));
            };
            if entries
                .insert(name(label)?.to_owned(), body.to_vec())
                .is_some()
            {
                return Err(invalid("duplicate Evidence constructor"));
            }
        }
        _ => return Err(invalid("unsupported Evidence top-level definition")),
    }
    Ok(())
}

fn binding(
    slot: &mut Option<Vec<(String, String)>>,
    values: &[Datum],
    aliases: bool,
) -> Result<()> {
    if slot.is_some() {
        return Err(invalid("duplicate Evidence source/output declaration"));
    }
    let labels = values
        .iter()
        .map(|v| match v {
            Datum::List(items) => {
                let [label, reference] = items.as_slice() else {
                    return Err(invalid("source/output binding shape"));
                };
                if !aliases && name(label)? != name(reference)? {
                    return Err(invalid("source/output alias must match exported relation"));
                }
                Ok((name(label)?.to_owned(), name(reference)?.to_owned()))
            }
            _ => name(v).map(|name| (name.to_owned(), name.to_owned())),
        })
        .collect::<Result<Vec<_>>>()?;
    if labels
        .iter()
        .map(|(label, _)| label)
        .collect::<BTreeSet<_>>()
        .len()
        != labels.len()
        || labels
            .iter()
            .map(|(_, target)| target)
            .collect::<BTreeSet<_>>()
            .len()
            != labels.len()
    {
        return Err(invalid("duplicate Evidence source/output binding"));
    }
    *slot = Some(labels);
    Ok(())
}

pub(super) fn expand(
    form: &Datum,
    fragments: &BTreeMap<String, Datum>,
    stack: &mut BTreeSet<String>,
    out: &mut Vec<Datum>,
) -> Result<()> {
    let items = list(form)?;
    if tag(items) == Some("ascent-fragment") {
        for child in &items[1..] {
            expand(child, fragments, stack, out)?;
        }
        return Ok(());
    }
    if tag(items) != Some("include") {
        out.push(form.clone());
        return Ok(());
    }
    let [_, label] = items else {
        return Err(invalid("include requires one Fragment binding"));
    };
    if let Datum::List(children) = label
        && tag(children) == Some("gerbil-ascent-fragment")
    {
        let fragment = super::declarations::fragment(label)?;
        return expand(
            &Datum::List(vec![Datum::Atom("include".into()), fragment]),
            fragments,
            stack,
            out,
        );
    }
    if let Datum::List(children) = label
        && tag(children) == Some("ascent-fragment")
    {
        for child in &children[1..] {
            expand(child, fragments, stack, out)?;
        }
        return Ok(());
    }
    let label = name(label)?;
    if !stack.insert(label.to_owned()) {
        return Err(invalid("cyclic Evidence Fragment inclusion"));
    }
    let fragment = fragments
        .get(label)
        .ok_or_else(|| invalid("unbound Evidence Fragment"))?;
    for child in &list(fragment)?[1..] {
        expand(child, fragments, stack, out)?;
    }
    stack.remove(label);
    Ok(())
}

fn tag(items: &[Datum]) -> Option<&str> {
    match items.first() {
        Some(Datum::Atom(tag)) => Some(tag),
        _ => None,
    }
}
