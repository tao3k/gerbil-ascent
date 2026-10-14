//! Native inference and generation-scoped result authority.
use super::{Engine, check, id, input, invoke};
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

struct State {
    engine: Engine,
    handle: u64,
    metadata: Data,
    generation: AtomicU64,
    closed: AtomicBool,
    gate: Mutex<()>,
    finite: Mutex<Option<Program>>,
    proofs: Mutex<Vec<gerbil_ascent::SourceSession>>,
    results: Mutex<BTreeMap<u64, Weak<ResultState>>>,
}
impl State {
    fn check(&self) -> Result<()> {
        check(&self.engine, self.closed.load(Ordering::Acquire))
    }
    fn close(&self) {
        if !self.closed.swap(true, Ordering::AcqRel) {
            let _ = invoke("close", [("handle", Data::from(self.handle))]);
        }
    }
}
impl Drop for State {
    fn drop(&mut self) {
        self.close();
    }
}
/// Native session with one owner-serialized operation stream.
#[derive(Clone)]
pub struct Evidence(Arc<State>);
impl Evidence {
    pub(super) fn new(engine: &Engine, metadata: Data) -> Result<Self> {
        let finite = metadata
            .field("projection")?
            .get("program")
            .map(gerbil_ascent::Catalog::read)
            .transpose()?
            .map(|c| c.program);
        let owner = Self(Arc::new(State {
            engine: engine.clone(),
            handle: id(&metadata, "handle")?,
            metadata,
            generation: AtomicU64::new(0),
            closed: AtomicBool::new(false),
            gate: Mutex::new(()),
            finite: Mutex::new(finite),
            proofs: Mutex::new(Vec::new()),
            results: Mutex::new(BTreeMap::new()),
        }));
        // Native batch replacement requires a clean initial session. Admission
        // completes this empty-query snapshot before exposing the public owner.
        let initial = owner.run(
            Some(&[]),
            &gerbil_ascent::SourceSession::default_limits(),
            &Cancellation::default(),
        )?;
        owner.result(id(&initial, "resultHandle")?)?.close();
        Ok(owner)
    }
    pub(super) fn check(&self) -> Result<()> {
        self.0.check()
    }
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.0.closed.load(Ordering::Acquire) || self.0.engine.is_closed()
    }
    /// Native export projection; unsupported callback semantics stay in Scheme.
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
    /// Schema-only observation for typed clients; execution remains native.
    /// # Errors
    /// Rejects closed owners or invalid descriptors.
    pub fn program(&self) -> Result<Program> {
        let mut program = Program::default();
        program.fact_limits = self.fact_limits()?;
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
        let _gate = self.0.gate.lock().map_err(|_| Error::Closed)?;
        self.check()?;
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        if limits.max_states != usize::MAX || limits.max_facts != usize::MAX {
            let finite = self.0.finite.lock().map_err(|_| Error::Closed)?;
            let program = finite.as_ref().ok_or_else(|| {
                crate::failure("native callback execution cannot admit finite Rust work ceilings")
            })?;
            let mut admitted = self.0.engine.open(program.clone())?;
            admitted.run(limits, cancellation)?;
        }
        let queries = queries.map_or_else(|| self.queries(), |v| Ok(v.to_vec()))?;
        let duration = u64::try_from(limits.timeout.as_nanos()).map_err(|_| Error::Timeout)?;
        let result = invoke(
            "source-run",
            [
                ("handle", Data::from(self.0.handle)),
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
        let handle = id(&result, "resultHandle")?;
        if cancellation.is_canceled() || !result.field("complete")?.boolean()? {
            let _ = self.release(handle);
            return Err(if cancellation.is_canceled() {
                Error::Canceled
            } else {
                Error::Timeout
            });
        }
        Ok(result)
    }
    /// Validate a retained result against this owner and committed generation.
    /// # Errors
    /// Rejects invalid handles and revoked sessions.
    pub fn result(&self, handle: u64) -> Result<EvidenceResult> {
        self.check()?;
        if handle == 0 {
            return Err(crate::failure("invalid result handle"));
        }
        let admitted = invoke(
            "native-result",
            [
                ("handle", Data::from(self.0.handle)),
                ("result", Data::from(handle)),
                ("action", Data::from("check")),
            ],
        )?;
        let mut results = self.0.results.lock().map_err(|_| Error::Closed)?;
        if let Some(result) = results.get(&handle).and_then(Weak::upgrade) {
            let result = EvidenceResult(result);
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
        Ok(EvidenceResult(result))
    }
    /// Replace native sources transactionally using their retained native values.
    /// # Errors
    /// Native type/resource failures preserve the previously committed generation.
    pub fn replace(
        &self,
        sources: BTreeMap<String, Vec<Vec<ObjectInput>>>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<u64> {
        let _gate = self.0.gate.lock().map_err(|_| Error::Closed)?;
        self.check()?;
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        let mut finite = self.0.finite.lock().map_err(|_| Error::Closed)?;
        let mut candidate = finite.clone();
        if let Some(program) = candidate.as_mut() {
            let descriptors = self.descriptors()?;
            for (label, rows) in &sources {
                let index = descriptors
                    .list()?
                    .iter()
                    .position(|d| d.field("name").and_then(Data::text) == Ok(label))
                    .ok_or_else(|| crate::failure("unknown source"))?;
                let relation = program
                    .relations
                    .get_mut(index)
                    .ok_or_else(|| crate::failure("source descriptor"))?;
                relation.rows = rows
                    .iter()
                    .map(|row| {
                        row.iter()
                            .zip(&relation.columns)
                            .map(|(v, ty)| input::owned(v, *ty))
                            .collect::<Result<Vec<_>>>()
                            .map(Into::into)
                    })
                    .collect::<Result<Vec<_>>>()?;
            }
            let mut checked = self.0.engine.open(program.clone())?;
            checked.run(limits, cancellation)?;
        }
        let sources = sources
            .into_iter()
            .map(|(name, rows)| {
                Ok(Data::object([
                    ("relation", Data::from(name)),
                    (
                        "rows",
                        Data::List(
                            rows.iter()
                                .map(|row| input::arguments(row, self.0.handle))
                                .collect::<Result<Vec<_>>>()?,
                        ),
                    ),
                ]))
            })
            .collect::<Result<Vec<_>>>()?;
        let result = invoke(
            "source-replace",
            [
                ("handle", Data::from(self.0.handle)),
                ("sources", Data::List(sources)),
            ],
        )?;
        *finite = candidate;
        for proof in self.0.proofs.lock().map_err(|_| Error::Closed)?.iter_mut() {
            proof.close();
        }
        self.0.proofs.lock().map_err(|_| Error::Closed)?.clear();
        let generation = id(&result, "sourceGeneration")?;
        self.0.generation.store(generation, Ordering::Release);
        Ok(generation)
    }
    fn release(&self, handle: u64) -> Result<()> {
        invoke(
            "native-result",
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
        let result = self.result(handle)?;
        result.check()?;
        let value = invoke(
            "native-result",
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
            generation: result.0.generation,
            graph: value.field("value")?.clone(),
            closed: AtomicBool::new(false),
        })
    }
    /// Replay a finite native result through the existing independent provenance checker.
    /// # Errors
    /// Rejects stale native results, unsupported projection and replay limits.
    pub fn provenance(
        &self,
        handle: u64,
        query: &str,
        limits: &gerbil_ascent::ProvenanceLimits,
        cancellation: &Cancellation,
    ) -> Result<gerbil_ascent::Provenance> {
        let result = self.result(handle)?;
        result.rows(query)?;
        let program = self
            .0
            .finite
            .lock()
            .map_err(|_| Error::Closed)?
            .clone()
            .ok_or_else(|| crate::failure("native program has no finite provenance projection"))?;
        let descriptors = self.descriptors()?;
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
        let receipt = session.run(Some(&[query.into()]), &Limits::default(), cancellation)?;
        let proof = session.provenance(receipt.result_handle, query, limits, cancellation)?;
        self.0
            .proofs
            .lock()
            .map_err(|_| Error::Closed)?
            .push(session);
        Ok(proof)
    }
    /// Close the native session; all generation-bound values become unusable.
    pub fn close(&self) {
        self.0.close();
    }
}
struct ResultState {
    owner: Evidence,
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
pub struct EvidenceResult(Arc<ResultState>);
impl EvidenceResult {
    /// Whether this lease was explicitly released.
    #[must_use]
    pub fn is_released(&self) -> bool {
        self.0.closed.load(Ordering::Acquire)
    }
    pub(super) fn owner_id(&self) -> u64 {
        self.0.owner.0.handle
    }
    pub(super) fn handle(&self) -> u64 {
        self.0.handle
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
    /// Native graph observation of one result relation.
    /// # Errors
    /// Rejects stale, released or unknown results/relations.
    pub fn rows(&self, relation: &str) -> Result<Data> {
        self.check()?;
        invoke(
            "native-result",
            [
                ("handle", Data::from(self.0.owner.0.handle)),
                ("result", Data::from(self.0.handle)),
                ("action", Data::from("rows")),
                ("relation", Data::from(relation)),
            ],
        )
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
    owner: Evidence,
    handle: u64,
    generation: u64,
    graph: Data,
    closed: AtomicBool,
}
impl Explanation {
    /// Read the immutable native observation, even after source replacement.
    /// # Errors
    /// Rejects explicit explanation/session/engine closure.
    pub fn graph(&self) -> Result<Data> {
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
            && self.generation == self.owner.0.generation.load(Ordering::Acquire)
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
