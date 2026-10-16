//! Fixed adapters to the existing Library Core; no new algorithm or evaluator.
use gerbil_ascent::{
    Cancellation, Catalog, Data, Engine, Error, FactLimits, Result, SourceSession,
};
use std::collections::BTreeMap;

pub(super) struct Owner {
    pub session: SourceSession,
    engine: Engine,
    pub trace: crate::diagnostics::Trace,
}
impl Owner {
    pub fn open(input: &Data) -> Result<Self> {
        validate_open(input)?;
        let mut trace = crate::diagnostics::Trace::new(
            input
                .get("diagnostics")
                .map(Data::boolean)
                .transpose()?
                .unwrap_or(false),
        );
        let started = trace.start();
        let engine = Engine::new(input.field("workers")?.index()?)?;
        trace.record("open.rayonPool", started);
        let started = trace.start();
        let declaration = read_declaration(input)?;
        trace.record("open.dslReadAndLower", started);
        let started = trace.start();
        let session = engine.open_evidence_program(declaration, read_limits(input)?)?;
        trace.record("open.admissionAndInitialRun", started);
        Ok(Self {
            session,
            engine,
            trace,
        })
    }
}
fn validate_open(input: &Data) -> Result<()> {
    let mut expected = if input.get("graph").is_some() {
        vec!["workers", "graph", "limits"]
    } else if input.get("components").is_some() {
        vec!["workers", "components", "entry", "constructor", "limits"]
    } else {
        vec!["workers", "sources", "constructor", "limits"]
    };
    if input.get("diagnostics").is_some() {
        expected.push("diagnostics");
    }
    fields(input, &expected)
}
fn read_declaration(input: &Data) -> Result<gerbil_ascent::EvidenceProgram> {
    if let Some(graph) = input.get("graph") {
        return read_graph(graph);
    }
    let constructor = match input.field("constructor")? {
        Data::Null => None,
        value => Some(value.text()?),
    };
    if let Some(components) = input.get("components") {
        let components = components
            .list()?
            .iter()
            .map(read_component)
            .collect::<Result<Vec<_>>>()?;
        return gerbil_ascent::EvidenceProgram::read_components(
            &components,
            input.field("entry")?.text()?,
            constructor,
        );
    }
    let sources = input
        .field("sources")?
        .list()?
        .iter()
        .map(Data::text)
        .collect::<Result<Vec<_>>>()?;
    gerbil_ascent::EvidenceProgram::read_sources(&sources, constructor)
}
fn read_graph(input: &Data) -> Result<gerbil_ascent::EvidenceProgram> {
    fields(
        input,
        &["algorithm", "source", "width", "rows", "output", "captures"],
    )?;
    let width = input.field("width")?.index()?;
    if width > 16 {
        return Err(Error::InvalidProgram(
            "Graph source width exceeds sixteen".into(),
        ));
    }
    let source = input.field("source")?.text()?;
    let catalog = Catalog::read(&Data::object([
        (
            "relations",
            Data::List(vec![Data::object([
                ("name", source.into()),
                ("source", true.into()),
                ("rows", input.field("rows")?.clone()),
                (
                    "columns",
                    Data::List(
                        (0..width)
                            .map(|_| Data::object([("kind", "value".into())]))
                            .collect(),
                    ),
                ),
            ])]),
        ),
        ("rules", Data::List(vec![])),
    ]))?;
    let rows = catalog
        .program
        .relations
        .into_iter()
        .next()
        .ok_or_else(|| Error::InvalidProgram("Graph source required".into()))?
        .rows;
    let graph = gerbil_ascent::RelationalGraph::source(source, width, rows)?;
    let captures = input.field("captures")?;
    let graph = match input.field("algorithm")?.text()? {
        "projection" => {
            fields(captures, &["columns"])?;
            let columns = captures
                .field("columns")?
                .list()?
                .iter()
                .map(Data::index)
                .collect::<Result<_>>()?;
            gerbil_ascent::make_projection_graph(columns)(graph)?
        }
        "transitive" => {
            fields(captures, &[])?;
            if width != 2 {
                return Err(Error::InvalidProgram(
                    "transitive Graph input width must be two".into(),
                ));
            }
            gerbil_ascent::make_transitive_graph()(graph)?
        }
        _ => {
            return Err(Error::InvalidProgram(
                "unknown precompiled Graph algorithm".into(),
            ));
        }
    };
    graph.evidence(input.field("output")?.text()?)
}
fn read_component(input: &Data) -> Result<gerbil_ascent::Component> {
    fields(input, &["id", "source", "exports", "dependencies"])?;
    Ok(gerbil_ascent::Component {
        id: input.field("id")?.text()?.into(),
        source: input.field("source")?.text()?.into(),
        exports: match input.field("exports")? {
            Data::Null => None,
            names => Some(read_names(names)?),
        },
        dependencies: input
            .field("dependencies")?
            .list()?
            .iter()
            .map(|dependency| {
                fields(dependency, &["component", "bindings"])?;
                Ok(gerbil_ascent::Dependency {
                    component: dependency.field("component")?.text()?.into(),
                    bindings: read_names(dependency.field("bindings")?)?,
                })
            })
            .collect::<Result<_>>()?,
    })
}
fn read_names(input: &Data) -> Result<Vec<String>> {
    input
        .list()?
        .iter()
        .map(|name| name.text().map(str::to_owned))
        .collect()
}
fn read_limits(input: &Data) -> Result<FactLimits> {
    let limits = input.field("limits")?;
    fields(limits, &["input", "derived", "output"])?;
    Ok(FactLimits {
        input: ceiling(limits, "input")?,
        derived: ceiling(limits, "derived")?,
        output: ceiling(limits, "output")?,
    })
}
impl Owner {
    pub fn invoke(&mut self, input: &Data) -> Result<Data> {
        let method = input.field("method")?.text()?;
        fields(
            input,
            match method {
                "describe" | "runtime" | "diagnose" => &["method"],
                "run" if input.get("resultFormat").is_some() => {
                    &["method", "queries", "timeoutNanoseconds", "resultFormat"]
                }
                "run" => &["method", "queries", "timeoutNanoseconds"],
                "replace" => &["method", "sources"],
                "explain" | "rows" => &["method", "handle", "query"],
                "release-result" => &["method", "handle"],
                _ => {
                    return Err(Error::InvalidUpdate(
                        "unknown fixed Core ABI operation".into(),
                    ));
                }
            },
        )?;
        match input.field("method")?.text()? {
            "diagnose" => Ok(self.trace.snapshot()),
            "runtime" => Ok(Data::object([
                ("workers", self.engine.threads().into()),
                ("schemeVm", false.into()),
                ("algorithmProvider", "existing-ascent-core".into()),
            ])),
            "describe" => Catalog::observe(&self.session.source_program()?, self.session.queries()),
            "run" => self.run(input),
            "replace" => self.replace(input),
            "explain" => self
                .session
                .explanation_metadata(handle(input)?, input.field("query")?.text()?),
            "rows" => Ok(gerbil_ascent::rows_graph(
                self.session
                    .result(handle(input)?)?
                    .rows(input.field("query")?.text()?)?,
            )?
            .to_native()),
            "release-result" => {
                self.session.result(handle(input)?)?.close();
                Ok(Data::Null)
            }
            _ => Err(Error::InvalidUpdate(
                "unknown fixed Core ABI operation".into(),
            )),
        }
    }
    fn run(&mut self, input: &Data) -> Result<Data> {
        let format = input
            .get("resultFormat")
            .map(Data::text)
            .transpose()?
            .unwrap_or("graph");
        if !matches!(format, "graph" | "typed-rows") {
            return Err(Error::InvalidUpdate(
                "explicit Core result format required".into(),
            ));
        }
        let queries = input.field("queries")?;
        let queries = match queries {
            Data::Null => None,
            values => Some(
                values
                    .list()?
                    .iter()
                    .map(|v| v.text().map(str::to_owned))
                    .collect::<Result<Vec<_>>>()?,
            ),
        };
        let mut limits = SourceSession::default_limits();
        limits.timeout = std::time::Duration::from_nanos(
            input
                .field("timeoutNanoseconds")?
                .index()?
                .try_into()
                .map_err(|_| Error::StateLimit)?,
        );
        let started = self.trace.start();
        let observation =
            self.session
                .run(queries.as_deref(), &limits, &Cancellation::default())?;
        self.trace.record("run.coreSnapshot", started);
        let started = self.trace.start();
        let relations = observation
            .relations
            .iter()
            .map(|(name, rows)| {
                Ok((
                    name.clone(),
                    match format {
                        "typed-rows" => Data::List(
                            rows.iter()
                                .map(|row| Data::List(row.iter().map(typed_cell).collect()))
                                .collect(),
                        ),
                        _ => gerbil_ascent::rows_graph(rows)?.to_native(),
                    },
                ))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        self.trace.record("run.objectGraphAndPacket", started);
        Ok(Data::object([
            ("complete", observation.complete.into()),
            ("relations", Data::Map(relations)),
            ("resultFormat", format.into()),
            ("resultHandle", observation.result_handle.into()),
            ("sourceGeneration", observation.source_generation.into()),
            ("runIndex", observation.run_index.into()),
            ("reused", observation.reused.into()),
            ("evaluated", observation.evaluated.into()),
        ]))
    }
    fn replace(&mut self, input: &Data) -> Result<Data> {
        let started = self.trace.start();
        let updates = input.field("sources")?.map()?;
        // Decode only incoming rows. Existing opaque/cyclic execution values
        // must never be round-tripped through a restricted catalog projection.
        let relations = updates
            .iter()
            .map(|(name, rows)| self.source_rows(name, rows))
            .collect::<Result<Vec<_>>>()?;
        let admitted = Catalog::read(&Data::object([
            ("relations", Data::List(relations)),
            ("rules", Data::List(vec![])),
        ]))?;
        let rows = admitted
            .program
            .relations
            .into_iter()
            .filter(|r| updates.contains_key(&r.name))
            .map(|r| (r.name, r.rows))
            .collect();
        self.trace.record("replace.packetAdmission", started);
        let started = self.trace.start();
        let result = self
            .session
            .replace(
                rows,
                &SourceSession::default_limits(),
                &Cancellation::default(),
            )
            .map(Data::from);
        self.trace.record("replace.coreValidateAndInfer", started);
        result
    }
    fn source_rows(&self, name: &str, rows: &Data) -> Result<Data> {
        let declaration = self
            .session
            .descriptors()
            .iter()
            .find(|r| r.name == name && r.source)
            .ok_or_else(|| Error::InvalidUpdate("unknown source replacement".into()))?;
        Ok(Data::object([
            ("name", name.into()),
            ("source", true.into()),
            ("rows", rows.clone()),
            (
                "columns",
                Data::List(
                    declaration
                        .columns
                        .iter()
                        .map(|ty| Data::object([("kind", column(*ty).into())]))
                        .collect(),
                ),
            ),
        ]))
    }
}
fn typed_cell(value: &gerbil_ascent::Value) -> Data {
    use gerbil_ascent::Value;
    match value {
        Value::Integer(v) => Data::Integer(v.clone()),
        Value::Boolean(v) => Data::Bool(*v),
        Value::Text(v) => {
            Data::object([("type", "string".into()), ("value", v.to_string().into())])
        }
        Value::Symbol(v) => {
            Data::object([("type", "symbol".into()), ("value", v.to_string().into())])
        }
        Value::Object(v) => v.native_input(),
    }
}
pub(super) fn fields(input: &Data, expected: &[&str]) -> Result<()> {
    let input = input.map()?;
    if input.len() != expected.len() || expected.iter().any(|name| !input.contains_key(*name)) {
        return Err(Error::InvalidUpdate("fixed Core ABI fields".into()));
    }
    Ok(())
}
fn column(ty: gerbil_ascent::Type) -> &'static str {
    use gerbil_ascent::Type;
    match ty {
        Type::Any => "value",
        Type::Scalar => "scalar",
        Type::Integer => "integer",
        Type::Boolean => "boolean",
        Type::Text => "string",
        Type::Symbol => "symbol",
        Type::Number => "number",
    }
}
impl Drop for Owner {
    fn drop(&mut self) {
        self.session.close();
        self.engine.shutdown();
    }
}
fn handle(input: &Data) -> Result<u64> {
    input
        .field("handle")?
        .index()?
        .try_into()
        .map_err(|_| Error::StateLimit)
}
fn ceiling(input: &Data, name: &str) -> Result<Option<usize>> {
    match input.field(name)? {
        Data::Null => Ok(None),
        value => value.index().map(Some),
    }
}
