//! Dependency slicing and typed loading of inert Datalog; execution stays in the Rust engine.
use super::{inference, parser};
use crate::{
    Cancellation, Catalog, Data, Engine, FactLimits, Limits, Result, invalid_data as invalid,
};
use std::collections::{BTreeMap, BTreeSet};
/// Declarative input for a bounded reader, never a Python program or build request.
pub struct DatalogRequest<'a> {
    pub facts: &'a Data,
    pub source: &'a str,
    pub queries: &'a Data,
    pub schema: Option<&'a Data>,
}
/// Scheme graph data and presentation-only query aliases; it grants no source authority.
pub struct DatalogGraph {
    pub program: Data,
    pub queries: Data,
}
/// Read inert rules into the same typed graph used by native Scheme source loading.
/// # Errors
/// Rejects unsupported syntax, unsafe variables, changed source authority and inconsistent types.
pub fn read_datalog(request: &DatalogRequest<'_>) -> Result<DatalogGraph> {
    Parsed::read(request)?.lower(request)
}
struct Parsed {
    typed: bool,
    rules: Vec<Data>,
    queries: BTreeMap<String, Data>,
    definitions: BTreeMap<String, Vec<usize>>,
    widths: BTreeMap<String, usize>,
    selected: BTreeSet<usize>,
}
impl Parsed {
    fn read(request: &DatalogRequest<'_>) -> Result<Self> {
        let typed = request.schema.is_some_and(|s| !matches!(s, Data::Null));
        let rules = parser::rules(request.source, typed)?;
        let queries = read_queries(request.queries)?;
        let definitions = definitions(&rules)?;
        let (widths, selected) = slice(request.facts, &queries, &rules, &definitions)?;
        Ok(Self {
            typed,
            rules,
            queries,
            definitions,
            widths,
            selected,
        })
    }
    fn lower(self, request: &DatalogRequest<'_>) -> Result<DatalogGraph> {
        let Self {
            typed,
            rules,
            queries,
            definitions,
            widths,
            selected,
        } = self;
        let schema = schema(request, &rules, &queries, &widths)?;
        let relations = widths
            .iter()
            .map(|(name, width)| declaration(name, *width, request.facts, &definitions, &schema))
            .collect::<Result<Vec<_>>>()?;
        let selected = selected
            .into_iter()
            .map(|i| rules[i].clone())
            .collect::<Vec<_>>();
        validate_operators(&selected, typed)?;
        if matches!(request.schema, Some(Data::Map(_))) {
            inference::validate_schema(request.facts, &selected, &schema)?;
        }
        let wanted = queries
            .values()
            .map(|q| q.field("relation")?.text().map(str::to_string))
            .collect::<Result<BTreeSet<_>>>()?;
        let program = Data::object([
            ("relations", Data::List(relations)),
            ("rules", Data::List(selected)),
            (
                "queries",
                Data::List(wanted.into_iter().map(Data::from).collect()),
            ),
        ]);
        let admitted = Catalog::read(&program)?;
        crate::graph::Graph::build(admitted.program)?;
        Ok(DatalogGraph {
            program,
            queries: Data::Map(queries),
        })
    }
}

fn read_queries(queries: &Data) -> Result<BTreeMap<String, Data>> {
    queries
        .map()?
        .iter()
        .map(|(label, source)| {
            let query = parser::query(source.text()?)?;
            let terms = query.field("terms")?.list()?;
            let variables = terms
                .iter()
                .map(|t| t.get("var").and_then(|v| v.text().ok()))
                .collect::<BTreeSet<_>>();
            if query.field("not")?.boolean()?
                || variables.contains(&None)
                || variables.len() != terms.len()
            {
                return Err(invalid(
                    "queries must request all distinct relation columns",
                ));
            }
            Ok((label.clone(), query))
        })
        .collect()
}
fn definitions(rules: &[Data]) -> Result<BTreeMap<String, Vec<usize>>> {
    let mut out = BTreeMap::<String, Vec<usize>>::new();
    for (i, rule) in rules.iter().enumerate() {
        let head = &rule.field("head")?.list()?[0];
        out.entry(head.field("relation")?.text()?.into())
            .or_default()
            .push(i);
    }
    Ok(out)
}
fn slice(
    facts: &Data,
    queries: &BTreeMap<String, Data>,
    rules: &[Data],
    definitions: &BTreeMap<String, Vec<usize>>,
) -> Result<(BTreeMap<String, usize>, BTreeSet<usize>)> {
    let facts = facts.map()?;
    let mut pending = queries.values().cloned().collect::<Vec<_>>();
    let mut selected = BTreeSet::new();
    let mut widths = BTreeMap::new();
    let mut visited = BTreeSet::new();
    while let Some(current) = pending.pop() {
        let name = current.field("relation")?.text()?;
        let width = current.field("terms")?.list()?.len();
        if widths
            .insert(name.to_string(), width)
            .is_some_and(|old| old != width)
        {
            return Err(invalid("inconsistent relation arity"));
        }
        if !visited.insert(name.to_string()) {
            continue;
        }
        visit_relation(name, facts, definitions, rules, &mut pending, &mut selected)?;
    }
    Ok((widths, selected))
}
fn visit_relation(
    name: &str,
    facts: &BTreeMap<String, Data>,
    definitions: &BTreeMap<String, Vec<usize>>,
    rules: &[Data],
    pending: &mut Vec<Data>,
    selected: &mut BTreeSet<usize>,
) -> Result<()> {
    let Some(indices) = definitions.get(name) else {
        if !facts.contains_key(name) {
            return Err(invalid("undeclared source relation"));
        }
        return Ok(());
    };
    if facts
        .get(name)
        .map(Data::list)
        .transpose()?
        .is_some_and(|r| !r.is_empty())
    {
        return Err(invalid("derived relation cannot contain source facts"));
    }
    for &i in indices {
        selected.insert(i);
        let rule = &rules[i];
        pending.extend_from_slice(rule.field("head")?.list()?);
        pending.extend(
            rule.field("body")?
                .list()?
                .iter()
                .filter(|c| c.get("relation").is_some())
                .cloned(),
        );
    }
    Ok(())
}
fn schema(
    request: &DatalogRequest<'_>,
    rules: &[Data],
    queries: &BTreeMap<String, Data>,
    widths: &BTreeMap<String, usize>,
) -> Result<BTreeMap<String, Vec<String>>> {
    match request.schema {
        None | Some(Data::Null) => Ok(widths
            .iter()
            .map(|(n, w)| (n.clone(), vec!["value".into(); *w]))
            .collect()),
        Some(Data::Text(v)) if v == "infer" => inference::infer(request.facts, rules, queries),
        Some(value) => value
            .map()?
            .iter()
            .map(|(n, k)| {
                k.list()?
                    .iter()
                    .map(|k| k.text().map(str::to_string))
                    .collect::<Result<Vec<_>>>()
                    .map(|k| (n.clone(), k))
            })
            .collect(),
    }
}
fn declaration(
    name: &str,
    width: usize,
    facts: &Data,
    definitions: &BTreeMap<String, Vec<usize>>,
    schema: &BTreeMap<String, Vec<String>>,
) -> Result<Data> {
    let kinds = schema
        .get(name)
        .ok_or_else(|| invalid("complete typed relation schema required"))?;
    if kinds.len() != width
        || kinds.iter().any(|k| {
            !["value", "symbol", "string", "text", "integer", "boolean"].contains(&k.as_str())
        })
    {
        return Err(invalid("complete typed relation schema required"));
    }
    let source = !definitions.contains_key(name);
    let rows = if source {
        facts
            .get(name)
            .cloned()
            .unwrap_or_else(|| Data::List(Vec::new()))
    } else {
        Data::List(Vec::new())
    };
    if rows
        .list()?
        .iter()
        .any(|r| r.list().is_err() || r.list().is_ok_and(|r| r.len() != width))
    {
        return Err(invalid("source row arity mismatch"));
    }
    Ok(Data::object([
        ("name", name.into()),
        ("source", source.into()),
        (
            "columns",
            Data::List(
                kinds
                    .iter()
                    .map(|kind| Data::object([("kind", kind.clone().into())]))
                    .collect(),
            ),
        ),
        ("rows", rows),
    ]))
}
fn validate_operators(rules: &[Data], typed: bool) -> Result<()> {
    if !typed
        && rules.iter().any(|r| {
            r.get("body")
                .and_then(|b| b.list().ok())
                .is_some_and(|b| b.iter().any(|c| c.get("mode").is_some()))
        })
    {
        return Err(invalid(
            "checked operators require explicit or inferred column types",
        ));
    }
    Ok(())
}
/// Evaluate the admitted rule graph once and return actual execution observations.
/// # Errors
/// Rejects closed engines, unsafe syntax, resource exhaustion and unstable/incomplete evaluation.
pub fn evaluate_datalog(engine: &Engine, request: &DatalogRequest<'_>) -> Result<(Data, Data)> {
    engine.check()?;
    let graph = read_datalog(request)?;
    let catalog = Catalog::read(&graph.program)?;
    let mut session = engine.open_catalog(
        catalog.program,
        BTreeMap::new(),
        catalog.queries,
        FactLimits::default(),
    )?;
    let result = session.run(None, &Limits::default(), &Cancellation::default())?;
    if !result.complete {
        return Err(invalid("incomplete Datalog result"));
    }
    let retained = session.result(result.result_handle)?;
    let source_identity = retained.identity()?;
    let rows = Data::Map(
        result
            .relations
            .iter()
            .map(|(name, rows)| Ok((name.clone(), Catalog::project_rows(rows))))
            .collect::<Result<_>>()?,
    );
    retained.close();
    let answers = graph
        .queries
        .map()?
        .iter()
        .map(|(label, atom)| {
            let mut rows = rows
                .field(atom.field("relation")?.text()?)?
                .list()?
                .to_vec();
            rows.sort();
            Ok((label.clone(), Data::List(rows)))
        })
        .collect::<Result<BTreeMap<_, _>>>()?;
    let receipt = Data::object([
        ("sourceIdentity", source_identity.into()),
        ("sourceGeneration", result.source_generation.into()),
        ("runIndex", result.run_index.into()),
        ("complete", result.complete.into()),
        ("reused", result.reused.into()),
    ]);
    Ok((Data::Map(answers), receipt))
}
