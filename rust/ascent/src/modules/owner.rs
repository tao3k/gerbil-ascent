//! Module and returned-value ownership, export resolution and checked references.
use super::{ObjectInput, ValueReference};
use super::{
    components::{Component, link},
    evaluation::{Evaluation, atom, number, validate_binding},
    objects::{Arena, EnvId, Id, Object, fail},
    primitives,
};
use crate::ObjectGraph;
use crate::{
    Engine, Error, Result,
    source::{Datum, definitions},
};
use num_traits::Zero;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
};
static NEXT_OWNER: AtomicU64 = AtomicU64::new(1);
static NEXT_VALUE: AtomicU64 = AtomicU64::new(1);
pub(super) struct OwnerPermit(Arc<AtomicUsize>);
impl Drop for OwnerPermit {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}
struct Lease {
    root: Id,
    count: usize,
    observation: Option<Arc<ObjectGraph>>,
    retained: BTreeSet<Id>,
    released: Arc<AtomicBool>,
}
pub(super) struct State {
    pub arena: Arena,
    pub engine: Engine,
    pub scopes: BTreeMap<String, (EnvId, BTreeSet<String>)>,
    pub entry: String,
    order: Vec<String>,
    pub(super) primitives: Option<EnvId>,
    pub(super) pins: BTreeMap<u64, Id>,
    leases: BTreeMap<u64, Lease>,
    pub closed: Arc<AtomicBool>,
    revocations: Arc<AtomicBool>,
    pub identity: u64,
    pub(super) permit: Option<OwnerPermit>,
    next_collection: usize,
    next_environment_collection: usize,
}
/// A loaded definition scope. Clones share one explicit close boundary.
#[derive(Clone)]
pub struct Module {
    pub(super) state: Arc<Mutex<State>>,
    closed: Arc<AtomicBool>,
    revocations: Arc<AtomicBool>,
    engine: Engine,
    identity: u64,
}
/// An independently releasable return value. Dropping it releases its lease.
pub struct ModuleValue {
    pub(super) owner: Module,
    handle: u64,
    pub(super) root: Id,
    count: usize,
    released: Arc<AtomicBool>,
}
impl Engine {
    /// Load definitions without invoking a compiler in the consuming application.
    /// # Errors
    /// Rejects malformed definitions, unsupported forms, or a closed engine.
    pub fn load_definitions(&self, source: &str) -> Result<Module> {
        Module::load(
            self,
            &[Component {
                id: "entry".into(),
                source: source.into(),
                exports: None,
                dependencies: Vec::new(),
            }],
            "entry",
        )
    }
    /// Link a validated component dependency closure into isolated lexical scopes.
    /// # Errors
    /// Rejects cycles, missing or conflicting imports and invalid definitions.
    pub fn load_components(&self, components: &[Component], entry: &str) -> Result<Module> {
        Module::load(self, components, entry)
    }
}
impl Module {
    fn load(engine: &Engine, components: &[Component], entry: &str) -> Result<Self> {
        if engine.is_closed() {
            return Err(Error::Closed);
        }
        engine
            .module_owners
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |count| {
                (count < 64).then_some(count + 1)
            })
            .map_err(|_| fail("module owner limit"))?;
        let permit = OwnerPermit(engine.module_owners.clone());
        let selected = link(components, entry)?;
        let closed = Arc::default();
        let revocations = Arc::default();
        let identity = NEXT_OWNER.fetch_add(1, Ordering::Relaxed);
        let mut state = State {
            arena: Arena::default(),
            engine: engine.clone(),
            scopes: BTreeMap::new(),
            entry: entry.into(),
            order: Vec::new(),
            primitives: None,
            pins: BTreeMap::new(),
            leases: BTreeMap::new(),
            closed: Arc::clone(&closed),
            revocations: Arc::clone(&revocations),
            identity,
            permit: Some(permit),
            next_collection: 1024,
            next_environment_collection: 512,
        };
        state.arena.identity = identity;
        let primitives = state.arena.env(None)?;
        primitives::install(&mut state.arena, primitives)?;
        state.primitives = Some(primitives);
        for component in selected {
            state.load_component(component, primitives, engine)?;
        }
        Ok(Self {
            state: Arc::new(Mutex::new(state)),
            closed,
            revocations,
            engine: engine.clone(),
            identity,
        })
    }
    /// Call an exported binding, resolving mutable exports on every invocation.
    /// # Errors
    /// Rejects closed owners, inaccessible exports, invalid references and failed calls.
    pub fn call(
        &self,
        export: &str,
        arguments: &[ObjectInput],
        component: Option<&str>,
    ) -> Result<ModuleValue> {
        let mut state = self.lock()?;
        state.check()?;
        let (env, exports) = state
            .scopes
            .get(component.unwrap_or(&state.entry))
            .ok_or_else(|| fail("component not loaded"))?;
        if !exports.contains(export) {
            return Err(fail("module export is not available"));
        }
        let procedure = state.arena.lookup(*env, export)?;
        let handle = state.invoke(procedure, arguments)?;
        let lease = state
            .leases
            .get(&handle)
            .ok_or_else(|| fail("module value released"))?;
        Ok(ModuleValue::retained(self.clone(), handle, lease))
    }
    /// Loaded components in dependency order.
    /// # Errors
    /// Rejects closed owners or poisoned state.
    pub fn components(&self) -> Result<Vec<String>> {
        let state = self.lock()?;
        state.check()?;
        Ok(state.order.clone())
    }
    /// Close invalidates all returned objects and references immediately.
    pub fn close(&self) {
        self.closed.store(true, Ordering::Release);
        if let Ok(mut state) = self.state.lock() {
            if state.pins.is_empty() {
                state.permit.take();
            }
            state.leases.clear();
            state.scopes.clear();
            state.order.clear();
            if state.pins.is_empty() {
                state.arena = Arena::default();
            }
        }
    }
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire) || self.engine.is_closed()
    }
    pub(super) fn lock(&self) -> Result<std::sync::MutexGuard<'_, State>> {
        self.state
            .lock()
            .map_err(|_| fail("module state lock poisoned"))
    }
}
impl State {
    pub(super) fn load_component(
        &mut self,
        component: &Component,
        primitives: EnvId,
        engine: &Engine,
    ) -> Result<()> {
        let forms = definitions(&component.source)?;
        let mut exports = BTreeSet::new();
        for form in &forms {
            super::native_forms::validate_syntax(form)?;
            exports.insert(definition_name(form)?.into());
        }
        let env = self.arena.env(Some(primitives))?;
        for dependency in &component.dependencies {
            self.import(env, dependency, &exports)?;
        }
        Evaluation::new(&mut self.arena, engine).sequence(&forms, env, 0)?;
        if let Some(explicit) = &component.exports {
            if explicit.iter().any(|name| !exports.contains(name)) {
                return Err(fail("component export is not defined"));
            }
            exports = explicit.iter().cloned().collect();
        }
        self.scopes.insert(component.id.clone(), (env, exports));
        self.order.push(component.id.clone());
        Ok(())
    }
    fn import(
        &mut self,
        env: EnvId,
        dependency: &super::Dependency,
        locals: &BTreeSet<String>,
    ) -> Result<()> {
        let (target, allowed) = &self.scopes[&dependency.component];
        for name in &dependency.bindings {
            if !allowed.contains(name) {
                return Err(fail("dependency binding not exported"));
            }
            if locals.contains(name) {
                return Err(fail("import conflicts with local definition"));
            }
            self.arena
                .environments
                .get_mut(&env)
                .expect("live scope")
                .bindings
                .insert(
                    name.clone(),
                    super::objects::Binding::Alias(*target, name.clone()),
                );
        }
        Ok(())
    }
    fn check(&self) -> Result<()> {
        if self.closed.load(Ordering::Acquire) || self.engine.is_closed() {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
    fn invoke(&mut self, procedure: Id, arguments: &[ObjectInput]) -> Result<u64> {
        self.prune_released();
        if self.leases.len() >= 64 {
            return Err(fail("module value limit; release values"));
        }
        // Admission borrows the procedure even if another caller revokes its
        // public lease while this invocation is waiting for the arena lock.
        self.collect_keeping(&[procedure]);
        let result = (|| {
            let args = arguments
                .iter()
                .map(|v| self.input(v, 0))
                .collect::<Result<Vec<_>>>()?;
            let (root, count) =
                Evaluation::new(&mut self.arena, &self.engine).invoke(procedure, &args)?;
            self.check()?;
            let handle = NEXT_VALUE.fetch_add(1, Ordering::Relaxed);
            self.leases.insert(
                handle,
                Lease {
                    root,
                    count,
                    observation: None,
                    retained: BTreeSet::from([root]),
                    released: Arc::default(),
                },
            );
            Ok(handle)
        })();
        self.collect_if_needed();
        result
    }
    fn prune_released(&mut self) {
        if self.revocations.swap(false, Ordering::AcqRel) {
            self.leases
                .retain(|_, lease| !lease.released.load(Ordering::Acquire));
        }
    }
    pub(super) fn collect_if_needed(&mut self) {
        self.collect_keeping(&[]);
    }
    fn collect_keeping(&mut self, temporary_roots: &[Id]) {
        if self.arena.objects.len() < self.next_collection
            && self.arena.environments.len() < self.next_environment_collection
        {
            return;
        }
        let roots = self
            .leases
            .values()
            .flat_map(|lease| lease.retained.iter().copied())
            .chain(self.pins.values().copied())
            .chain(temporary_roots.iter().copied())
            .collect::<Vec<_>>();
        let scopes = self
            .scopes
            .values()
            .map(|(env, _)| *env)
            .collect::<Vec<_>>();
        self.arena.collect(&roots, &scopes);
        self.next_collection = self
            .arena
            .objects
            .len()
            .saturating_mul(2)
            .clamp(1024, 261_120);
        self.next_environment_collection = self
            .arena
            .environments
            .len()
            .saturating_mul(2)
            .clamp(512, 65_024);
    }
    pub(super) fn input(&mut self, input: &ObjectInput, depth: usize) -> Result<Id> {
        if depth > 128 {
            return Err(fail("argument nesting bound"));
        }
        let object = match input {
            ObjectInput::ResultValue(value) => {
                return self.input(&ObjectInput::Value(value.value()?), depth + 1);
            }
            ObjectInput::Value(value) => {
                if let crate::Value::Object(value) = value
                    && value.owner() != self.identity
                    && !value.detached_scalar()
                {
                    return Err(fail("foreign frozen module value"));
                }
                return self.arena.thaw(value);
            }
            ObjectInput::Reference(reference) => {
                if reference.owner != self.identity {
                    return Err(fail("foreign module value"));
                }
                let lease = self
                    .leases
                    .get(&reference.result)
                    .ok_or_else(|| fail("released or foreign module value"))?;
                if lease.released.load(Ordering::Acquire)
                    || !lease.retained.contains(&reference.node)
                {
                    return Err(fail("reference node is not retained"));
                }
                return Ok(reference.node);
            }
            ObjectInput::Integer(value) => {
                Object::Number(num_rational::BigRational::from_integer(value.clone()))
            }
            ObjectInput::Rational(value) => {
                if value.denom().is_zero() {
                    return Err(fail("invalid exact rational denominator"));
                }
                Object::Number(num_rational::BigRational::new(
                    value.numer().clone(),
                    value.denom().clone(),
                ))
            }
            ObjectInput::Inexact(v) => Object::Inexact(*v),
            ObjectInput::Boolean(v) => Object::Boolean(*v),
            ObjectInput::Number(v) => {
                if let Some(n) = number(v) {
                    Object::Number(n)
                } else {
                    Object::Inexact(
                        crate::numbers::parse_inexact(v)
                            .ok_or_else(|| fail("invalid Scheme real number"))?,
                    )
                }
            }
            ObjectInput::Character(v) => Object::Character(*v),
            ObjectInput::Text(v) => Object::Text(v.clone()),
            ObjectInput::Symbol(v) => return self.arena.symbol(v, true),
            ObjectInput::Bytes(v) => Object::Bytes(v.clone()),
            ObjectInput::Vector(items) => Object::Vector(
                items
                    .iter()
                    .map(|v| self.input(v, depth + 1))
                    .collect::<Result<_>>()?,
            ),
            ObjectInput::List(items) => {
                let values = items
                    .iter()
                    .map(|v| self.input(v, depth + 1))
                    .collect::<Result<Vec<_>>>()?;
                return self.arena.list(&values);
            }
            ObjectInput::Pair(a, b) => {
                Object::Pair(self.input(a, depth + 1)?, self.input(b, depth + 1)?)
            }
        };
        self.arena.add(object)
    }
}
impl ModuleValue {
    fn retained(owner: Module, handle: u64, lease: &Lease) -> Self {
        Self {
            owner,
            handle,
            root: lease.root,
            count: lease.count,
            released: Arc::clone(&lease.released),
        }
    }
    pub(super) fn check(&self) -> Result<()> {
        if self.owner.is_closed() {
            return Err(Error::Closed);
        }
        if self.released.load(Ordering::Acquire) {
            return Err(fail("module value released"));
        }
        Ok(())
    }
    #[must_use]
    pub fn handle(&self) -> u64 {
        self.handle
    }
    /// # Errors
    /// Rejects released values or closed owners.
    pub fn graph(&self) -> Result<Arc<ObjectGraph>> {
        self.check()?;
        let mut state = self.owner.lock()?;
        state.check()?;
        let lease = state
            .leases
            .get(&self.handle)
            .ok_or_else(|| fail("module value released"))?;
        if let Some(observation) = &lease.observation {
            return Ok(observation.clone());
        }
        let observation = Arc::new(state.arena.graph(lease.root)?);
        self.check()?;
        state.check()?;
        let lease = state
            .leases
            .get_mut(&self.handle)
            .ok_or_else(|| fail("module value released"))?;
        lease.retained.extend(observation.nodes.keys());
        lease.observation = Some(observation.clone());
        Ok(observation)
    }
    /// # Errors
    /// Rejects released values or closed owners.
    pub fn value_count(&self) -> Result<usize> {
        self.check()?;
        Ok(self.count)
    }
    /// # Errors
    /// Rejects nodes outside this returned graph or released values.
    pub fn reference(&self, node: Option<usize>) -> Result<ValueReference> {
        self.check()?;
        let node = match node {
            None => self.root,
            Some(node) => {
                let state = self.owner.lock()?;
                state.check()?;
                self.check()?;
                let lease = state
                    .leases
                    .get(&self.handle)
                    .ok_or_else(|| fail("module value released"))?;
                if !lease.retained.contains(&node) {
                    return Err(fail("reference node is not retained"));
                }
                node
            }
        };
        Ok(ValueReference {
            owner: self.owner.identity,
            result: self.handle,
            node,
        })
    }
    /// Apply an owned lexical procedure with the same authority as module calls.
    /// # Errors
    /// Rejects nonprocedures, invalid arguments, released values and closed owners.
    pub fn apply(&self, arguments: &[ObjectInput]) -> Result<Self> {
        self.check()?;
        let mut state = self.owner.lock()?;
        state.check()?;
        self.check()?;
        let procedure = state
            .leases
            .get(&self.handle)
            .ok_or_else(|| fail("module value released"))?
            .root;
        let handle = state.invoke(procedure, arguments)?;
        let lease = state
            .leases
            .get(&handle)
            .ok_or_else(|| fail("module value released"))?;
        Ok(Self::retained(self.owner.clone(), handle, lease))
    }
    pub fn close(&self) {
        if self.released.swap(true, Ordering::AcqRel) {
            return;
        }
        self.owner.revocations.store(true, Ordering::Release);
        if let Ok(mut state) = self.owner.state.try_lock() {
            state.prune_released();
            state.collect_if_needed();
        }
    }
}
impl Drop for ModuleValue {
    fn drop(&mut self) {
        self.close();
    }
}
fn definition_name(datum: &Datum) -> Result<&str> {
    let Datum::List(parts) = datum else {
        return Err(fail("Scheme definition required"));
    };
    let [head, name, ..] = parts.as_slice() else {
        return Err(fail("Scheme definition required"));
    };
    if !matches!(
        atom(head),
        Some("def" | "define" | "defrules" | "define-evidence")
    ) {
        return Err(fail("unsupported module definition form"));
    }
    let name = match name {
        Datum::Atom(name) => name.as_str(),
        Datum::List(signature) => signature
            .first()
            .and_then(atom)
            .ok_or_else(|| fail("definition name required"))?,
        Datum::Text(_) => return Err(fail("definition name required")),
    };
    validate_binding(name)?;
    Ok(name)
}
