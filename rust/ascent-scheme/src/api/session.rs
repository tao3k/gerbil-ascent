//! Scheme inference and generation-scoped result authority.
use super::{Engine, check, id, input};
use gerbil_ascent::{
    Cancellation, Data, Error, FactLimits, Limits, ObjectInput, Program, Relation, Result, Type,
};
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex, Weak,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};

pub(super) struct State {
    engine: Engine,
    handle: u64,
    metadata: Data,
    identity: u64,
    generation: AtomicU64,
    closed: AtomicBool,
    gate: Mutex<()>,
    proofs: Mutex<Vec<Weak<Mutex<Option<gerbil_ascent::SourceSession>>>>>,
    results: Mutex<BTreeMap<u64, Weak<ResultState>>>,
}
impl State {
    fn check(&self) -> Result<()> {
        check(&self.engine, self.closed.load(Ordering::Acquire))
    }
    pub(super) fn close(&self) {
        if !self.closed.swap(true, Ordering::AcqRel) {
            if let Ok(mut proofs) = self.proofs.lock() {
                for proof in proofs.iter().filter_map(Weak::upgrade) {
                    if let Ok(mut session) = proof.lock()
                        && let Some(mut session) = session.take()
                    {
                        session.close();
                    }
                }
                proofs.clear();
            }
            let _ = self
                .engine
                .invoke_unchecked("close", [("handle", Data::from(self.handle))]);
        }
    }
}
impl Drop for State {
    fn drop(&mut self) {
        self.close();
    }
}
/// Scheme session with one owner-serialized operation stream.
#[derive(Clone)]
pub struct RuleSession(Arc<State>);
impl RuleSession {
    pub(super) fn new(engine: &Engine, metadata: Data) -> Result<Self> {
        let owner = Self(Arc::new(State {
            engine: engine.clone(),
            handle: id(&metadata, "handle")?,
            metadata,
            identity: gerbil_ascent::allocate_source_identity()?,
            generation: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            gate: Mutex::new(()),
            proofs: Mutex::new(Vec::new()),
            results: Mutex::new(BTreeMap::new()),
        }));
        engine.track_session(&owner.0)?;
        Ok(owner)
    }
    fn acquire(&self, control: &crate::control::Control) -> Result<std::sync::MutexGuard<'_, ()>> {
        loop {
            control.check()?;
            match self.0.gate.try_lock() {
                Ok(guard) => return Ok(guard),
                Err(std::sync::TryLockError::Poisoned(_)) => return Err(Error::Closed),
                Err(std::sync::TryLockError::WouldBlock) => {
                    std::thread::park_timeout(std::time::Duration::from_millis(1));
                }
            }
        }
    }
    pub(super) fn check(&self) -> Result<()> {
        self.0.check()
    }
    fn current_generation(&self) -> Result<u64> {
        self.check()?;
        let response = self
            .0
            .engine
            .invoke("source-status", [("handle", Data::from(self.0.handle))])?;
        id(&response, "sourceGeneration")
    }
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.0.closed.load(Ordering::Acquire) || self.0.engine.is_closed()
    }
    /// Scheme export projection; unsupported callback semantics stay in Scheme.
    /// # Errors
    /// Rejects closed owners.
    pub fn projection(&self) -> Result<Data> {
        self.check()?;
        Ok(self.0.metadata.field("projection")?.clone())
    }
    /// Original native relation descriptors.
    /// # Errors
    /// Rejects closed owners.
    pub fn descriptors(&self) -> Result<Data> {
        self.check()?;
        Ok(self.0.metadata.field("descriptors")?.clone())
    }
    /// Exposed query names.
    /// # Errors
    /// Rejects closed owners.
    pub fn queries(&self) -> Result<Vec<String>> {
        self.check()?;
        self.0
            .metadata
            .field("queries")?
            .list()?
            .iter()
            .map(|v| v.text().map(str::to_string))
            .collect()
    }
    /// Effective native fact ceilings, preserving infinity as no ceiling.
    /// # Errors
    /// Rejects closed owners or invalid native metadata.
    pub fn fact_limits(&self) -> Result<FactLimits> {
        self.check()?;
        let limit = |name| -> Result<Option<usize>> {
            let v = self.0.metadata.field("factLimits")?.field(name)?;
            if v == &Data::from("unlimited") {
                Ok(None)
            } else {
                Ok(Some(v.index()?))
            }
        };
        Ok(FactLimits {
            input: limit("input")?,
            derived: limit("derived")?,
            output: limit("output")?,
        })
    }
    fn finite_program(&self) -> Result<Option<Program>> {
        let projection = self
            .0
            .engine
            .invoke("source-projection", [("handle", Data::from(self.0.handle))])?;
        if projection.field("status")?.text()? != "supported" {
            return Ok(None);
        }
        gerbil_ascent::Catalog::read(projection.field("program")?)
            .map(|catalog| Some(catalog.program))
    }
    /// Schema-only observation for typed clients; execution remains native.
    /// # Errors
    /// Rejects closed owners or invalid descriptors.
    pub fn program(&self) -> Result<Program> {
        let mut program = Program {
            fact_limits: self.fact_limits()?,
            ..Program::default()
        };
        for d in self.descriptors()?.list()? {
            let columns = d
                .field("columns")?
                .list()?
                .iter()
                .map(|c| match c.field("kind")?.text()? {
                    "integer" => Ok(Type::Integer),
                    "symbol" => Ok(Type::Symbol),
                    "boolean" => Ok(Type::Boolean),
                    "string" => Ok(Type::Text),
                    _ => Ok(Type::Any),
                })
                .collect::<Result<Vec<_>>>()?;
            program.relations.push(Relation::new(
                d.field("name")?.text()?,
                columns,
                d.field("source")?.boolean()?,
            ));
        }
        Ok(program)
    }
    /// Execute the original native Scheme session and return owned observations.
    /// # Errors
    /// Rejects cancellation, timeout, invalid queries and native resource failures.
    pub fn run(
        &self,
        queries: Option<&[String]>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<Data> {
        let control = crate::control::Control::new(limits, cancellation)?;
        let _gate = self.acquire(&control)?;
        self.check()?;
        if limits.max_states != usize::MAX || limits.max_facts != usize::MAX {
            let program = self.finite_program()?.ok_or_else(|| {
                crate::failure("native callback execution cannot admit finite Rust work ceilings")
            })?;
            let mut admitted = self.0.engine.open(program)?;
            admitted.run(limits, cancellation)?;
        }
        let queries = queries.map_or_else(|| self.queries(), |v| Ok(v.to_vec()))?;
        let duration = u64::try_from(limits.timeout.as_nanos()).map_err(|_| Error::Timeout)?;
        control.check()?;
        let result = self.0.engine.invoke(
            "source-run",
            [
                ("handle", Data::from(self.0.handle)),
                ("executionControl", control.id()),
                (
                    "queries",
                    Data::List(queries.into_iter().map(Data::from).collect()),
                ),
                (
                    "timeoutNanoseconds",
                    Data::from(duration.min(1_000_000_000)),
                ),
            ],
        )?;
        self.check()?;
        let handle = id(&result, "resultHandle")?;
        if !result.field("complete")?.boolean()? {
            let _ = self.release(handle);
            return Err(Error::Timeout);
        }
        if let Err(error) = control.check() {
            let _ = self.release(handle);
            return Err(error);
        }
        Ok(result)
    }
    /// Validate a retained result against this owner and committed generation.
    /// # Errors
    /// Rejects invalid handles and revoked sessions.
    pub fn result(&self, handle: u64) -> Result<RuleResult> {
        self.check()?;
        if handle == 0 {
            return Err(crate::failure("invalid result handle"));
        }
        let admitted = self.0.engine.invoke_unchecked(
            "owned-result",
            [
                ("handle", Data::from(self.0.handle)),
                ("result", Data::from(handle)),
                ("action", Data::from("check")),
            ],
        )?;
        let mut results = self.0.results.lock().map_err(|_| Error::Closed)?;
        if let Some(result) = results.get(&handle).and_then(Weak::upgrade) {
            let result = RuleResult(result);
            result.check()?;
            return Ok(result);
        }
        results.retain(|_, value| value.strong_count() > 0);
        let result = Arc::new(ResultState {
            owner: self.clone(),
            handle,
            generation: id(&admitted, "sourceGeneration")?,
            closed: AtomicBool::new(false),
        });
        results.insert(handle, Arc::downgrade(&result));
        Ok(RuleResult(result))
    }
    /// Replace native sources transactionally using their retained native values.
    /// # Errors
    /// Scheme type/resource failures preserve the previously committed generation.
    pub fn replace(
        &self,
        sources: BTreeMap<String, Vec<Vec<ObjectInput>>>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<u64> {
        let control = crate::control::Control::new(limits, cancellation)?;
        let _gate = self.acquire(&control)?;
        self.check()?;
        self.admit_replacement(&sources, limits, cancellation)?;
        let sources = Self::source_payload(sources, &control)?;
        control.check()?;
        let result = self.0.engine.invoke(
            "source-replace",
            [
                ("handle", Data::from(self.0.handle)),
                ("sources", Data::List(sources)),
                ("executionControl", control.id()),
            ],
        )?;
        self.publish_generation(&result)
    }
    fn admit_replacement(
        &self,
        sources: &BTreeMap<String, Vec<Vec<ObjectInput>>>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<()> {
        if limits.max_states == usize::MAX && limits.max_facts == usize::MAX {
            return Ok(());
        }
        let mut program = self.finite_program()?.ok_or_else(|| {
            crate::failure("native callback replacement cannot admit finite Rust work ceilings")
        })?;
        let descriptors = self.descriptors()?;
        let indexes = descriptors
            .list()?
            .iter()
            .enumerate()
            .map(|(index, descriptor)| Ok((descriptor.field("name")?.text()?.to_string(), index)))
            .collect::<Result<BTreeMap<_, _>>>()?;
        for (label, rows) in sources {
            let index = *indexes
                .get(label)
                .ok_or_else(|| crate::failure("unknown source"))?;
            let relation = program
                .relations
                .get_mut(index)
                .ok_or_else(|| crate::failure("source descriptor"))?;
            relation.rows = rows
                .iter()
                .map(|row| owned_row(row, &relation.columns))
                .collect::<Result<_>>()?;
        }
        self.0
            .engine
            .open(program)?
            .run(limits, cancellation)
            .map(|_| ())
    }
    fn source_payload(
        sources: BTreeMap<String, Vec<Vec<ObjectInput>>>,
        control: &crate::control::Control,
    ) -> Result<Vec<Data>> {
        sources
            .into_iter()
            .map(|(name, rows)| {
                let rows = rows
                    .iter()
                    .map(|row| {
                        control.check()?;
                        input::source_arguments(row)
                    })
                    .collect::<Result<_>>()?;
                Ok(Data::object([
                    ("relation", Data::from(name)),
                    ("rows", Data::List(rows)),
                ]))
            })
            .collect()
    }
    fn publish_generation(&self, result: &Data) -> Result<u64> {
        self.check()?;
        for proof in self
            .0
            .proofs
            .lock()
            .map_err(|_| Error::Closed)?
            .iter()
            .filter_map(Weak::upgrade)
        {
            if let Some(mut session) = proof.lock().map_err(|_| Error::Closed)?.take() {
                session.close();
            }
        }
        self.0.proofs.lock().map_err(|_| Error::Closed)?.clear();
        let generation = id(result, "sourceGeneration")?;
        self.0.generation.store(generation, Ordering::Release);
        Ok(generation)
    }
    fn release(&self, handle: u64) -> Result<()> {
        self.0
            .engine
            .invoke_unchecked(
                "owned-result",
                [
                    ("handle", Data::from(self.0.handle)),
                    ("result", Data::from(handle)),
                    ("action", Data::from("release")),
                ],
            )
            .map(|_| ())
    }
    /// Capture the native explainer result independently of the source result lease.
    /// # Errors
    /// Rejects stale results and invalid query names.
    pub fn explain(&self, handle: u64, query: &str) -> Result<Explanation> {
        self.check()?;
        let value = self.0.engine.invoke_unchecked(
            "owned-result",
            [
                ("handle", Data::from(self.0.handle)),
                ("result", Data::from(handle)),
                ("action", Data::from("explain")),
                ("relation", Data::from(query)),
            ],
        )?;
        Ok(Explanation {
            owner: self.clone(),
            handle: id(&value, "explanationHandle")?,
            generation: id(&value, "sourceGeneration")?,
            graph: Arc::new(value.field("value")?.clone()),
            closed: AtomicBool::new(false),
        })
    }
    /// Independently replay and check the complete native answer before publishing a proof.
    /// # Errors
    /// Rejects stale scopes, invalid bounds and failed or exhausted independent replay.
    pub fn provenance(
        &self,
        handle: u64,
        query: &str,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancellation: &Cancellation,
    ) -> Result<SchemeProvenance> {
        let control = crate::control::Control::new(
            &Limits {
                timeout: limits.timeout,
                max_states: usize::MAX,
                max_facts: usize::MAX,
            },
            cancellation,
        )?;
        let _gate = self.acquire(&control)?;
        let generation = self.admit_proof_scope(handle, query, limits, cancellation, &control)?;
        let program = self.proof_program(&control)?;
        let Some((program, fingerprint)) = program else {
            control.check()?;
            return self.unsupported_provenance(generation, query, cancellation);
        };
        let rows = self.proof_rows(handle, query, &control)?;
        let (proof, session) =
            self.replay_proof(program, &rows, query, limits, cancellation, &control)?;
        if self.admit_proof_scope(handle, query, limits, cancellation, &control)? != generation {
            return Err(Error::Closed);
        }
        let retained = self.retain_proof(proof, session, generation, fingerprint)?;
        retained.check_controlled(&control)?;
        Ok(retained)
    }
    fn admit_proof_scope(
        &self,
        handle: u64,
        query: &str,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancellation: &Cancellation,
        control: &crate::control::Control,
    ) -> Result<u64> {
        let scope = self.0.engine.invoke(
            "owned-result",
            [
                ("handle", Data::from(self.0.handle)),
                ("executionControl", control.id()),
                ("result", Data::from(handle)),
                ("action", Data::from("proof-scope")),
                ("relation", Data::from(query)),
            ],
        )?;
        if limits.max_steps == 0
            || limits.max_nodes == 0
            || limits.max_nodes > 4096
            || limits.max_edges == 0
            || limits.max_edges > 65_536
        {
            return Err(Error::InvalidUpdate("invalid provenance limits".into()));
        }
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        id(&scope, "sourceGeneration")
    }
    fn retain_proof(
        &self,
        proof: gerbil_ascent::Provenance,
        session: gerbil_ascent::SourceSession,
        generation: u64,
        fingerprint: String,
    ) -> Result<SchemeProvenance> {
        let session = Arc::new(Mutex::new(Some(session)));
        let mut proofs = self.0.proofs.lock().map_err(|_| Error::Closed)?;
        proofs.retain(|scope| {
            scope
                .upgrade()
                .is_some_and(|s| s.lock().is_ok_and(|s| s.is_some()))
        });
        proofs.push(Arc::downgrade(&session));
        Ok(SchemeProvenance {
            owner: self.clone(),
            generation,
            proof: Some(proof),
            fingerprint: Some(fingerprint),
            unsupported: None,
            session: Some(session),
            closed: AtomicBool::new(false),
        })
    }
    fn replay_proof(
        &self,
        program: Program,
        rows: &[gerbil_ascent::Row],
        query: &str,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancellation: &Cancellation,
        control: &crate::control::Control,
    ) -> Result<(gerbil_ascent::Provenance, gerbil_ascent::SourceSession)> {
        let descriptors = self.descriptors()?;
        if descriptors.list()?.len() != program.relations.len() {
            return Err(crate::failure("native descriptor count mismatch"));
        }
        let aliases = descriptors
            .list()?
            .iter()
            .zip(&program.relations)
            .map(|(d, r)| Ok((d.field("name")?.text()?.into(), r.name.clone())))
            .collect::<Result<BTreeMap<_, _>>>()?;
        let mut session =
            self.0
                .engine
                .open_exported_program(program, aliases, self.fact_limits()?)?;
        let run_limits = Limits {
            timeout: control.remaining()?,
            ..Limits::default()
        };
        let receipt = session.run(Some(&[query.into()]), &run_limits, cancellation)?;
        let replay = session.result(receipt.result_handle)?;
        let mut actual = rows.to_vec();
        let mut checked = replay.rows(query)?.to_vec();
        actual.sort();
        checked.sort();
        if actual != checked {
            session.close();
            return Err(crate::failure(
                "native result disagrees with checked provenance replay",
            ));
        }
        let remaining_limits = gerbil_ascent::ProvenanceLimits {
            timeout: control.remaining()?,
            ..limits.clone()
        };
        let proof = session.provenance(
            receipt.result_handle,
            query,
            &remaining_limits,
            cancellation,
        )?;
        control.check()?;
        Ok((proof, session))
    }
    fn proof_program(
        &self,
        control: &crate::control::Control,
    ) -> Result<Option<(Program, String)>> {
        let projection = self.current_projection(control)?;
        if projection.field("status")?.text()? != "supported" {
            return Ok(None);
        }
        let program = gerbil_ascent::Catalog::read(projection.field("program")?)?.program;
        Ok(Some((program, projection.digest())))
    }
    fn current_status(&self, control: &crate::control::Control) -> Result<Data> {
        self.0.engine.invoke(
            "source-status",
            [
                ("handle", Data::from(self.0.handle)),
                ("executionControl", control.id()),
            ],
        )
    }
    fn current_projection(&self, control: &crate::control::Control) -> Result<Data> {
        self.0.engine.invoke(
            "source-projection",
            [
                ("handle", Data::from(self.0.handle)),
                ("executionControl", control.id()),
            ],
        )
    }
    fn proof_rows(
        &self,
        handle: u64,
        query: &str,
        control: &crate::control::Control,
    ) -> Result<Vec<gerbil_ascent::Row>> {
        let native = self.0.engine.invoke(
            "owned-result",
            [
                ("handle", Data::from(self.0.handle)),
                ("executionControl", control.id()),
                ("result", Data::from(handle)),
                ("action", Data::from("scalar-rows")),
                ("relation", Data::from(query)),
            ],
        )?;
        let rows = native
            .list()?
            .iter()
            .map(|row| {
                row.list()?
                    .iter()
                    .map(|cell| {
                        let value = cell.field("value")?;
                        match cell.field("kind")?.text()? {
                            "symbol" => Ok(gerbil_ascent::Value::Symbol(value.text()?.into())),
                            "string" => Ok(gerbil_ascent::Value::Text(value.text()?.into())),
                            "integer" => match value {
                                Data::Integer(v) => Ok(gerbil_ascent::Value::Integer(v.clone())),
                                _ => Err(crate::failure("native integer projection")),
                            },
                            "number" => gerbil_ascent::Value::number(value.text()?),
                            "graph" => gerbil_ascent::FrozenValue::new(
                                0,
                                0,
                                gerbil_ascent::ObjectGraph::read_scheme(value)?,
                            )
                            .map(gerbil_ascent::Value::Object),
                            "boolean" => Ok(gerbil_ascent::Value::Boolean(value.boolean()?)),
                            _ => Err(crate::failure("unsupported native proof value")),
                        }
                    })
                    .collect::<Result<Vec<_>>>()
                    .map(gerbil_ascent::Row::from)
            })
            .collect::<Result<Vec<_>>>()?;
        Ok(rows)
    }
    fn unsupported_provenance(
        &self,
        generation: u64,
        query: &str,
        cancel: &Cancellation,
    ) -> Result<SchemeProvenance> {
        if cancel.is_canceled() {
            return Err(Error::Canceled);
        }
        Ok(SchemeProvenance {
            owner: self.clone(),
            generation,
            proof: None,
            fingerprint: None,
            session: None,
            unsupported: Some(Arc::new(gerbil_ascent::ProvenanceGraph {
                status: gerbil_ascent::ProvenanceStatus::Unsupported,
                checker_version: 3,
                source_identity: self.0.identity,
                generation,
                query: query.into(),
                nodes: vec![],
                edges: vec![],
                roots: vec![],
            })),
            closed: AtomicBool::new(false),
        })
    }
    /// Close the native session; all generation-bound values become unusable.
    pub fn close(&self) {
        self.0.close();
    }
}
struct ResultState {
    owner: RuleSession,
    handle: u64,
    generation: u64,
    closed: AtomicBool,
}
impl Drop for ResultState {
    fn drop(&mut self) {
        if !self.closed.swap(true, Ordering::AcqRel) {
            let _ = self.owner.release(self.handle);
        }
    }
}
/// Generation-bound native result lease.
#[derive(Clone)]
pub struct RuleResult(Arc<ResultState>);
impl RuleResult {
    /// Whether this lease was explicitly released.
    #[must_use]
    pub fn is_released(&self) -> bool {
        self.0.closed.load(Ordering::Acquire)
    }
    /// Retain native cell authority with generation and result lifetime checks.
    /// # Errors
    /// Rejects revoked or out-of-range cells.
    pub fn value(&self, relation: &str, row: usize, column: usize) -> Result<super::ResultValue> {
        let value = super::ResultValue {
            result: self.clone(),
            relation: relation.into(),
            row,
            column,
        };
        value.input()?;
        Ok(value)
    }
    fn check(&self) -> Result<()> {
        self.0.owner.check()?;
        if self.0.closed.load(Ordering::Acquire)
            || self.0.generation != self.0.owner.0.generation.load(Ordering::Acquire)
        {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
    /// Scheme graph observation of one result relation.
    /// # Errors
    /// Rejects stale, released or unknown results/relations.
    pub fn rows(&self, relation: &str) -> Result<Data> {
        self.check()?;
        self.0.owner.0.engine.invoke_unchecked(
            "owned-result",
            [
                ("handle", Data::from(self.0.owner.0.handle)),
                ("result", Data::from(self.0.handle)),
                ("action", Data::from("rows")),
                ("relation", Data::from(relation)),
            ],
        )
    }
    pub(super) fn reference(
        &self,
        relation: &str,
        row: usize,
        column: usize,
    ) -> Result<ObjectInput> {
        self.check()?;
        let value = self.0.owner.0.engine.invoke(
            "owned-result",
            [
                ("handle", Data::from(self.0.owner.0.handle)),
                ("result", Data::from(self.0.handle)),
                ("action", Data::from("reference")),
                ("relation", Data::from(relation)),
                ("row", Data::from(row)),
                ("column", Data::from(column)),
            ],
        )?;
        Ok(ObjectInput::SourceReference {
            owner: self.0.owner.0.handle,
            generation: id(&value, "sourceGeneration")?,
            result: self.0.handle,
            node: value.field("node")?.index()?,
        })
    }
    /// Committed source generation.
    /// # Errors
    /// Rejects revoked authority.
    pub fn generation(&self) -> Result<u64> {
        self.check()?;
        Ok(self.0.generation)
    }
    /// Release only this result, keeping the inference session alive.
    pub fn close(&self) {
        if !self.0.closed.swap(true, Ordering::AcqRel) {
            let _ = self.0.owner.release(self.0.handle);
        }
    }
}
/// Independent recorded explanation, retaining its original generation metadata.
pub struct Explanation {
    owner: RuleSession,
    handle: u64,
    generation: u64,
    graph: Arc<Data>,
    closed: AtomicBool,
}
impl Explanation {
    /// Read the immutable native observation, even after source replacement.
    /// # Errors
    /// Rejects explicit explanation/session/engine closure.
    pub fn graph(&self) -> Result<Arc<Data>> {
        self.owner.check()?;
        if self.closed.load(Ordering::Acquire) {
            Err(Error::Closed)
        } else {
            Ok(self.graph.clone())
        }
    }
    #[must_use]
    pub fn source_generation(&self) -> u64 {
        self.generation
    }
    #[must_use]
    pub fn is_current(&self) -> bool {
        !self.is_closed()
            && self.owner.check().is_ok()
            && self
                .owner
                .current_generation()
                .is_ok_and(|generation| self.generation == generation)
    }
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Acquire)
    }
    /// Release native explanation state.
    pub fn close(&self) {
        if !self.closed.swap(true, Ordering::AcqRel) {
            let _ = self.owner.release(self.handle);
        }
    }
}
impl Drop for Explanation {
    fn drop(&mut self) {
        self.close();
    }
}

/// Checked derivation bound to native source authority, independent of the source result lease.
pub struct SchemeProvenance {
    owner: RuleSession,
    generation: u64,
    proof: Option<gerbil_ascent::Provenance>,
    fingerprint: Option<String>,
    unsupported: Option<Arc<gerbil_ascent::ProvenanceGraph>>,
    session: Option<Arc<Mutex<Option<gerbil_ascent::SourceSession>>>>,
    closed: AtomicBool,
}
impl SchemeProvenance {
    fn check(&self) -> Result<()> {
        let control = crate::control::Control::new(&Limits::default(), &Cancellation::default())?;
        self.check_controlled(&control)
    }
    fn check_controlled(&self, control: &crate::control::Control) -> Result<()> {
        self.owner.check()?;
        if self.closed.load(Ordering::Acquire) {
            return Err(Error::Closed);
        }
        // BEGIN GENERATED PROOF AUTHORITY READ
        let status = if self.fingerprint.is_some() {
            self.owner.current_projection(control)?
        } else {
            self.owner.current_status(control)?
        };
        // END GENERATED PROOF AUTHORITY READ
        if id(&status, "sourceGeneration")? != self.generation {
            return Err(Error::Closed);
        }
        if self
            .fingerprint
            .as_ref()
            .is_some_and(|expected| *expected != status.digest())
        {
            return Err(Error::Closed);
        }
        control.check()
    }
    /// # Errors
    /// Rejects released proofs or changed source authority.
    pub fn graph(&self) -> Result<Arc<gerbil_ascent::ProvenanceGraph>> {
        self.check()?;
        if let Some(graph) = &self.unsupported {
            return Ok(graph.clone());
        }
        let mut graph = (*self.proof.as_ref().ok_or(Error::Closed)?.graph()?).clone();
        graph.source_identity = self.owner.0.identity;
        graph.generation = self.generation;
        Ok(Arc::new(graph))
    }
    /// # Errors
    /// Rejects revoked source authority, cancellation and exhausted verification bounds.
    pub fn verify(
        &self,
        candidate: &gerbil_ascent::ProvenanceGraph,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancel: &Cancellation,
    ) -> Result<bool> {
        let control = crate::control::Control::new(
            &Limits {
                timeout: limits.timeout,
                max_states: usize::MAX,
                max_facts: usize::MAX,
            },
            cancel,
        )?;
        let _gate = self.owner.acquire(&control)?;
        self.check_controlled(&control)?;
        if candidate.source_identity != self.owner.0.identity
            || candidate.generation != self.generation
        {
            return Ok(false);
        }
        if cancel.is_canceled() {
            return Err(Error::Canceled);
        }
        let valid = self.verify_replay(candidate, limits, cancel, &control)?;
        self.check_controlled(&control)?;
        Ok(valid)
    }
    fn verify_replay(
        &self,
        candidate: &gerbil_ascent::ProvenanceGraph,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancel: &Cancellation,
        control: &crate::control::Control,
    ) -> Result<bool> {
        let Some(proof) = &self.proof else {
            return Ok(false);
        };
        let inner = proof.graph()?;
        let mut mapped = candidate.clone();
        mapped.source_identity = inner.source_identity;
        mapped.generation = inner.generation;
        let remaining_limits = gerbil_ascent::ProvenanceLimits {
            timeout: control.remaining()?,
            ..limits.clone()
        };
        proof.verify(&mapped, &remaining_limits, cancel)
    }
    pub fn close(&self) {
        if self.closed.swap(true, Ordering::AcqRel) {
            return;
        }
        if let Some(proof) = &self.proof {
            proof.close();
        }
        self.close_replay();
    }
    fn close_replay(&self) {
        let Some(scope) = &self.session else {
            return;
        };
        let Ok(mut session) = scope.lock() else {
            return;
        };
        if let Some(mut session) = session.take() {
            session.close();
        }
    }
}

impl Drop for SchemeProvenance {
    fn drop(&mut self) {
        self.close();
    }
}

fn owned_row(row: &[ObjectInput], columns: &[Type]) -> Result<gerbil_ascent::Row> {
    if row.len() != columns.len() {
        return Err(crate::failure("invalid source row width"));
    }
    row.iter()
        .zip(columns)
        .map(|(value, ty)| input::owned(value, *ty))
        .collect::<Result<Vec<_>>>()
        .map(Into::into)
}

#[cfg(test)]
#[path = "../../tests/unit/proof_authority.rs"]
mod proof_authority_tests;
