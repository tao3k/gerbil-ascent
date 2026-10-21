//! Structural keys for immutable cyclic Scheme values, computed before worker admission.
use crate::{
    Error, Result,
    object_graph::{GraphItem, ObjectGraph, ObjectNode},
};
use std::{
    cmp::Ordering,
    collections::{BTreeMap, VecDeque},
    hash::{Hash, Hasher},
    sync::Arc,
};

#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
enum Label {
    Void,
    Null,
    Boolean(bool),
    Number(String),
    Character(char),
    Text(String),
    Symbol(String),
    Pair,
    Vector,
    Bytes(Vec<u8>),
    Identity(u64, usize),
}
#[derive(Clone, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
struct Node {
    label: Label,
    edges: Vec<usize>,
}
/// Frozen structural equality ignores sharing, while observations retain original sharing.
/// Tables, uninterned symbols and opaque objects retain owner-local identity.
#[derive(Clone)]
pub struct FrozenValue {
    owner: u64,
    observation: u64,
    key: Arc<[Node]>,
    graph: Arc<ObjectGraph>,
    hash: u64,
    numeric: Option<Arc<crate::numbers::Number>>,
}
impl std::fmt::Debug for FrozenValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FrozenValue")
            .field("owner", &self.owner)
            .field("observation", &self.observation)
            .field("root", &self.graph.root)
            .field("canonical_nodes", &self.key.len())
            .field("digest", &self.hash)
            .finish_non_exhaustive()
    }
}
impl PartialEq for FrozenValue {
    fn eq(&self, other: &Self) -> bool {
        self.hash == other.hash && self.key == other.key
    }
}
impl Eq for FrozenValue {}
impl PartialOrd for FrozenValue {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}
impl Ord for FrozenValue {
    fn cmp(&self, other: &Self) -> Ordering {
        self.key.cmp(&other.key)
    }
}
impl Hash for FrozenValue {
    fn hash<H: Hasher>(&self, state: &mut H) {
        state.write_u64(self.hash);
    }
}
impl FrozenValue {
    pub(crate) fn vector_items(&self) -> Option<&[GraphItem]> {
        let GraphItem::Reference(id) = self.graph.root else {
            return None;
        };
        match self.graph.nodes.get(&id)? {
            ObjectNode::Vector(items) => Some(items),
            _ => None,
        }
    }
    pub(crate) fn vector_item(&self, index: usize) -> Result<crate::Value> {
        use crate::Value;
        let item = self
            .vector_items()
            .and_then(|items| items.get(index))
            .ok_or_else(|| Error::Evaluation("vector-ref outside vector".into()))?;
        match item {
            GraphItem::Number(value) => Value::number(value),
            GraphItem::Boolean(value) => Ok(Value::Boolean(*value)),
            GraphItem::Reference(id) => match self.graph.nodes.get(id) {
                Some(ObjectNode::Text(value)) => Ok(Value::Text(value.as_str().into())),
                Some(ObjectNode::Symbol {
                    name,
                    interned: true,
                }) => Ok(Value::Symbol(name.as_str().into())),
                _ => Self::new(
                    self.owner,
                    self.observation,
                    ObjectGraph {
                        root: item.clone(),
                        nodes: self.graph.nodes.clone(),
                    },
                )
                .map(Value::Object),
            },
            _ => Self::new(
                self.owner,
                self.observation,
                ObjectGraph {
                    root: item.clone(),
                    nodes: self.graph.nodes.clone(),
                },
            )
            .map(Value::Object),
        }
    }
    /// Freeze a validated observation and compute its cycle-safe structural key.
    /// Transport reachable immutable data, retaining sharing within one native call.
    #[must_use]
    pub fn scheme_input(&self) -> crate::Data {
        crate::Data::object([
            ("type", crate::Data::from("graph")),
            ("value", self.graph.to_scheme()),
            (
                "namespace",
                crate::Data::List(vec![
                    crate::Data::from(self.owner),
                    crate::Data::from(self.observation),
                ]),
            ),
        ])
    }
    /// # Errors
    /// Rejects dangling references and graphs exceeding structural key limits.
    pub fn new(owner: u64, observation: u64, graph: ObjectGraph) -> Result<Self> {
        let mut builder = Builder {
            owner,
            nodes: Vec::new(),
            ids: BTreeMap::new(),
            queue: VecDeque::new(),
        };
        let root = builder.item(&graph.root);
        while let Some((id, index)) = builder.queue.pop_front() {
            let node = graph
                .nodes
                .get(&id)
                .ok_or_else(|| Error::Evaluation("dangling frozen value".into()))?;
            let (label, children) = match node {
                ObjectNode::Text(v) => (Label::Text(v.clone()), vec![]),
                ObjectNode::Symbol {
                    name,
                    interned: true,
                } => (Label::Symbol(name.clone()), vec![]),
                ObjectNode::Pair(a, b) => (Label::Pair, vec![a, b]),
                ObjectNode::Vector(items) => (Label::Vector, items.iter().collect()),
                ObjectNode::Bytes(v) => (Label::Bytes(v.clone()), vec![]),
                _ => (Label::Identity(builder.owner, id), vec![]),
            };
            let edges = children
                .into_iter()
                .map(|item| builder.item(item))
                .collect();
            builder.nodes[index] = Node { label, edges };
        }
        let key = canonical(&builder.nodes, root)?;
        let mut hash = std::collections::hash_map::DefaultHasher::new();
        key.hash(&mut hash);
        let numeric = match &graph.root {
            GraphItem::Number(text) => crate::numbers::parse_number(text).map(Arc::new),
            _ => None,
        };
        Ok(Self {
            numeric,
            owner,
            observation,
            hash: hash.finish(),
            key: key.into(),
            graph: Arc::new(graph),
        })
    }
    pub(crate) fn is_scalar(&self) -> bool {
        match &self.graph.root {
            GraphItem::Character(_) => true,
            GraphItem::Reference(id) => {
                matches!(self.graph.nodes.get(id), Some(ObjectNode::Symbol { .. }))
            }
            _ => false,
        }
    }
    pub(crate) fn numeric(&self) -> Option<&crate::numbers::Number> {
        self.numeric.as_deref()
    }
    pub(crate) fn number(&self) -> Option<num_rational::BigRational> {
        match self.numeric()? {
            crate::numbers::Number::Exact(n) => Some(n.clone()),
            crate::numbers::Number::Inexact(_) => None,
        }
    }
    pub(crate) fn observation(&self) -> u64 {
        self.observation
    }
    pub(crate) fn owner(&self) -> u64 {
        self.owner
    }
    #[must_use]
    pub fn graph(&self) -> &ObjectGraph {
        &self.graph
    }
}
struct Builder {
    owner: u64,
    nodes: Vec<Node>,
    ids: BTreeMap<usize, usize>,
    queue: VecDeque<(usize, usize)>,
}
impl Builder {
    fn item(&mut self, item: &GraphItem) -> usize {
        if let GraphItem::Reference(id) = item {
            if let Some(index) = self.ids.get(id) {
                return *index;
            }
            let index = self.nodes.len();
            self.ids.insert(*id, index);
            self.nodes.push(Node {
                label: Label::Void,
                edges: vec![],
            });
            self.queue.push_back((*id, index));
            return index;
        }
        let label = match item {
            GraphItem::Void => Label::Void,
            GraphItem::Null => Label::Null,
            GraphItem::Boolean(v) => Label::Boolean(*v),
            GraphItem::Number(v) => Label::Number(crate::numbers::canonical_text(v)),
            GraphItem::Character(v) => Label::Character(*v),
            GraphItem::Reference(_) => unreachable!(),
        };
        let index = self.nodes.len();
        self.nodes.push(Node {
            label,
            edges: vec![],
        });
        index
    }
}
fn canonical(nodes: &[Node], root: usize) -> Result<Vec<Node>> {
    // Monotone partition refinement computes bisimulation even for unequal cycle lengths.
    // Bound total edge work rather than allowing adversarial chains quadratic allocation.
    let mut classes = vec![0; nodes.len()];
    let mut work = 0usize;
    loop {
        let mut signatures = BTreeMap::new();
        let mut next = Vec::with_capacity(nodes.len());
        for (i, node) in nodes.iter().enumerate() {
            work = work.saturating_add(1 + node.edges.len());
            if work > 4_194_304 {
                return Err(Error::StateLimit);
            }
            let signature = (
                classes[i],
                &node.label,
                node.edges.iter().map(|e| classes[*e]).collect::<Vec<_>>(),
            );
            let id = signatures.len();
            next.push(*signatures.entry(signature).or_insert(id));
        }
        if next == classes {
            break;
        }
        classes = next;
    }
    let representatives: BTreeMap<_, _> =
        classes.iter().enumerate().map(|(i, c)| (*c, i)).collect();
    let mut numbered = BTreeMap::from([(classes[root], 0)]);
    let mut queue = VecDeque::from([classes[root]]);
    let mut out = Vec::new();
    while let Some(class) = queue.pop_front() {
        let node = &nodes[representatives[&class]];
        let edges = node
            .edges
            .iter()
            .map(|e| {
                let class = classes[*e];
                let next = numbered.len();
                *numbered.entry(class).or_insert_with(|| {
                    queue.push_back(class);
                    next
                })
            })
            .collect();
        out.push(Node {
            label: node.label.clone(),
            edges,
        });
    }
    Ok(out)
}
