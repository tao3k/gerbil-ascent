//! Closed relational graphs lower to the same checked relations and rules.
use super::{
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::BTreeMap;

fn atom(s: &str) -> Datum {
    Datum::Atom(s.into())
}
fn form(tag: &str, values: impl IntoIterator<Item = Datum>) -> Datum {
    Datum::List(std::iter::once(atom(tag)).chain(values).collect())
}
fn symbol(value: &Datum) -> Result<&str> {
    let [Datum::Atom(quote), label] = list(value)? else {
        return Err(invalid("quoted graph label required"));
    };
    if quote != "quote" {
        return Err(invalid("quoted graph label required"));
    }
    name(label)
}
fn indices(value: &Datum) -> Result<Vec<usize>> {
    let [Datum::Atom(quote), values] = list(value)? else {
        return Err(invalid("quoted projection indices required"));
    };
    if quote != "quote" {
        return Err(invalid("quoted projection indices required"));
    }
    list(values)?.iter().map(index).collect()
}
fn index(value: &Datum) -> Result<usize> {
    name(value)?
        .parse()
        .map_err(|_| invalid("nonnegative graph index required"))
}
fn relation(label: &str, width: usize, rows: Option<&Datum>) -> Datum {
    let mut values = vec![
        atom(label),
        Datum::List((0..width).map(|i| atom(&format!("column{i}"))).collect()),
    ];
    if let Some(rows) = rows {
        values.push(rows.clone());
    }
    form("relation", values)
}
fn terms(width: usize) -> Vec<Datum> {
    (0..width)
        .map(|i| atom(&format!("__ascent_graph_v{i}")))
        .collect()
}
fn rule(label: &str, output: Vec<Datum>, body: Vec<Datum>) -> Datum {
    Datum::List(
        std::iter::once(form(label, output))
            .chain(std::iter::once(atom("<--")))
            .chain(body)
            .collect(),
    )
}
pub(super) fn fragment(value: &Datum) -> Result<Datum> {
    let [_, expression, label] = list(value)? else {
        return Err(invalid("graph fragment needs operator and label"));
    };
    let label = symbol(label)?;
    let mut forms = Vec::new();
    let mut serial = 0;
    let (output, width) = lower(expression, label, &mut forms, &mut serial)?;
    if output != label {
        forms.push(relation(label, width, None));
        forms.push(rule(label, terms(width), vec![form(&output, terms(width))]));
    }
    Ok(form("ascent-fragment", forms))
}
fn lower(
    expression: &Datum,
    namespace: &str,
    forms: &mut Vec<Datum>,
    serial: &mut usize,
) -> Result<(String, usize)> {
    let items = list(expression)?;
    let Some(tag) = items.first() else {
        return Err(invalid("relational graph required"));
    };
    if name(tag)? == "relational-op-source" {
        let [_, label, width, rows] = items else {
            return Err(invalid("graph source needs label, width and rows"));
        };
        let label = symbol(label)?.to_owned();
        let width = index(width)?;
        if width > 16 {
            return Err(invalid("ASCENT column bound"));
        }
        let declaration = relation(&label, width, Some(rows));
        if let Some(previous) = forms.iter().find(|f| matches!(f, Datum::List(items) if items.first() == Some(&atom("relation")) && items.get(1) == Some(&atom(&label)))) {
            if previous != &declaration { return Err(invalid("conflicting graph source declarations")); }
        } else { forms.push(declaration); }
        return Ok((label, width));
    }
    let label = format!("__ascent_graph_{namespace}_{}", *serial);
    *serial = serial
        .checked_add(1)
        .ok_or_else(|| invalid("graph identity overflow"))?;
    match name(tag)? {
        "relational-op-project" => {
            let [_, input, columns] = items else {
                return Err(invalid("projection needs operator and indices"));
            };
            let (source, width) = lower(input, namespace, forms, serial)?;
            let columns = indices(columns)?;
            if columns.iter().any(|i| *i >= width) {
                return Err(invalid("projection column outside source"));
            }
            let variables = terms(width);
            forms.push(relation(&label, columns.len(), None));
            forms.push(rule(
                &label,
                columns.iter().map(|i| variables[*i].clone()).collect(),
                vec![form(&source, variables)],
            ));
            Ok((label, columns.len()))
        }
        "relational-op-union" => {
            let [_, left, right] = items else {
                return Err(invalid("union needs two operators"));
            };
            let (left, width) = lower(left, namespace, forms, serial)?;
            let (right, other) = lower(right, namespace, forms, serial)?;
            if width != other {
                return Err(invalid("union column mismatch"));
            }
            forms.push(relation(&label, width, None));
            for source in [left, right] {
                forms.push(rule(
                    &label,
                    terms(width),
                    vec![form(&source, terms(width))],
                ));
            }
            Ok((label, width))
        }
        "relational-op-join" => {
            let [_, left, right, left_key, right_key] = items else {
                return Err(invalid("join needs two operators and column indices"));
            };
            let (left, left_width) = lower(left, namespace, forms, serial)?;
            let (right, right_width) = lower(right, namespace, forms, serial)?;
            let (left_key, right_key) = (index(left_key)?, index(right_key)?);
            if left_key >= left_width || right_key >= right_width {
                return Err(invalid("join column outside source"));
            }
            let width = left_width
                .checked_add(right_width)
                .filter(|w| *w <= 16)
                .ok_or_else(|| invalid("ASCENT column bound"))?;
            let left_terms = terms(left_width);
            let mut right_terms = terms(width)[left_width..].to_vec();
            right_terms[right_key] = left_terms[left_key].clone();
            let output = left_terms.iter().chain(&right_terms).cloned().collect();
            forms.push(relation(&label, width, None));
            forms.push(rule(
                &label,
                output,
                vec![form(&left, left_terms), form(&right, right_terms)],
            ));
            Ok((label, width))
        }
        _ => Err(invalid("unsupported relational graph operator")),
    }
}
pub(super) fn resolve(value: &Datum, fragments: &BTreeMap<String, Datum>) -> Result<Datum> {
    let Datum::List(items) = value else {
        return Ok(value.clone());
    };
    if matches!(items.first(),Some(Datum::Atom(tag)) if tag == "quote") {
        return Ok(value.clone());
    }
    if matches!(items.first(),Some(Datum::Atom(tag)) if tag == "relational-export") {
        let [_, owner, label] = items.as_slice() else {
            return Err(invalid("export needs graph and label"));
        };
        let label = symbol(label)?;
        let fragment = fragments
            .get(name(owner)?)
            .ok_or_else(|| invalid("unbound relational graph"))?;
        if !list(fragment)?.iter().skip(1).any(|f| matches!(f, Datum::List(row) if row.first() == Some(&atom("relation")) && row.get(1) == Some(&atom(label)))) {
            return Err(invalid("relation is not exported by graph"));
        }
        return Ok(atom(label));
    }
    items
        .iter()
        .map(|item| resolve(item, fragments))
        .collect::<Result<Vec<_>>>()
        .map(Datum::List)
}
