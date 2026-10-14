//! Owner-local arena: identity and cycles never depend on Python object addresses.
use crate::{Error, GraphItem, ObjectGraph, ObjectNode, Result, source::Datum};
use num_bigint::BigInt;
use num_rational::BigRational;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
pub(super) type Id = usize;
pub(super) type EnvId = usize;
#[derive(Clone)]
pub(super) enum Object {
    Reachability(Arc<std::sync::Mutex<crate::Reachability>>, Vec<Id>),
    ClosureView(crate::ReachabilitySnapshot, Vec<Id>),
    RowsView(Arc<[crate::Row]>, Vec<Id>),
    Compiled(Arc<crate::Program>, Vec<Id>),
    Fragment(Arc<super::operator_lowering::Fragment>),
    Execution(Arc<std::sync::Mutex<crate::Session>>, BTreeMap<String, Id>),
    Completed(Arc<crate::Snapshot>, Vec<Id>),
    Relation(crate::Relation, Id),
    Rule(crate::Rule, Id),
    Void,
    Null,
    Boolean(bool),
    Number(BigRational),
    Inexact(f64),
    Character(char),
    Text(String),
    Symbol(String, bool),
    Pair(Id, Id),
    Vector(Vec<Id>),
    Bytes(Vec<u8>),
    Table {
        entries: Vec<(Id, Id)>,
        identity: bool,
    },
    Procedure(Procedure),
    Record(String, Vec<Id>),
}
#[derive(Clone)]
pub(super) enum Procedure {
    Rows(Arc<crate::Snapshot>, Vec<Id>),
    Query(String),
    Builtin(&'static str),
    Closure {
        parameters: Arc<[String]>,
        rest: Option<Arc<str>>,
        body: Arc<[Datum]>,
        env: EnvId,
    },
}
#[derive(Clone)]
pub(super) enum Binding {
    Local(Id),
    Alias(EnvId, String),
}
#[derive(Default)]
pub(super) struct Environment {
    pub parent: Option<EnvId>,
    pub bindings: BTreeMap<String, Binding>,
    pub macros: BTreeMap<String, Vec<(Datum, Datum)>>,
}
#[derive(Default)]
pub(super) struct Arena {
    pub identity: u64,
    pub objects: BTreeMap<Id, Object>,
    pub environments: BTreeMap<EnvId, Environment>,
    symbols: BTreeMap<String, Id>,
    handles: BTreeMap<String, Id>,
    handle_names: BTreeMap<Id, String>,
    next: usize,
    next_env: usize,
}
impl Arena {
    pub fn register_name(&mut self, id: Id) -> Result<()> {
        if matches!(self.get(id)?, Object::Symbol(_, false)) && !self.handle_names.contains_key(&id)
        {
            let key = format!("relation-handle-{}-{}-symbol", self.identity, id);
            self.handles.insert(key.clone(), id);
            self.handle_names.insert(id, key);
        }
        Ok(())
    }
    pub fn relation_name(&mut self, name: &str) -> Result<Id> {
        if !name.starts_with("relation-handle-") {
            return self.symbol(name, true);
        }
        if let Some(id) = self.handles.get(name) {
            return Ok(*id);
        }
        let id = self.symbol(name, false)?;
        self.handles.insert(name.into(), id);
        self.handle_names.insert(id, name.into());
        Ok(id)
    }
    pub fn checked_name(&self, id: Id) -> Result<String> {
        match self.get(id)? {
            Object::Symbol(name, true) if !name.starts_with("relation-handle-") => Ok(name.clone()),
            Object::Symbol(_, false) => self
                .handle_names
                .get(&id)
                .cloned()
                .ok_or_else(|| fail("unregistered symbolic declaration")),
            _ => Err(fail(
                "live relation identity or interned declaration name required",
            )),
        }
    }
    pub fn add(&mut self, object: Object) -> Result<Id> {
        if self.objects.len() >= 262_144 {
            return Err(fail("module object allocation bound"));
        }
        self.next = self
            .next
            .checked_add(1)
            .ok_or_else(|| fail("object identity overflow"))?;
        self.objects.insert(self.next, object);
        Ok(self.next)
    }
    pub fn env(&mut self, parent: Option<EnvId>) -> Result<EnvId> {
        if self.environments.len() >= 65_536 {
            return Err(fail("lexical environment bound"));
        }
        self.next_env = self
            .next_env
            .checked_add(1)
            .ok_or_else(|| fail("scope identity overflow"))?;
        self.environments.insert(
            self.next_env,
            Environment {
                parent,
                ..Environment::default()
            },
        );
        Ok(self.next_env)
    }
    pub fn get(&self, id: Id) -> Result<&Object> {
        self.objects.get(&id).ok_or_else(|| fail("released object"))
    }
    pub fn lookup(&self, env: EnvId, name: &str) -> Result<Id> {
        let (env, name) = self.location(env, name, 0)?;
        match self.environments[&env].bindings.get(&name) {
            Some(Binding::Local(id)) => Ok(*id),
            _ => Err(fail("invalid binding location")),
        }
    }
    fn location(&self, env: EnvId, name: &str, depth: usize) -> Result<(EnvId, String)> {
        if depth > 256 {
            return Err(fail("binding lookup depth bound"));
        }
        let scope = self
            .environments
            .get(&env)
            .ok_or_else(|| fail("released scope"))?;
        match scope.bindings.get(name) {
            Some(Binding::Local(_)) => Ok((env, name.into())),
            Some(Binding::Alias(target, binding)) => self.location(*target, binding, depth + 1),
            None => scope
                .parent
                .ok_or_else(|| fail(&format!("unbound Scheme identifier: {name}")))
                .and_then(|parent| self.location(parent, name, depth + 1)),
        }
    }
    pub fn bind(&mut self, env: EnvId, name: String, value: Id) {
        let scope = self.environments.get_mut(&env).expect("live scope");
        scope.macros.remove(&name);
        scope.bindings.insert(name, Binding::Local(value));
    }
    pub fn assign(&mut self, env: EnvId, name: &str, value: Id) -> Result<()> {
        let (env, name) = self.location(env, name, 0)?;
        self.bind(env, name, value);
        Ok(())
    }
    pub fn list(&mut self, items: &[Id]) -> Result<Id> {
        let mut tail = self.add(Object::Null)?;
        for head in items.iter().rev() {
            tail = self.add(Object::Pair(*head, tail))?;
        }
        Ok(tail)
    }
    pub fn items(&self, mut id: Id) -> Result<Vec<Id>> {
        let mut seen = BTreeSet::new();
        let mut out = Vec::new();
        loop {
            if !seen.insert(id) {
                return Err(fail("cyclic list"));
            }
            match self.get(id)? {
                Object::Null => return Ok(out),
                Object::Pair(a, b) => {
                    out.push(*a);
                    id = *b;
                }
                _ => return Err(fail("proper list required")),
            }
        }
    }
    pub fn number(&self, id: Id) -> Result<BigRational> {
        match self.get(id)? {
            Object::Number(v) => Ok(v.clone()),
            _ => Err(fail("number required")),
        }
    }
    pub fn integer(&self, id: Id) -> Result<BigInt> {
        let v = self.number(id)?;
        if !v.is_integer() {
            return Err(fail("exact integer required"));
        }
        Ok(v.to_integer())
    }
    pub fn truth(&self, id: Id) -> Result<bool> {
        Ok(!matches!(self.get(id)?, Object::Boolean(false)))
    }
    pub fn symbol(&mut self, name: &str, interned: bool) -> Result<Id> {
        if interned && let Some(id) = self.symbols.get(name) {
            return Ok(*id);
        }
        let id = self.add(Object::Symbol(name.into(), interned))?;
        if interned {
            self.symbols.insert(name.into(), id);
        }
        Ok(id)
    }

    pub fn collect(&mut self, roots: &[Id], scopes: &[EnvId]) {
        let mut objects = BTreeSet::new();
        let mut envs = BTreeSet::new();
        let mut pending = roots.to_vec();
        let mut environments = scopes.to_vec();
        loop {
            self.trace_environments(&mut environments, &mut envs, &mut pending);
            let Some(id) = pending.pop() else { break };
            if objects.insert(id) {
                self.trace_object(id, &mut pending, &mut environments);
            }
        }
        self.objects.retain(|id, _| objects.contains(id));
        self.symbols.retain(|_, id| objects.contains(id));
        self.handles.retain(|_, id| objects.contains(id));
        self.handle_names.retain(|id, _| objects.contains(id));
        self.environments.retain(|id, _| envs.contains(id));
    }
    fn trace_environments(
        &self,
        pending: &mut Vec<EnvId>,
        seen: &mut BTreeSet<EnvId>,
        objects: &mut Vec<Id>,
    ) {
        while let Some(env) = pending.pop() {
            if !seen.insert(env) {
                continue;
            }
            if let Some(scope) = self.environments.get(&env) {
                Self::trace_scope(scope, pending, objects);
            }
        }
    }
    fn trace_scope(scope: &Environment, pending: &mut Vec<EnvId>, objects: &mut Vec<Id>) {
        pending.extend(scope.parent);
        for binding in scope.bindings.values() {
            match binding {
                Binding::Local(id) => objects.push(*id),
                Binding::Alias(env, _) => pending.push(*env),
            }
        }
    }
    fn trace_object(&self, id: Id, pending: &mut Vec<Id>, environments: &mut Vec<EnvId>) {
        if let Some(object) = self.objects.get(&id) {
            match object {
                Object::Fragment(f) => pending.extend(
                    f.exports
                        .values()
                        .filter_map(|name| self.handles.get(name))
                        .copied(),
                ),
                Object::Compiled(p, _) => pending.extend(
                    p.relations
                        .iter()
                        .filter_map(|r| self.handles.get(&r.name))
                        .copied(),
                ),
                _ => (),
            }
            match object {
                Object::Relation(_, root) | Object::Rule(_, root) => pending.push(*root),
                Object::Compiled(_, roots)
                | Object::Completed(_, roots)
                | Object::Procedure(Procedure::Rows(_, roots))
                | Object::Reachability(_, roots)
                | Object::ClosureView(_, roots)
                | Object::RowsView(_, roots) => pending.extend(roots),
                Object::Fragment(fragment) => pending.push(fragment.root),
                Object::Execution(_, roots) => pending.extend(roots.values()),
                Object::Pair(a, b) => pending.extend([*a, *b]),
                Object::Vector(ids) | Object::Record(_, ids) => pending.extend(ids),
                Object::Table { entries, .. } => {
                    pending.extend(entries.iter().flat_map(|(a, b)| [*a, *b]));
                }
                Object::Procedure(Procedure::Closure { env, .. }) => environments.push(*env),
                _ => (),
            }
        }
    }
}
pub(super) fn fail(message: &str) -> Error {
    Error::Evaluation(message.into())
}
/// Typed argument boundary; no wire serialization or Python objects enter the owner.
#[derive(Clone, Debug)]
pub enum ObjectInput {
    ResultValue(crate::RowValue),
    Value(crate::Value),
    Integer(BigInt),
    Rational(BigRational),
    Inexact(f64),
    Boolean(bool),
    Number(String),
    Character(char),
    Text(String),
    Symbol(String),
    List(Vec<Self>),
    Pair(Box<Self>, Box<Self>),
    Vector(Vec<Self>),
    Bytes(Vec<u8>),
    Reference(ValueReference),
}
/// Reference authority is validated against its originating live value lease.
#[derive(Clone, Debug)]
pub struct ValueReference {
    pub owner: u64,
    pub result: u64,
    pub node: usize,
}
impl Arena {
    pub fn graph(&self, root: Id) -> Result<ObjectGraph> {
        let mut graph = ObjectGraph {
            root: GraphItem::Void,
            nodes: BTreeMap::new(),
        };
        let mut queue = Vec::new();
        graph.root = self.graph_item(root, &mut queue)?;
        while let Some(id) = queue.pop() {
            if graph.nodes.contains_key(&id) {
                continue;
            }
            if graph.nodes.len() >= 65_536 {
                return Err(fail("native graph transport bound"));
            }
            let node = match self.get(id)? {
                Object::Text(s) => ObjectNode::Text(s.clone()),
                Object::Symbol(name, interned) => ObjectNode::Symbol {
                    name: name.clone(),
                    interned: *interned,
                },
                Object::Pair(a, b) => ObjectNode::Pair(
                    self.graph_item(*a, &mut queue)?,
                    self.graph_item(*b, &mut queue)?,
                ),
                Object::Vector(items) => ObjectNode::Vector(
                    items
                        .iter()
                        .map(|v| self.graph_item(*v, &mut queue))
                        .collect::<Result<_>>()?,
                ),
                Object::Bytes(items) => ObjectNode::Bytes(items.clone()),
                Object::Table { entries, .. } => ObjectNode::Table(
                    entries
                        .iter()
                        .map(|(a, b)| {
                            Ok((
                                self.graph_item(*a, &mut queue)?,
                                self.graph_item(*b, &mut queue)?,
                            ))
                        })
                        .collect::<Result<_>>()?,
                ),
                Object::Record(kind, _) => ObjectNode::Opaque(kind.clone()),
                Object::Reachability(_, _) => ObjectNode::Opaque("reachability".into()),
                Object::ClosureView(_, _) | Object::RowsView(_, _) => {
                    ObjectNode::Opaque("relation-view".into())
                }
                Object::Compiled(_, _) => ObjectNode::Opaque("program".into()),
                Object::Fragment(_) => ObjectNode::Opaque("fragment".into()),
                Object::Execution(_, _) => ObjectNode::Opaque("session".into()),
                Object::Completed(_, _) => ObjectNode::Opaque("solution".into()),
                Object::Relation(_, _) => ObjectNode::Opaque("relation".into()),
                Object::Rule(_, _) => ObjectNode::Opaque("rule".into()),
                Object::Procedure(_) => ObjectNode::Opaque("procedure".into()),
                _ => return Err(fail("inline value queued as observation node")),
            };
            graph.nodes.insert(id, node);
        }
        Ok(graph)
    }
    fn graph_item(&self, id: Id, queue: &mut Vec<Id>) -> Result<GraphItem> {
        Ok(match self.get(id)? {
            Object::Void => GraphItem::Void,
            Object::Null => GraphItem::Null,
            Object::Boolean(v) => GraphItem::Boolean(*v),
            Object::Number(v) => GraphItem::Number(v.to_string()),
            Object::Inexact(v) => GraphItem::Number(crate::numbers::format_inexact(*v)),
            Object::Character(v) => GraphItem::Character(*v),
            _ => {
                queue.push(id);
                GraphItem::Reference(id)
            }
        })
    }
}
