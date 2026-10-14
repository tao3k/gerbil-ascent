//! Native owned catalog admission shared by every language binding and workflow.
use super::clauses;
use crate::{Data, Program, Relation, Result, Rule, Type, Value, invalid_data as invalid};
use std::collections::{BTreeMap, BTreeSet};
pub(crate) fn shape(value: &Data, required: &[&str], optional: &[&str]) -> Result<()> {
    let fields = value.map()?;
    if required.iter().any(|k| !fields.contains_key(*k))
        || fields
            .keys()
            .any(|k| !required.contains(&k.as_str()) && !optional.contains(&k.as_str()))
    {
        return Err(invalid("catalog fields"));
    }
    Ok(())
}
pub(crate) fn scalar(value: &Data, ty: Type) -> Result<Value> {
    match value {
        Data::Integer(n) => Ok(Value::Integer(n.clone())),
        Data::Bool(v) => Ok(Value::Boolean(*v)),
        Data::Text(v) if matches!(ty, Type::Symbol | Type::Scalar) && v.len() <= 4096 => {
            Ok(Value::Symbol(v.as_str().into()))
        }
        Data::Text(v) => Ok(Value::Text(v.as_str().into())),
        _ => Err(invalid("typed catalog scalar required")),
    }
}
/// Fully owned program and explicit observation projection, independent from Python.
#[derive(Clone, Debug)]
pub struct Catalog {
    pub program: Program,
    pub queries: Vec<String>,
}
impl Catalog {
    /// # Errors
    /// Rejects unknown fields, malformed types/terms and unrecognized operators.
    pub fn read(value: &Data) -> Result<Self> {
        shape(value, &["relations", "rules"], &["queries"])?;
        let mut program = Program {
            relations: value
                .field("relations")?
                .list()?
                .iter()
                .map(read_relation)
                .collect::<Result<_>>()?,
            ..Program::default()
        };
        let declarations = program
            .relations
            .iter()
            .map(|r| (r.name.clone(), r))
            .collect::<BTreeMap<_, _>>();
        if declarations.len() != program.relations.len() {
            return Err(invalid("duplicate relation"));
        }
        program.rules = value
            .field("rules")?
            .list()?
            .iter()
            .map(|rule| read_rule(rule, &declarations))
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .flatten()
            .collect();
        let queries = value
            .get("queries")
            .map(|v| {
                v.list()?
                    .iter()
                    .map(|v| v.text().map(str::to_string))
                    .collect::<Result<Vec<_>>>()
            })
            .transpose()?
            .unwrap_or_else(|| program.relations.iter().map(|r| r.name.clone()).collect());
        if queries.iter().any(|q| !declarations.contains_key(q)) {
            return Err(invalid("unknown query"));
        }
        Ok(Self { program, queries })
    }
}
pub(crate) fn read_relation(raw: &Data) -> Result<Relation> {
    shape(raw, &["name", "columns", "source"], &["rows"])?;
    let name = raw.field("name")?.identity()?;
    let columns = raw.field("columns")?.list()?;
    if columns.len() > 16 {
        return Err(invalid("column bound"));
    }
    let (types, domains): (Vec<_>, Vec<_>) = columns
        .iter()
        .map(read_column)
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .unzip();
    let mut relation = Relation::new(name, types, raw.field("source")?.boolean()?);
    relation.domains = domains;
    if let Some(rows) = raw.get("rows") {
        relation.rows = rows
            .list()?
            .iter()
            .map(|row| {
                let cells = row.list()?;
                if cells.len() != relation.columns.len() {
                    return Err(invalid("source tuple arity"));
                }
                cells
                    .iter()
                    .zip(&relation.columns)
                    .map(|(v, ty)| scalar(v, *ty))
                    .collect::<Result<Vec<_>>>()
                    .map(Into::into)
            })
            .collect::<Result<_>>()?;
    }
    Ok(relation)
}

fn read_rule(raw: &Data, declarations: &BTreeMap<String, &Relation>) -> Result<Vec<Rule>> {
    shape(raw, &["head", "body"], &[])?;
    let mut names = BTreeMap::new();
    let body = raw
        .field("body")?
        .list()?
        .iter()
        .map(|c| clauses::clause(c, declarations, &mut names))
        .collect::<Result<Vec<_>>>()?;
    let heads = raw.field("head")?.list()?;
    if heads.is_empty() {
        return Err(invalid("nonempty rule head required"));
    }
    heads
        .iter()
        .map(|head| {
            shape(head, &["relation", "terms"], &["not"])?;
            if head
                .get("not")
                .map(Data::boolean)
                .transpose()?
                .unwrap_or(false)
            {
                return Err(invalid("negative rule head"));
            }
            Ok(Rule {
                head: clauses::atom(head, declarations, &mut names)?,
                body: body.clone(),
            })
        })
        .collect()
}
fn read_column(column: &Data) -> Result<(Type, Option<BTreeSet<Value>>)> {
    shape(column, &["kind"], &["domain"])?;
    let ty = match column.field("kind")?.text()? {
        "scalar" => Type::Scalar,
        "value" => Type::Any,
        "integer" => Type::Integer,
        "boolean" => Type::Boolean,
        "symbol" => Type::Symbol,
        "string" | "text" => Type::Text,
        _ => return Err(invalid("unsupported column kind")),
    };
    let domain = column
        .get("domain")
        .map(|v| {
            v.list()?
                .iter()
                .map(|v| scalar(v, ty))
                .collect::<Result<BTreeSet<_>>>()
        })
        .transpose()?;
    Ok((ty, domain))
}
