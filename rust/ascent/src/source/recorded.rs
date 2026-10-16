//! Library recorded-module constructor lowering; no host procedure evaluation.
use super::{
    evidence::{EvidenceProgram, expand, lower_entry},
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::Result;
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn lower(
    selected: String,
    form: &Datum,
    fragments: &BTreeMap<String, Datum>,
) -> Result<EvidenceProgram> {
    let [_, fragment, sources, limits @ ..] = list(form)? else {
        return Err(invalid(
            "recorded module requires fragment and source authority",
        ));
    };
    if limits.len() > 3 {
        return Err(invalid("recorded module has at most three fact ceilings"));
    }
    let [quote, sources] = list(sources)? else {
        return Err(invalid("literal recorded source authority required"));
    };
    if name(quote)? != "quote" {
        return Err(invalid("literal recorded source authority required"));
    }
    let mut forms = Vec::new();
    expand(
        &Datum::List(vec![Datum::Atom("include".into()), fragment.clone()]),
        fragments,
        &mut BTreeSet::new(),
        &mut forms,
    )?;
    let outputs = forms.iter().filter_map(|form| match form {
        Datum::List(items) if matches!(items.first(), Some(Datum::Atom(tag)) if tag == "relation" || tag == "lattice") => items.get(1).cloned(),
        _ => None,
    }).collect::<Vec<_>>();
    let mut body = vec![
        Datum::List(
            std::iter::once(Datum::Atom("sources".into()))
                .chain(list(sources)?.iter().cloned())
                .collect(),
        ),
        Datum::List(
            std::iter::once(Datum::Atom("outputs".into()))
                .chain(outputs)
                .collect(),
        ),
    ];
    if !limits.is_empty() {
        body.push(Datum::List(
            std::iter::once(Datum::Atom("bounds".into()))
                .chain((0..3).map(|i| {
                    limits
                        .get(i)
                        .cloned()
                        .unwrap_or(Datum::Atom("+inf.0".into()))
                }))
                .collect(),
        ));
    }
    body.extend(forms);
    lower_entry(selected, &body, fragments)
}
