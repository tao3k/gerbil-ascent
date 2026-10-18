//! Typed explanation templates are separate from relational execution admission.
use super::{
    lowering::{list, name},
    reader::{Datum, invalid},
};
use crate::{Data, Result};
use std::collections::BTreeMap;

/// Declared metadata template, independent of checked per-row provenance.
#[derive(Clone, Debug)]
pub struct EvidenceExplanation {
    template: ResultTemplate,
}
#[derive(Clone, Debug)]
enum ResultTemplate {
    Fields(BTreeMap<String, Field>),
    Unavailable(String),
}
#[derive(Clone, Debug)]
enum Field {
    Constant(Data),
    Argument(usize),
    Property(usize, String),
}
impl EvidenceExplanation {
    pub(super) fn read(form: &Datum) -> Self {
        Self {
            template: match compile(form) {
                Ok(fields) => ResultTemplate::Fields(fields),
                Err(e) => ResultTemplate::Unavailable(e.to_string()),
            },
        }
    }
    /// Render declared metadata without replaying or authorizing execution.
    /// # Errors
    /// Unsupported templates are explicit gaps and never weaken query execution.
    pub fn render(&self, program: &Data, result: &Data, query: &str, scope: &Data) -> Result<Data> {
        let ResultTemplate::Fields(fields) = &self.template else {
            let ResultTemplate::Unavailable(reason) = &self.template else {
                unreachable!()
            };
            return Err(invalid(&format!("explanation unavailable: {reason}")));
        };
        let query = Data::Text(query.into());
        let arguments = [program, result, &query, scope];
        fields
            .iter()
            .map(|(key, field)| {
                Ok((
                    key.clone(),
                    match field {
                        Field::Constant(v) => v.clone(),
                        Field::Argument(i) => arguments[*i].clone(),
                        Field::Property(i, key) => arguments[*i].field(key)?.clone(),
                    },
                ))
            })
            .collect::<Result<BTreeMap<_, _>>>()
            .map(Data::Map)
    }
}
fn compile(form: &Datum) -> Result<BTreeMap<String, Field>> {
    let [lambda, parameters, body] = list(form)? else {
        return Err(invalid("explanation lambda shape"));
    };
    if name(lambda)? != "lambda" {
        return Err(invalid("explanation template lambda required"));
    }
    let parameters = list(parameters)?
        .iter()
        .map(name)
        .collect::<Result<Vec<_>>>()?;
    if parameters.len() != 4
        || parameters
            .iter()
            .collect::<std::collections::BTreeSet<_>>()
            .len()
            != 4
    {
        return Err(invalid("explanation requires four distinct parameters"));
    }
    let (hash, fields) = list(body)?
        .split_first()
        .ok_or_else(|| invalid("explanation fields required"))?;
    if name(hash)? != "hash" {
        return Err(invalid(
            "only declared hash explanation templates are supported",
        ));
    }
    let mut output = BTreeMap::new();
    for entry in fields {
        let [Datum::Text(key), value] = list(entry)? else {
            return Err(invalid("literal explanation field name required"));
        };
        let field = field(value, &parameters)?;
        if matches!(field, Field::Argument(1) | Field::Property(1, _)) {
            return Err(invalid(
                "result object explanation binding is not yet supported",
            ));
        }
        if output.insert(key.clone(), field).is_some() {
            return Err(invalid("duplicate explanation field"));
        }
    }
    Ok(output)
}
fn field(value: &Datum, parameters: &[&str]) -> Result<Field> {
    match value {
        Datum::Text(v) => Ok(Field::Constant(v.clone().into())),
        Datum::Atom(v) if parameters.contains(&v.as_str()) => Ok(Field::Argument(
            parameters.iter().position(|p| *p == v).unwrap(),
        )),
        Datum::List(items) => {
            let [operation, parameter, property] = items.as_slice() else {
                return Err(invalid("unsupported explanation expression"));
            };
            if name(operation)? != ".ref" {
                return Err(invalid("unsupported explanation operation"));
            }
            let index = parameters
                .iter()
                .position(|p| *p == name(parameter).unwrap_or(""))
                .ok_or_else(|| invalid("unknown explanation parameter"))?;
            let [quote, key] = list(property)? else {
                return Err(invalid("literal explanation property required"));
            };
            if name(quote)? != "quote" {
                return Err(invalid("literal explanation property required"));
            }
            Ok(Field::Property(index, name(key)?.to_owned()))
        }
        _ => Err(invalid("unsupported explanation field")),
    }
}
