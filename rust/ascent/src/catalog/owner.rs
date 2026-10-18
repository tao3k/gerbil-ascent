//! Scheme owned catalog admission shared by every language binding and workflow.
use super::clauses;
pub(crate) use super::values::shape;
use super::values::{scalar, scalar_in};
use crate::{Data, Program, Relation, Result, Rule, Type, Value, invalid_data as invalid};
use std::collections::{BTreeMap, BTreeSet};
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
        shape(value, &["relations", "rules"], &["queries", "values"])?;
        let pool = read_pool(value.get("values"))?;
        let mut program = Program {
            relations: value
                .field("relations")?
                .list()?
                .iter()
                .map(|r| read_relation_in(r, &pool))
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
            .map(|rule| read_rule(rule, &declarations, &pool))
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
    read_relation_in(raw, &[])
}
fn read_relation_in(raw: &Data, pool: &[Value]) -> Result<Relation> {
    shape(
        raw,
        &["name", "columns", "source"],
        &["rows", "lattice", "initialOccurrences"],
    )?;
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
    relation.initial_occurrences = raw
        .get("initialOccurrences")
        .map(Data::boolean)
        .transpose()?
        .unwrap_or(false);
    relation.lattice = raw
        .get("lattice")
        .map(|v| match v.text()? {
            "min" => Ok(crate::LatticeJoin::Min),
            "max" => Ok(crate::LatticeJoin::Max),
            _ => Err(invalid("unsupported native lattice")),
        })
        .transpose()?;
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
                    .map(|(v, ty)| scalar_in(v, *ty, pool))
                    .collect::<Result<Vec<_>>>()
                    .map(Into::into)
            })
            .collect::<Result<_>>()?;
    }
    Ok(relation)
}

fn read_rule(
    raw: &Data,
    declarations: &BTreeMap<String, &Relation>,
    pool: &[Value],
) -> Result<Vec<Rule>> {
    shape(raw, &["head", "body"], &[])?;
    let mut names = BTreeMap::new();
    let body = raw
        .field("body")?
        .list()?
        .iter()
        .map(|c| clauses::clause(c, declarations, &mut names, pool))
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
                head: clauses::atom(head, declarations, &mut names, pool)?,
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
        "number" => Type::Number,
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

fn read_pool(value: Option<&Data>) -> Result<Vec<Value>> {
    let Some(value) = value else {
        return Ok(vec![]);
    };
    let graph = crate::ObjectGraph::read_scheme(value)?;
    let crate::GraphItem::Reference(id) = graph.root else {
        return Err(invalid("owned value pool root"));
    };
    let Some(crate::ObjectNode::Vector(roots)) = graph.nodes.get(&id) else {
        return Err(invalid("owned value pool vector required"));
    };
    let identity = crate::allocate_source_identity()?;
    roots
        .iter()
        .map(|root| {
            crate::FrozenValue::new(
                identity,
                identity,
                crate::ObjectGraph {
                    root: root.clone(),
                    nodes: graph.nodes.clone(),
                },
            )
            .map(Value::Object)
        })
        .collect()
}
