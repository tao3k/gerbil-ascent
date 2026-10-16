//! Local rule templates reuse the existing hygienic pattern expander.
use super::{
    functions::Function,
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn expand(forms: &[Datum]) -> Result<Vec<Datum>> {
    let mut rules = BTreeMap::new();
    let mut output = Vec::new();
    for form in forms {
        let items = list(form)?;
        if matches!(items.first(), Some(Datum::Atom(tag)) if tag == "macro") {
            let (label, rule) = read(items)?;
            if rules.insert(label, rule).is_some() {
                return Err(invalid("duplicate local rule macro"));
            }
        } else {
            output.push(super::functions::expand(form, &rules, 0)?);
        }
    }
    Ok(output)
}

fn read(items: &[Datum]) -> Result<(String, Function)> {
    let [_, label, parameters, template] = items else {
        return Err(invalid("local macro signature/template required"));
    };
    let mut seen = BTreeSet::new();
    let parameters = list(parameters)?
        .iter()
        .map(|parameter| {
            let [binding, kind] = list(parameter)? else {
                return Err(invalid("typed local macro parameter required"));
            };
            if name(kind)? != "expr" || !seen.insert(name(binding)?) {
                return Err(invalid("unique expr macro parameters required"));
            }
            Ok(binding.clone())
        })
        .collect::<Result<Vec<_>>>()?;
    let pattern = std::iter::once(Datum::Atom("_".into()))
        .chain(parameters)
        .collect();
    Function::rules(&[
        Datum::Atom("defrules".into()),
        label.clone(),
        Datum::List(vec![]),
        Datum::List(vec![Datum::List(pattern), template.clone()]),
    ])
}
