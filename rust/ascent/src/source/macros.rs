//! Pattern rules expand in Library scopes before relational admission.
use super::{
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug)]
pub(super) struct Rules {
    literals: BTreeSet<String>,
    clauses: Vec<(Datum, Datum)>,
}
impl Rules {
    pub(super) fn read(items: &[Datum]) -> Result<(String, Self)> {
        let [_, label, literals, clauses @ ..] = items else {
            return Err(invalid("defrules requires literals and pattern clauses"));
        };
        if clauses.is_empty() {
            return Err(invalid("defrules requires a pattern clause"));
        }
        let literals = list(literals)?
            .iter()
            .map(|v| name(v).map(str::to_owned))
            .collect::<Result<BTreeSet<_>>>()?;
        let clauses = clauses
            .iter()
            .map(|c| {
                let [pattern, template] = list(c)? else {
                    return Err(invalid("macro pattern/template required"));
                };
                validate(pattern)?;
                validate(template)?;
                Ok((pattern.clone(), template.clone()))
            })
            .collect::<Result<_>>()?;
        Ok((name(label)?.into(), Self { literals, clauses }))
    }
    pub(super) fn scoped(&self, env: &BTreeMap<String, String>) -> Self {
        Self {
            literals: self.literals.clone(),
            clauses: self
                .clauses
                .iter()
                .map(|(p, t)| {
                    let mut bound = BTreeSet::new();
                    pattern_variables(p, &self.literals, &mut bound);
                    let env = env
                        .iter()
                        .filter(|(key, _)| !bound.contains(*key))
                        .map(|(k, v)| (k.clone(), v.clone()))
                        .collect();
                    (p.clone(), super::functions::scope_calls(t, &env))
                })
                .collect(),
        }
    }
    pub(super) fn apply(&self, form: &Datum, generation: usize) -> Result<Datum> {
        for (pattern, template) in &self.clauses {
            let mut bindings = BTreeMap::new();
            if matches_pattern(pattern, form, &self.literals, &mut bindings) {
                let mut locals = BTreeSet::new();
                rule_variables(template, &mut locals);
                let renames = locals
                    .into_iter()
                    .filter(|n| !bindings.contains_key(n))
                    .map(|n| {
                        (
                            n.clone(),
                            Datum::Atom(format!("__ascent_macro_{generation}_{n}")),
                        )
                    })
                    .collect();
                return Ok(substitute(&substitute(template, &renames), &bindings));
            }
        }
        Err(invalid("no matching macro pattern"))
    }
}
fn pattern_variables(form: &Datum, literals: &BTreeSet<String>, out: &mut BTreeSet<String>) {
    match form {
        Datum::Atom(s) if s != "_" && !literals.contains(s) => {
            out.insert(s.clone());
        }
        Datum::List(items) => {
            for item in items {
                pattern_variables(item, literals, out);
            }
        }
        _ => {}
    }
}
fn validate(form: &Datum) -> Result<()> {
    match form {
        Datum::Atom(s) if s == "..." => {
            Err(invalid("macro ellipsis is not supported by this backend"))
        }
        Datum::List(items) => {
            for item in items {
                validate(item)?;
            }
            Ok(())
        }
        _ => Ok(()),
    }
}
fn matches_pattern(
    pattern: &Datum,
    value: &Datum,
    literals: &BTreeSet<String>,
    bindings: &mut BTreeMap<String, Datum>,
) -> bool {
    match pattern {
        Datum::Atom(s) if s == "_" => true,
        Datum::Atom(s) if !literals.contains(s) => {
            if let Some(previous) = bindings.get(s) {
                previous == value
            } else {
                bindings.insert(s.clone(), value.clone());
                true
            }
        }
        Datum::List(patterns) => match value {
            Datum::List(values) if patterns.len() == values.len() => patterns
                .iter()
                .zip(values)
                .all(|(p, v)| matches_pattern(p, v, literals, bindings)),
            _ => false,
        },
        _ => pattern == value,
    }
}
fn substitute(form: &Datum, bindings: &BTreeMap<String, Datum>) -> Datum {
    match form {
        Datum::Atom(s) => bindings.get(s).cloned().unwrap_or_else(|| form.clone()),
        Datum::List(items) if !matches!(items.first(), Some(Datum::Atom(s)) if s == "quote") => {
            Datum::List(items.iter().map(|v| substitute(v, bindings)).collect())
        }
        _ => form.clone(),
    }
}
fn rule_variables(form: &Datum, out: &mut BTreeSet<String>) {
    let Datum::List(items) = form else {
        return;
    };
    if matches!(items.get(1), Some(Datum::Atom(s)) if s == "<--") {
        out.extend(
            items
                .iter()
                .take(1)
                .chain(items.iter().skip(2))
                .flat_map(atom_variables),
        );
    } else {
        for item in items {
            rule_variables(item, out);
        }
    }
}
fn atom_variables(atom: &Datum) -> impl Iterator<Item = String> + '_ {
    let terms = match atom {
        Datum::List(terms) => terms.as_slice(),
        _ => &[],
    };
    terms.iter().skip(1).filter_map(|term| match term {
        Datum::Atom(name)
            if name != "_"
                && !name.starts_with('#')
                && crate::numbers::parse_number(name).is_none() =>
        {
            Some(name.clone())
        }
        _ => None,
    })
}
