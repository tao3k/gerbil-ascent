//! Test observation adapters. Every language operation calls the native library.
use ascent_scheme as native;
use gerbil_ascent::{
    Cancellation, Component, Data, FactLimits, GraphItem, Limits, ObjectGraph, ObjectInput,
    ObjectNode, Result, Row, SourceObservation, Value,
};
use std::{
    collections::BTreeMap,
    ops::Deref,
    sync::{Arc, OnceLock},
};
#[derive(Clone)]
pub struct Engine(native::Engine);
impl Deref for Engine {
    type Target = gerbil_ascent::Engine;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl Engine {
    pub fn new(threads: usize) -> Result<Self> {
        crate::engine(threads).map(Self)
    }
    pub fn factory() -> impl Fn(usize) -> Result<Self> {
        let create = crate::engines();
        move |threads| create(threads).map(Self)
    }
    pub fn on_process(self, process: native::ProcessOwner) -> Self {
        Self(self.0.on_process(process))
    }
    pub fn load_definitions(&self, source: &str) -> Result<Module> {
        self.0.load_definitions(source).map(Module)
    }
    pub fn load_components(&self, components: &[Component], entry: &str) -> Result<Module> {
        self.0.load_components(components, entry).map(Module)
    }
    pub fn module(&self, name: &str) -> Result<Module> {
        self.0.module(name).map(Module)
    }
    pub fn register_module(&self, name: &str, source: &str) -> Result<()> {
        self.0.register_module(name, source)
    }
}
pub struct Module(native::Module);
impl Module {
    pub fn call(
        &self,
        name: &str,
        args: &[ObjectInput],
        component: Option<&str>,
    ) -> Result<ModuleValue> {
        self.0.call(name, args, component).map(ModuleValue::new)
    }

    pub fn close(&self) {
        self.0.close();
    }
}
pub struct ModuleValue {
    inner: native::ModuleValue,
    graph: OnceLock<Arc<ObjectGraph>>,
}
impl ModuleValue {
    fn new(inner: native::ModuleValue) -> Self {
        Self {
            inner,
            graph: OnceLock::new(),
        }
    }
    pub fn graph(&self) -> Result<Arc<ObjectGraph>> {
        let graph = self.inner.graph()?;
        if let Some(graph) = self.graph.get() {
            return Ok(graph.clone());
        }
        let graph = Arc::new(ObjectGraph::read_scheme(&graph)?);
        let _ = self.graph.set(graph.clone());
        Ok(graph)
    }
    pub fn apply(&self, args: &[ObjectInput]) -> Result<Self> {
        self.inner.apply(args).map(Self::new)
    }
    pub fn reference(&self, node: Option<usize>) -> Result<gerbil_ascent::ValueReference> {
        self.inner.reference(node)
    }
    pub fn value_count(&self) -> Result<usize> {
        self.inner.value_count()
    }
    pub fn close(&self) {
        self.inner.close();
    }
    pub fn open_session(&self, limits: FactLimits) -> Result<RuleSession> {
        self.inner.open_session(limits).map(|inner| RuleSession {
            inner,
            results: std::sync::Mutex::default(),
        })
    }
}
pub struct RuleSession {
    inner: native::RuleSession,
    results: std::sync::Mutex<BTreeMap<u64, native::RuleResult>>,
}
fn list(graph: &ObjectGraph, mut item: GraphItem) -> Result<Vec<GraphItem>> {
    let mut output = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    loop {
        match item {
            GraphItem::Null => return Ok(output),
            GraphItem::Reference(id) => {
                if !seen.insert(id) {
                    return Err(gerbil_ascent::Error::Evaluation("cyclic tuple list".into()));
                }
                let Some(ObjectNode::Pair(a, b)) = graph.nodes.get(&id) else {
                    return Err(gerbil_ascent::Error::Evaluation(
                        "tuple list required".into(),
                    ));
                };
                output.push(a.clone());
                item = b.clone();
            }
            _ => {
                return Err(gerbil_ascent::Error::Evaluation(
                    "tuple list required".into(),
                ));
            }
        }
    }
}
pub fn rows(value: &Data, identity: u64) -> Result<Vec<Row>> {
    let graph = ObjectGraph::read_scheme(value.field("value")?)?;
    list(&graph, graph.root.clone())?
        .into_iter()
        .map(|row| {
            list(&graph, row)?
                .into_iter()
                .map(|cell| {
                    Ok(match &cell {
                        GraphItem::Boolean(v) => Value::Boolean(*v),
                        GraphItem::Number(v) if v.parse::<num_bigint::BigInt>().is_ok() => {
                            Value::Integer(v.parse().unwrap())
                        }
                        GraphItem::Reference(id) => match graph.nodes.get(id) {
                            Some(ObjectNode::Text(v)) => Value::Text(v.as_str().into()),
                            Some(ObjectNode::Symbol {
                                name,
                                interned: true,
                            }) => Value::Symbol(name.as_str().into()),
                            _ => Value::Object(gerbil_ascent::FrozenValue::new(
                                identity,
                                identity,
                                ObjectGraph {
                                    root: cell,
                                    nodes: graph.nodes.clone(),
                                },
                            )?),
                        },
                        _ => Value::Object(gerbil_ascent::FrozenValue::new(
                            identity,
                            identity,
                            ObjectGraph {
                                root: cell,
                                nodes: graph.nodes.clone(),
                            },
                        )?),
                    })
                })
                .collect::<Result<Vec<_>>>()
                .map(Row::from)
        })
        .collect()
}
impl RuleSession {
    pub fn run(
        &self,
        queries: Option<&[String]>,
        limits: &Limits,
        cancel: &Cancellation,
    ) -> Result<SourceObservation> {
        let data = self
            .inner
            .run(queries, limits, cancel)
            .inspect_err(|error| {
                eprintln!("OBSERVE-RUN-FAIL stage=execute error={error:?}");
            })?;
        let handle = u64::try_from(data.field("resultHandle")?.index()?).unwrap();
        let result = self.inner.result(handle).inspect_err(|error| {
            eprintln!("OBSERVE-RUN-FAIL stage=result-lookup error={error:?}");
        })?;
        let queries = queries.map_or_else(|| self.inner.queries(), |q| Ok(q.to_vec()))?;
        let relations = queries
            .into_iter()
            .map(|q| {
                let native = result.rows(&q).inspect_err(|error| {
                    eprintln!("OBSERVE-RUN-FAIL stage=result-rows query={q} error={error:?}");
                })?;
                Ok((q.clone(), rows(&native, handle)?))
            })
            .collect::<Result<_>>()?;
        // Keep the result lease retained until the explicit result() request.
        self.results.lock().unwrap().insert(handle, result);
        Ok(SourceObservation {
            complete: data.field("complete")?.boolean()?,
            relations,
            result_handle: handle,
            source_generation: u64::try_from(data.field("sourceGeneration")?.index()?).unwrap(),
            run_index: u64::try_from(data.field("runIndex")?.index()?).unwrap(),
            reused: data.field("nativeResultReused")?.boolean()?,
            active_rule_count: data.field("activeRuleCount")?.index()?,
            evaluated: !data.field("nativeResultReused")?.boolean()?,
            reused_relations: vec![],
        })
    }
    pub fn result(&self, handle: u64) -> Result<RuleResult> {
        self.results
            .lock()
            .unwrap()
            .remove(&handle)
            .map_or_else(|| self.inner.result(handle), Ok)
            .map(RuleResult)
    }
    pub fn replace(
        &self,
        sources: BTreeMap<String, Vec<Vec<ObjectInput>>>,
        limits: &Limits,
        cancel: &Cancellation,
    ) -> Result<u64> {
        self.inner.replace(sources, limits, cancel)
    }
    pub fn explain(&self, handle: u64, query: &str) -> Result<native::Explanation> {
        self.inner.explain(handle, query)
    }
    pub fn provenance(
        &self,
        handle: u64,
        query: &str,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancel: &Cancellation,
    ) -> Result<native::SchemeProvenance> {
        self.inner.provenance(handle, query, limits, cancel)
    }
    pub fn close(&self) {
        self.inner.close();
        self.results.lock().unwrap().clear();
    }
}
pub struct RuleResult(native::RuleResult);
impl RuleResult {
    pub fn rows(&self, name: &str) -> Result<Vec<Row>> {
        rows(&self.0.rows(name)?, 0)
    }

    pub fn close(&self) {
        self.0.close();
    }
    pub fn value(&self, name: &str, row: usize, column: usize) -> Result<native::ResultValue> {
        self.0.value(name, row, column)
    }
}
