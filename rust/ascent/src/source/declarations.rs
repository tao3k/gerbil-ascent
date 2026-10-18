//! Closed declaration constructors, not arbitrary host-language execution.
use super::{
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::BTreeMap;

pub(super) fn fragment(value: &Datum) -> Result<Datum> {
    evaluate(value, &BTreeMap::new(), 0)
}
fn evaluate(value: &Datum, env: &BTreeMap<String, Datum>, depth: usize) -> Result<Datum> {
    if depth > 128 {
        return Err(invalid("declaration constructor depth bound"));
    }
    let Datum::List(items) = value else {
        return Ok(match value {
            Datum::Atom(s) => env.get(s).cloned().unwrap_or_else(|| value.clone()),
            _ => value.clone(),
        });
    };
    if items.is_empty() {
        return Ok(value.clone());
    }
    let tag = name(&items[0])?;
    if tag == "quote" {
        let [_, body] = items.as_slice() else {
            return Err(invalid("declaration quote arity"));
        };
        return Ok(body.clone());
    }
    if tag == "let" {
        let [_, bindings, body] = items.as_slice() else {
            return Err(invalid("declaration let shape"));
        };
        let [binding, expression] = list(bindings)? else {
            return Err(invalid("declaration let requires one binding"));
        };
        let mut env = env.clone();
        let value = evaluate(expression, &env, depth + 1)?;
        env.insert(name(binding)?.into(), value);
        return evaluate(body, &env, depth + 1);
    }
    let args = items[1..]
        .iter()
        .map(|v| evaluate(v, env, depth + 1))
        .collect::<Result<Vec<_>>>()?;
    match (tag, args.as_slice()) {
        ("list", _) => Ok(Datum::List(args)),
        ("gerbil-ascent-variable", [label]) => {
            name(label)?;
            Ok(label.clone())
        }
        ("gerbil-ascent-atom", [label, terms]) => Ok(Datum::List(
            std::iter::once(Datum::Atom(name(label)?.into()))
                .chain(list(terms)?.iter().cloned())
                .collect(),
        )),
        ("gerbil-ascent-rule", [heads, body]) => {
            if list(heads)?.is_empty() {
                return Err(invalid("nonempty declaration rule head required"));
            }
            Ok(Datum::List(
                std::iter::once(heads.clone())
                    .chain(std::iter::once(Datum::Atom("<--".into())))
                    .chain(list(body)?.iter().cloned())
                    .collect(),
            ))
        }
        ("gerbil-ascent-fragment", [relations, rules]) => Ok(Datum::List(
            std::iter::once(Datum::Atom("ascent-fragment".into()))
                .chain(list(relations)?.iter().cloned())
                .chain(list(rules)?.iter().cloned())
                .collect(),
        )),
        _ => Err(invalid("unsupported closed declaration constructor")),
    }
}
