//! Immutable identity-preserving observations shared by module and relational values.
use std::{collections::BTreeMap, sync::Arc};
/// Inline scalar or reference to an identity-bearing observation node.
#[derive(Clone, Debug)]
pub enum GraphItem {
    Void,
    Null,
    Boolean(bool),
    Number(String),
    Character(char),
    Reference(usize),
}
/// Identity-bearing Scheme object observation.
#[derive(Clone, Debug)]
pub enum ObjectNode {
    Text(String),
    Symbol { name: String, interned: bool },
    Pair(GraphItem, GraphItem),
    Vector(Vec<GraphItem>),
    Bytes(Vec<u8>),
    Table(Vec<(GraphItem, GraphItem)>),
    Opaque(String),
}
/// Finite observation of a possibly cyclic object graph.
#[derive(Clone, Debug)]
pub struct ObjectGraph {
    pub root: GraphItem,
    pub nodes: Arc<BTreeMap<usize, ObjectNode>>,
}

/// Build a Scheme list of tuples, preserving complex-value sharing and cycles.
/// # Errors
/// Rejects observations larger than the bounded graph transport.
pub fn rows_graph(rows: &[crate::Row]) -> crate::Result<ObjectGraph> {
    let mut builder = Observation {
        out: ObjectGraph {
            root: GraphItem::Null,
            nodes: Arc::default(),
        },
        identities: BTreeMap::new(),
        symbols: BTreeMap::new(),
    };
    for row in rows.iter().rev() {
        builder.row(row)?;
    }
    Ok(builder.out)
}
struct Observation {
    out: ObjectGraph,
    identities: BTreeMap<(u64, u64, usize), usize>,
    symbols: BTreeMap<std::sync::Arc<str>, usize>,
}
impl Observation {
    fn row(&mut self, row: &crate::Row) -> crate::Result<()> {
        let mut tuple = GraphItem::Null;
        for value in row.iter().rev() {
            let cell = self.cell(value)?;
            tuple = allocate(&mut self.out, ObjectNode::Pair(cell, tuple))?;
        }
        let tail = self.out.root.clone();
        self.out.root = allocate(&mut self.out, ObjectNode::Pair(tuple, tail))?;
        Ok(())
    }
    fn cell(&mut self, value: &crate::Value) -> crate::Result<GraphItem> {
        match value {
            crate::Value::Integer(v) => Ok(GraphItem::Number(v.to_string())),
            crate::Value::Boolean(v) => Ok(GraphItem::Boolean(*v)),
            crate::Value::Text(v) => allocate(&mut self.out, ObjectNode::Text(v.to_string())),
            crate::Value::Symbol(v) => self.symbol(v),
            crate::Value::Object(v) => self.object(v),
        }
    }
    fn symbol(&mut self, v: &std::sync::Arc<str>) -> crate::Result<GraphItem> {
        if let Some(id) = self.symbols.get(v) {
            return Ok(GraphItem::Reference(*id));
        }
        let item = allocate(
            &mut self.out,
            ObjectNode::Symbol {
                name: v.to_string(),
                interned: true,
            },
        )?;
        if let GraphItem::Reference(id) = item {
            self.symbols.insert(v.clone(), id);
        }
        Ok(item)
    }
    fn object(&mut self, v: &crate::FrozenValue) -> crate::Result<GraphItem> {
        let graph = v.graph();
        let mut local = BTreeMap::new();
        let mut fresh = Vec::new();
        let mut pending = vec![graph.root.clone()];
        while let Some(item) = pending.pop() {
            let GraphItem::Reference(id) = item else {
                continue;
            };
            if local.contains_key(&id) {
                continue;
            }
            let key = (v.owner(), v.observation(), id);
            let mapped = if let Some(mapped) = self.identities.get(&key) {
                *mapped
            } else {
                let GraphItem::Reference(mapped) =
                    allocate(&mut self.out, ObjectNode::Opaque("pending".into()))?
                else {
                    unreachable!()
                };
                self.identities.insert(key, mapped);
                fresh.push((id, mapped));
                mapped
            };
            local.insert(id, mapped);
            match graph
                .nodes
                .get(&id)
                .ok_or_else(|| crate::invalid_data("dangling frozen observation"))?
            {
                ObjectNode::Pair(a, b) => {
                    pending.push(a.clone());
                    pending.push(b.clone());
                }
                ObjectNode::Vector(values) => pending.extend(values.iter().cloned()),
                ObjectNode::Table(values) => {
                    for (a, b) in values {
                        pending.push(a.clone());
                        pending.push(b.clone());
                    }
                }
                _ => (),
            }
        }
        for (id, mapped) in fresh {
            Arc::make_mut(&mut self.out.nodes)
                .insert(mapped, remap_node(&graph.nodes[&id], &local));
        }
        Ok(remap(&graph.root, &local))
    }
}
fn allocate(graph: &mut ObjectGraph, node: ObjectNode) -> crate::Result<GraphItem> {
    if graph.nodes.len() >= 65_536 {
        return Err(crate::Error::StateLimit);
    }
    let id = graph.nodes.len() + 1;
    Arc::make_mut(&mut graph.nodes).insert(id, node);
    Ok(GraphItem::Reference(id))
}
fn remap(item: &GraphItem, ids: &BTreeMap<usize, usize>) -> GraphItem {
    match item {
        GraphItem::Reference(id) => GraphItem::Reference(ids[id]),
        _ => item.clone(),
    }
}
fn remap_node(node: &ObjectNode, ids: &BTreeMap<usize, usize>) -> ObjectNode {
    match node {
        ObjectNode::Pair(a, b) => ObjectNode::Pair(remap(a, ids), remap(b, ids)),
        ObjectNode::Vector(items) => {
            ObjectNode::Vector(items.iter().map(|v| remap(v, ids)).collect())
        }
        ObjectNode::Table(entries) => ObjectNode::Table(
            entries
                .iter()
                .map(|(a, b)| (remap(a, ids), remap(b, ids)))
                .collect(),
        ),
        _ => node.clone(),
    }
}

impl ObjectGraph {
    /// Decode an owned observation produced by Scheme, preserving graph identity.
    /// This reads data only; no Scheme forms or procedures are evaluated.
    /// # Errors
    /// Rejects malformed nodes, invalid scalar encodings and dangling references.
    pub fn read_scheme(value: &crate::Data) -> crate::Result<Self> {
        let entries = value.field("nodes")?.list()?;
        if entries.len() > 65_536 {
            return Err(crate::Error::StateLimit);
        }
        let mut nodes = BTreeMap::new();
        for entry in entries {
            let id = entry.field("id")?.index()?;
            let node = scheme_node(entry)?;
            if nodes.insert(id, node).is_some() {
                return Err(crate::invalid_data("duplicate native graph identity"));
            }
        }
        let graph = Self {
            root: scheme_item(value.field("root")?)?,
            nodes: Arc::new(nodes),
        };
        graph.validate_references()?;
        Ok(graph)
    }
}

impl ObjectGraph {
    fn validate_references(&self) -> crate::Result<()> {
        let check = |v: &GraphItem| {
            if matches!(v, GraphItem::Reference(id) if !self.nodes.contains_key(id)) {
                return Err(crate::invalid_data("dangling native graph identity"));
            }
            Ok(())
        };
        check(&self.root)?;
        self.nodes.values().try_for_each(|node| match node {
            ObjectNode::Pair(a, b) => {
                check(a)?;
                check(b)
            }
            ObjectNode::Vector(v) => v.iter().try_for_each(check),
            ObjectNode::Table(v) => v.iter().try_for_each(|(a, b)| {
                check(a)?;
                check(b)
            }),
            _ => Ok(()),
        })
    }
}

impl ObjectGraph {
    /// Encode an owned graph for the native value adapter; this transports data only.
    #[must_use]
    pub fn to_scheme(&self) -> crate::Data {
        use crate::Data;
        fn item(v: &GraphItem) -> Data {
            match v {
                GraphItem::Reference(id) => Data::object([("ref", Data::from(*id))]),
                GraphItem::Void => Data::object([("type", Data::from("void"))]),
                GraphItem::Null => Data::object([("type", Data::from("null"))]),
                GraphItem::Boolean(v) => {
                    Data::object([("type", Data::from("boolean")), ("value", Data::Bool(*v))])
                }
                GraphItem::Number(v) => Data::object([
                    ("type", Data::from("number")),
                    ("value", Data::from(v.clone())),
                ]),
                GraphItem::Character(v) => Data::object([
                    ("type", Data::from("character")),
                    ("value", Data::from(u64::from(u32::from(*v)))),
                ]),
            }
        }
        let reachable = reachable_ids(self);
        let nodes = self
            .nodes
            .iter()
            .filter(|(id, _)| reachable.contains(id))
            .map(|(id, node)| {
                let mut fields = vec![("id", Data::from(*id))];
                match node {
                    ObjectNode::Text(v) => fields.extend([
                        ("type", Data::from("string")),
                        ("value", Data::from(v.clone())),
                    ]),
                    ObjectNode::Symbol { name, interned } => fields.extend([
                        ("type", Data::from("symbol")),
                        ("value", Data::from(name.clone())),
                        ("interned", Data::Bool(*interned)),
                    ]),
                    ObjectNode::Pair(a, b) => fields.extend([
                        ("type", Data::from("pair")),
                        ("car", item(a)),
                        ("cdr", item(b)),
                    ]),
                    ObjectNode::Vector(v) => fields.extend([
                        ("type", Data::from("vector")),
                        ("items", Data::List(v.iter().map(item).collect())),
                    ]),
                    ObjectNode::Bytes(v) => fields.extend([
                        ("type", Data::from("u8vector")),
                        (
                            "items",
                            Data::List(v.iter().map(|v| Data::from(usize::from(*v))).collect()),
                        ),
                    ]),
                    ObjectNode::Table(v) => fields.extend([
                        ("type", Data::from("hash-table")),
                        (
                            "entries",
                            Data::List(
                                v.iter()
                                    .map(|(a, b)| Data::List(vec![item(a), item(b)]))
                                    .collect(),
                            ),
                        ),
                    ]),
                    ObjectNode::Opaque(v) => fields.extend([
                        ("type", Data::from("opaque")),
                        ("encoding", Data::from(v.clone())),
                    ]),
                }
                Data::Map(
                    fields
                        .into_iter()
                        .map(|(key, value)| (key.into(), value))
                        .collect(),
                )
            })
            .collect();
        Data::object([
            ("format", Data::from("native-value-graph.v1")),
            ("root", item(&self.root)),
            ("nodes", Data::List(nodes)),
        ])
    }
}

fn scheme_item(value: &crate::Data) -> crate::Result<GraphItem> {
    if let Some(id) = value.get("ref") {
        return Ok(GraphItem::Reference(id.index()?));
    }
    Ok(match value.field("type")?.text()? {
        "void" => GraphItem::Void,
        "null" => GraphItem::Null,
        "boolean" => GraphItem::Boolean(value.field("value")?.boolean()?),
        "number" => GraphItem::Number(value.field("value")?.text()?.into()),
        "character" => GraphItem::Character(
            char::from_u32(
                u32::try_from(value.field("value")?.index()?)
                    .map_err(|_| crate::invalid_data("character range"))?,
            )
            .ok_or_else(|| crate::invalid_data("character range"))?,
        ),
        _ => return Err(crate::invalid_data("native graph item kind")),
    })
}

fn scheme_node(entry: &crate::Data) -> crate::Result<ObjectNode> {
    Ok(match entry.field("type")?.text()? {
        "string" => ObjectNode::Text(entry.field("value")?.text()?.into()),
        "symbol" => ObjectNode::Symbol {
            name: entry.field("value")?.text()?.into(),
            interned: entry.field("interned")?.boolean()?,
        },
        "pair" => ObjectNode::Pair(
            scheme_item(entry.field("car")?)?,
            scheme_item(entry.field("cdr")?)?,
        ),
        "vector" => ObjectNode::Vector(
            entry
                .field("items")?
                .list()?
                .iter()
                .map(scheme_item)
                .collect::<crate::Result<_>>()?,
        ),
        "u8vector" => ObjectNode::Bytes(
            entry
                .field("items")?
                .list()?
                .iter()
                .map(|v| u8::try_from(v.index()?).map_err(|_| crate::invalid_data("byte range")))
                .collect::<crate::Result<_>>()?,
        ),
        "hash-table" => ObjectNode::Table(
            entry
                .field("entries")?
                .list()?
                .iter()
                .map(|v| {
                    let v = v.list()?;
                    if v.len() != 2 {
                        return Err(crate::invalid_data("native table pair"));
                    }
                    Ok((scheme_item(&v[0])?, scheme_item(&v[1])?))
                })
                .collect::<crate::Result<_>>()?,
        ),
        "opaque" => ObjectNode::Opaque(entry.field("encoding")?.text()?.into()),
        _ => return Err(crate::invalid_data("native graph node kind")),
    })
}

fn reachable_ids(graph: &ObjectGraph) -> std::collections::BTreeSet<usize> {
    let mut ids = std::collections::BTreeSet::new();
    let mut pending = vec![&graph.root];
    while let Some(item) = pending.pop() {
        let GraphItem::Reference(id) = item else {
            continue;
        };
        if !ids.insert(*id) {
            continue;
        }
        match graph.nodes.get(id) {
            Some(ObjectNode::Pair(a, b)) => pending.extend([a, b]),
            Some(ObjectNode::Vector(v)) => pending.extend(v),
            Some(ObjectNode::Table(v)) => pending.extend(v.iter().flat_map(|(a, b)| [a, b])),
            _ => (),
        }
    }
    ids
}
