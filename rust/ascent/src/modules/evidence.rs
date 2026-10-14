//! Constructor-owned sessions and independent, explicitly recorded explanation observations.
use super::{
    Module, ObjectInput,
    constructors::Admission,
    evaluation::Evaluation,
    objects::{Id, Object, fail},
    owner::ModuleValue,
    replacement,
};
use crate::{
    Cancellation, Error, FactLimits, Limits, ObjectGraph, Result, SourceObservation, SourceResult,
    SourceSession,
};
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
};
static NEXT_PIN: AtomicU64 = AtomicU64::new(1);
struct SessionPermit(Arc<AtomicUsize>);
impl Drop for SessionPermit {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::AcqRel);
    }
}
struct Inner {
    permit: Mutex<Option<SessionPermit>>,
    module: Module,
    pin: u64,
    program: Id,
    constructor: Id,
    source_roots: Mutex<BTreeMap<String, Id>>,
    explainer: Id,
    session: Mutex<SourceSession>,
    closed: AtomicBool,
}
impl Inner {
    fn check(&self) -> Result<()> {
        if self.closed.load(Ordering::Acquire) {
            Err(Error::Closed)
        } else {
            self.module
                .state
                .lock()
                .map_err(|_| fail("module lock poisoned"))?
                .engine
                .check()
        }
    }
    fn unpin(&self) {
        if let Ok(mut state) = self.module.state.lock() {
            state.pins.remove(&self.pin);
            if state.closed.load(Ordering::Acquire) && state.pins.is_empty() {
                state.arena = super::objects::Arena::default();
                state.permit.take();
            }
        }
    }
}
impl Drop for Inner {
    fn drop(&mut self) {
        self.unpin();
    }
}
/// An evidence constructor admitted into the Rust runtime. Module public closure does
/// not revoke the session's private lexical roots; engine/session closure does.
#[derive(Clone)]
pub struct Evidence(Arc<Inner>);
impl ModuleValue {
    /// Admit a returned program or evidence-module constructor without user compilation.
    /// # Errors
    /// Invalid/released constructors, unsafe rules or exhausted session pins are rejected.
    pub fn open_session(&self, limits: FactLimits) -> Result<Evidence> {
        self.check()?;
        let mut state = self.owner.lock()?;
        self.check()?;
        if state.pins.len() >= 64 {
            return Err(fail("evidence session limit"));
        }
        let (program, explainer) = match state.arena.get(self.root)? {
            Object::Record(kind, fields)
                if kind == "evidence" && (2..=3).contains(&fields.len()) =>
            {
                (fields[0], fields[1])
            }
            Object::Compiled(_, _) => {
                let f = state.arena.add(Object::Boolean(false))?;
                (self.root, f)
            }
            Object::Record(kind, _) if kind == "program" => {
                let f = state.arena.add(Object::Boolean(false))?;
                (self.root, f)
            }
            _ => return Err(fail("program or evidence module required")),
        };
        state
            .engine
            .evidence_owners
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |n| {
                (n < 64).then_some(n + 1)
            })
            .map_err(|_| fail("evidence session owner limit"))?;
        let permit = SessionPermit(state.engine.evidence_owners.clone());
        let declaration = Admission::new(&state.arena, state.identity)?.program(program)?;
        let session = if let Object::Record(kind, fields) = state.arena.get(self.root)?
            && kind == "evidence"
            && fields.len() == 3
        {
            let admission = Admission::new(&state.arena, state.identity)?;
            let mut aliases = BTreeMap::new();
            for pair in state.arena.items(fields[2])? {
                let Object::Pair(label, handle) = state.arena.get(pair)? else {
                    return Err(fail("export binding pair required"));
                };
                if aliases
                    .insert(admission.name(*label)?, admission.name(*handle)?)
                    .is_some()
                {
                    return Err(fail("duplicate public export label"));
                }
            }
            state
                .engine
                .open_exported_program(declaration, aliases, limits)?
        } else {
            state.engine.open_source_program(declaration, limits)?
        };
        let pin = NEXT_PIN.fetch_add(1, Ordering::Relaxed);
        let retained = state.arena.add(Object::Record(
            "session-roots".into(),
            vec![self.root, explainer],
        ))?;
        state.pins.insert(pin, retained);
        Ok(Evidence(Arc::new(Inner {
            permit: Mutex::new(Some(permit)),
            module: self.owner.clone(),
            pin,
            program,
            constructor: self.root,
            source_roots: Mutex::new(BTreeMap::new()),
            explainer,
            session: Mutex::new(session),
            closed: AtomicBool::new(false),
        })))
    }
}
impl Evidence {
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.0.closed.load(Ordering::Acquire)
    }
    fn session(&self) -> Result<std::sync::MutexGuard<'_, SourceSession>> {
        self.0.check()?;
        self.0
            .session
            .lock()
            .map_err(|_| fail("evidence session lock poisoned"))
    }
    /// Immutable admitted declarations, including caller-tightened fact limits.
    /// # Errors
    /// Rejects closed owners.
    pub fn program(&self) -> Result<crate::Program> {
        Ok(self.session()?.program().clone())
    }
    /// # Errors
    /// Rejects closed owners.
    pub fn queries(&self) -> Result<Vec<String>> {
        Ok(self.session()?.queries().to_vec())
    }
    /// # Errors
    /// Rejects closed owners.
    pub fn fact_limits(&self) -> Result<FactLimits> {
        Ok(self.session()?.fact_limits())
    }
    /// # Errors
    /// Execution preserves the normal cancellation, resource and result admission rules.
    pub fn run(
        &self,
        queries: Option<&[String]>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<SourceObservation> {
        self.session()?.run(queries, limits, cancellation)
    }
    /// # Errors
    /// Rejects released, stale or unknown results.
    pub fn result(&self, handle: u64) -> Result<SourceResult> {
        self.session()?.result(handle)
    }
    /// Freeze arguments before transactional source replacement. Public module closure
    /// does not prevent scalar/compound inputs; public references still require live leases.
    /// # Errors
    /// Invalid rows and failed executions preserve the previous committed generation.
    pub fn replace(
        &self,
        sources: BTreeMap<String, Vec<Vec<ObjectInput>>>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<u64> {
        let mut session = self.session()?;
        for input in sources.values().flatten().flatten() {
            replacement::validate(input, &session, 0)?;
        }
        let mut retained = self
            .0
            .source_roots
            .lock()
            .map_err(|_| fail("source roots lock poisoned"))?;
        let mut roots = retained.clone();
        let (updates, prior, candidate) = {
            let mut state = self.0.module.lock()?;
            state.collect_if_needed();
            let snapshot = super::freeze::snapshot()?;
            let (updates, new_roots) = replacement::prepare(&mut state, sources, snapshot)?;
            roots.extend(new_roots);
            let mut keep = vec![self.0.constructor, self.0.explainer];
            keep.extend(roots.values().copied());
            let candidate = state
                .arena
                .add(Object::Record("session-roots".into(), keep))?;
            let prior = state.pins[&self.0.pin];
            let temporary = state.arena.add(Object::Record(
                "pending-roots".into(),
                vec![prior, candidate],
            ))?;
            state.pins.insert(self.0.pin, temporary);
            (updates, prior, candidate)
        };
        let outcome = session.replace(updates, limits, cancellation);
        let mut state = self.0.module.lock()?;
        if outcome.is_ok() {
            state.pins.insert(self.0.pin, candidate);
            *retained = roots;
        } else {
            state.pins.insert(self.0.pin, prior);
        }
        state.collect_if_needed();
        outcome
    }
    /// Invoke the declared explainer against this generation. Its output is recorded
    /// metadata, never promoted to a per-row proof by this interface.
    /// # Errors
    /// Rejects invalid results/queries, callback failure and owner limits.
    /// An absent explainer produces explicit unsupported metadata.
    pub fn explain(&self, handle: u64, query: &str) -> Result<Explanation> {
        let session = self.session()?;
        let result = session.result(handle)?;
        result.rows(query)?;
        let mut state = self.0.module.lock()?;
        let generation = result.generation()?;
        let authority = result.fork()?;
        let output = self.explanation_graph(&mut state, &session, &result, query);
        state.collect_if_needed();
        output.map(|graph| Explanation {
            owner: self.clone(),
            authority,
            graph,
            generation,
            released: AtomicBool::new(false),
        })
    }
    fn explanation_graph(
        &self,
        state: &mut super::owner::State,
        session: &SourceSession,
        result: &SourceResult,
        query: &str,
    ) -> Result<Arc<ObjectGraph>> {
        let query = state.arena.relation_name(result.resolve(query)?)?;
        let sources = session
            .program()
            .relations
            .as_slice()
            .iter()
            .filter(|r| r.source)
            .map(|r| {
                (
                    r.name.clone(),
                    result.relations().expect("live locked result")[&r.name].clone(),
                )
            })
            .collect::<Vec<_>>();
        let scope = state
            .arena
            .explanation_scope(result.generation()?, &sources)?;
        let observed = state.arena.solution(result.relations()?)?;
        let program = self.0.program;
        let engine = state.engine.clone();
        let root = if matches!(state.arena.get(self.0.explainer)?, Object::Boolean(false)) {
            state.arena.default_explanation(program, scope)?
        } else {
            Evaluation::new(&mut state.arena, &engine)
                .invoke(self.0.explainer, &[program, observed, query, scope])?
                .0
        };
        engine.check()?;
        state.arena.graph(root).map(Arc::new)
    }
    /// Independently replay positive rules and enumerate all finite grounded alternatives.
    /// # Errors
    /// Stale results, invalid limits and cancellation fail closed; unsupported bodies
    /// publish an explicit empty unsupported observation.
    pub fn provenance(
        &self,
        handle: u64,
        query: &str,
        limits: &crate::ProvenanceLimits,
        cancel: &Cancellation,
    ) -> Result<crate::Provenance> {
        let session = self.session()?;
        let result = session.result(handle)?;
        crate::Provenance::generate(session.program().clone(), &result, query, limits, cancel)
    }
    pub fn close(&self) {
        if !self.0.closed.swap(true, Ordering::AcqRel) {
            if let Ok(mut session) = self.0.session.lock() {
                session.close();
            }
            self.0.unpin();
            if let Ok(mut permit) = self.0.permit.lock() {
                permit.take();
            }
        }
    }
}
/// Independently releasable recorded explanation, scoped to the session/engine.
pub struct Explanation {
    owner: Evidence,
    authority: SourceResult,
    graph: Arc<ObjectGraph>,
    generation: u64,
    released: AtomicBool,
}
impl Explanation {
    /// # Errors
    /// Result release does not revoke this observation; explanation/session release does.
    pub fn graph(&self) -> Result<Arc<ObjectGraph>> {
        self.owner.0.check()?;
        if self.released.load(Ordering::Acquire) {
            return Err(Error::Closed);
        }
        Ok(self.graph.clone())
    }
    #[must_use]
    pub fn source_generation(&self) -> u64 {
        self.generation
    }
    #[must_use]
    pub fn is_current(&self) -> bool {
        !self.released.load(Ordering::Acquire)
            && self.owner.0.check().is_ok()
            && self.authority.generation().is_ok()
    }
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.released.load(Ordering::Acquire)
    }
    pub fn close(&self) {
        self.released.store(true, Ordering::Release);
        self.authority.close();
    }
}
impl Drop for Explanation {
    fn drop(&mut self) {
        self.close();
    }
}
