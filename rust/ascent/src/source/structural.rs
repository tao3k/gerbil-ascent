//! Closed structural clauses lower to existing guard/compute relation kernels.
use super::{
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::BTreeSet;

fn atom(value: &str) -> Datum {
    Datum::Atom(value.into())
}
pub(super) fn required(body: &[Datum]) -> bool {
    body.iter().any(|clause| {
        matches!(clause,
        Datum::List(items) if matches!(items.first(),
            Some(Datum::Atom(tag)) if matches!(tag.as_str(), "match" | "for" | "or")))
    })
}
fn form(tag: &str, values: impl IntoIterator<Item = Datum>) -> Datum {
    Datum::List(std::iter::once(atom(tag)).chain(values).collect())
}
fn names(value: &Datum) -> Result<Vec<String>> {
    let values = list(value)?
        .iter()
        .map(|v| name(v).map(str::to_owned))
        .collect::<Result<Vec<_>>>()?;
    if values.iter().collect::<BTreeSet<_>>().len() != values.len() {
        return Err(invalid("distinct structural bindings required"));
    }
    Ok(values)
}
fn pattern<'a>(outputs: &Datum, value: &'a Datum) -> Result<&'a [Datum]> {
    let outputs = names(outputs)?;
    let (tag, fields) = list(value)?
        .split_first()
        .ok_or_else(|| invalid("vector pattern required"))?;
    if name(tag)? != "vector"
        || fields.len() != outputs.len()
        || fields
            .iter()
            .zip(&outputs)
            .any(|(field, output)| name(field).ok() != Some(output.as_str()))
    {
        return Err(invalid(
            "closed vector pattern must name each output once in order",
        ));
    }
    Ok(fields)
}
fn bind(output: Datum, inputs: &Datum, body: Datum) -> Datum {
    form("let", [output, inputs.clone(), body])
}
fn structural(items: &[Datum]) -> Result<Vec<Vec<Datum>>> {
    match items.first().and_then(|v| name(v).ok()) {
        Some("match") => {
            let [_, outputs, inputs, value] = items else {
                return Err(invalid("match output/input/pattern required"));
            };
            let [subject] = list(inputs)? else {
                return Err(invalid("closed vector match requires one input"));
            };
            names(inputs)?;
            let fields = pattern(outputs, value)?;
            let mut clauses = vec![form(
                "if",
                [
                    inputs.clone(),
                    form(
                        "vector-shape?",
                        [subject.clone(), atom(&fields.len().to_string())],
                    ),
                ],
            )];
            clauses.extend(fields.iter().enumerate().map(|(index, output)| {
                bind(
                    output.clone(),
                    inputs,
                    form("vector-ref", [subject.clone(), atom(&index.to_string())]),
                )
            }));
            Ok(vec![clauses])
        }
        Some("for") => {
            let [_, outputs, inputs, generator, value] = items else {
                return Err(invalid("for output/input/generator/pattern required"));
            };
            names(inputs)?;
            let fields = pattern(outputs, value)?;
            let (tag, rows) = list(generator)?
                .split_first()
                .ok_or_else(|| invalid("closed finite row generator required"))?;
            if name(tag)? != "list" || rows.len() > 256 {
                return Err(invalid(
                    "closed generator requires at most 256 explicit vector rows",
                ));
            }
            if rows.is_empty() {
                // Keep the head a derived relation while admitting unreachable
                // outputs. The false guard prevents all value construction.
                let mut clauses = vec![form("if", [inputs.clone(), atom("#f")])];
                clauses.extend(fields.iter().map(|output| {
                    bind(
                        output.clone(),
                        &Datum::List(vec![]),
                        form("lit", [form("quote", [Datum::List(vec![])])]),
                    )
                }));
                return Ok(vec![clauses]);
            }
            rows.iter()
                .map(|row| {
                    let (tag, values) = list(row)?
                        .split_first()
                        .ok_or_else(|| invalid("generator vector required"))?;
                    if name(tag)? != "vector" || values.len() != fields.len() {
                        return Err(invalid("generator vector width mismatch"));
                    }
                    Ok(fields
                        .iter()
                        .zip(values)
                        .map(|(output, value)| bind(output.clone(), inputs, value.clone()))
                        .collect())
                })
                .collect()
        }
        Some("or") => {
            let mut branches = Vec::new();
            for branch in &items[1..] {
                let (tag, body) = list(branch)?
                    .split_first()
                    .ok_or_else(|| invalid("and branch required"))?;
                if name(tag)? != "and" {
                    return Err(invalid("or requires and branches"));
                }
                branches.extend(expand(body)?);
                if branches.len() > 256 {
                    return Err(invalid("structural branch bound"));
                }
            }
            if branches.is_empty() {
                return Err(invalid("nonempty or required"));
            }
            Ok(branches)
        }
        _ => Ok(vec![vec![Datum::List(items.to_vec())]]),
    }
}
pub(super) fn expand(body: &[Datum]) -> Result<Vec<Vec<Datum>>> {
    let mut branches = vec![Vec::new()];
    for clause in body {
        let choices = structural(list(clause)?)?;
        if branches.len().saturating_mul(choices.len()) > 256 {
            return Err(invalid("structural branch bound"));
        }
        branches = branches
            .iter()
            .flat_map(|prefix| {
                choices
                    .iter()
                    .map(move |suffix| prefix.iter().chain(suffix).cloned().collect())
            })
            .collect();
    }
    Ok(branches)
}

#[cfg(test)]
#[path = "../../tests/unit/source_structural.rs"]
mod tests;
