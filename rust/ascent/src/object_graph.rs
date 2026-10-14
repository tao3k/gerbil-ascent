//! Immutable identity-preserving observations shared by module and relational values.
use std::collections::BTreeMap;
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
    pub nodes: BTreeMap<usize, ObjectNode>,
}

/// Build a Scheme list of tuples, preserving complex-value sharing and cycles.
/// # Errors
/// Rejects observations larger than the bounded graph transport.
pub fn rows_graph(rows: &[crate::Row]) -> crate::Result<ObjectGraph> {
    let mut builder = Observation {
        out: ObjectGraph {
            root: GraphItem::Null,
            nodes: BTreeMap::new(),
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
        for id in graph.nodes.keys() {
            let key = (v.owner(), v.observation(), *id);
            let mapped = if let Some(mapped) = self.identities.get(&key) {
                *mapped
            } else {
                let GraphItem::Reference(mapped) =
                    allocate(&mut self.out, ObjectNode::Opaque("pending".into()))?
                else {
                    unreachable!()
                };
                self.identities.insert(key, mapped);
                fresh.push((*id, mapped));
                mapped
            };
            local.insert(*id, mapped);
        }
        for (id, mapped) in fresh {
            self.out
                .nodes
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
    graph.nodes.insert(id, node);
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
