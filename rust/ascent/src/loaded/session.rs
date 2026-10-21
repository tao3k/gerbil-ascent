//! Scheme source loading, atomic replacement and generation-scoped results.
use super::{SourceResult, result::Scope};
use crate::{
    Cancellation, Engine, Error, FactLimits, Limits, Program, Relation, Result, Row, Session,
};
use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

static NEXT_SOURCE: AtomicU64 = AtomicU64::new(1);
/// Allocate one process-unique source identity across VM and owned-data sessions.
/// # Errors
/// Rejects exhaustion instead of recycling a provenance authority.
pub fn allocate_source_identity() -> Result<u64> {
    NEXT_SOURCE
        .try_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
            value.checked_add(1)
        })
        .map_err(|_| Error::InvalidUpdate("source identities exhausted".into()))
}
static NEXT_RESULT: AtomicU64 = AtomicU64::new(1);

/// Execution receipt; results stay in Rust and can be retained without rerunning.
pub struct SourceObservation {
    pub complete: bool,
    pub relations: BTreeMap<String, Vec<Row>>,
    pub result_handle: u64,
    pub source_generation: u64,
    pub run_index: u64,
    pub reused: bool,
    pub active_rule_count: usize,
    pub evaluated: bool,
    pub reused_relations: Vec<String>,
}
/// Loaded native DSL owner, with atomic checked replacement and scoped results.
pub struct SourceSession {
    explanation: Option<crate::RuleExplanation>,
    session: Session,
    scope: Arc<Scope>,
    queries: Arc<[String]>,
    aliases: Arc<BTreeMap<String, String>>,
    public_descriptors: Option<Vec<Relation>>,
    results: BTreeMap<u64, SourceResult>,
    runs: u64,
    last_run: Option<Arc<crate::Snapshot>>,
}
impl SourceSession {
    #[must_use]
    pub fn is_closed(&self) -> bool {
        self.scope.check().is_err()
    }
    #[must_use]
    pub fn request_limit(&self) -> Option<usize> {
        self.scope.engine.request_limit()
    }
}
impl Engine {
    /// Open declarative Evidence directly in Rust with explicit query bindings.
    /// # Errors
    /// Invalid definitions, unknown constructors and caller limits fail closed.
    pub fn open_declaration_sources(
        &self,
        sources: &[&str],
        constructor: Option<&str>,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        self.admit_source()?;
        let entry = crate::RuleProgram::read_sources(sources, constructor)?;
        self.open_rule_program_inner(entry, limits)
    }
    /// Open a scoped, already lowered Evidence declaration in the Rust engine.
    /// # Errors
    /// Invalid programs, caller limits or initialization failures publish no owner.
    pub fn open_rule_program(
        &self,
        entry: crate::RuleProgram,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        self.admit_source()?;
        self.open_rule_program_inner(entry, limits)
    }
    fn open_rule_program_inner(
        &self,
        entry: crate::RuleProgram,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        let mut owner = self.open_source_program_inner(entry.program, limits)?;
        let mut aliases = (*owner.aliases).clone();
        aliases.extend(entry.output_aliases);
        owner.aliases = Arc::new(aliases);
        owner.queries = entry.outputs.into();
        owner.explanation = entry.explanation;
        let initial = owner.run(
            None,
            &SourceSession::default_limits(),
            &Cancellation::default(),
        )?;
        owner.result(initial.result_handle)?.close();
        // Constructor validation is not a completed public query receipt.
        owner.last_run = None;
        Ok(owner)
    }
    /// Load native pure Scheme DSL from a prebuilt library.
    /// # Errors
    /// Rejects malformed sources, unsupported syntax and invalid caller limits.
    pub fn open_sources(&self, sources: &[&str], limits: FactLimits) -> Result<SourceSession> {
        self.admit_source()?;
        self.open_source_program_inner(Program::read_sources(sources)?, limits)
    }
    /// Load the inert typed rule-source interface.
    /// # Errors
    /// Rejects executable forms and all rule admission failures.
    pub fn open_rule_sources(&self, sources: &[&str], limits: FactLimits) -> Result<SourceSession> {
        self.admit_source()?;
        self.open_source_program_inner(Program::read_rule_sources(sources)?, limits)
    }
    /// Open an owned catalog with the same lifecycle as loaded DSL sources.
    /// # Errors
    /// Rejects malformed declarations and policies that cannot be admitted.
    pub fn open_source_program(
        &self,
        program: Program,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        self.admit_source()?;
        self.open_source_program_inner(program, limits)
    }
    fn open_source_program_inner(
        &self,
        mut program: Program,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        program.fact_limits = program.fact_limits.tighten(limits)?;
        let aliases = program
            .relations
            .iter()
            .map(|r| (r.name.clone(), r.name.clone()))
            .collect::<BTreeMap<_, _>>();
        let queries = program
            .relations
            .iter()
            .map(|r| r.name.clone())
            .collect::<Vec<_>>()
            .into();
        let session = self.open(program)?;
        let identity = allocate_source_identity()?;
        let scope = Arc::new(Scope {
            identity,
            engine: self.clone(),
            generation: 0,
            closed: AtomicBool::new(false),
            owners: AtomicUsize::new(0),
        });
        Ok(SourceSession {
            explanation: None,
            session,
            scope,
            queries,
            aliases: Arc::new(aliases),
            public_descriptors: None,
            results: BTreeMap::new(),
            runs: 0,
            last_run: None,
        })
    }
    /// Open a constructor program with explicit public labels bound to native relation handles.
    /// # Errors
    /// Rejects missing handles, invalid labels and resource/admission failures.
    pub fn open_exported_program(
        &self,
        program: Program,
        aliases: BTreeMap<String, String>,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        let mut owner = self.open_source_program(program, limits)?;
        let declarations = owner
            .program()
            .relations
            .iter()
            .map(|r| (r.name.as_str(), r))
            .collect::<BTreeMap<_, _>>();
        if aliases.is_empty()
            || aliases.len() > 128
            || aliases.iter().any(|(label, handle)| {
                label.is_empty() || label.len() > 128 || !declarations.contains_key(handle.as_str())
            })
        {
            return Err(Error::InvalidProgram(
                "invalid constructor export bindings".into(),
            ));
        }
        let descriptors = aliases
            .iter()
            .map(|(label, handle)| {
                let mut relation = (*declarations
                    .get(handle.as_str())
                    .ok_or_else(|| Error::InvalidProgram("unknown export handle".into()))?)
                .clone();
                relation.name.clone_from(label);
                Ok(relation)
            })
            .collect::<Result<Vec<_>>>()?;
        owner.queries = aliases.keys().cloned().collect::<Vec<_>>().into();
        owner.aliases = Arc::new(aliases);
        owner.public_descriptors = Some(descriptors);
        Ok(owner)
    }
    /// Open a typed catalog with initial rows and an explicit exported query set.
    /// # Errors
    /// Invalid inputs, queries, guards and resource policies fail before ownership escapes.
    pub fn open_catalog(
        &self,
        program: Program,
        sources: BTreeMap<String, Vec<Row>>,
        queries: Vec<String>,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        let mut owner = self.open_source_program(program, limits)?;
        owner.validate_queries(&queries)?;
        owner.queries = queries.into();
        if !sources.is_empty() {
            owner.session.replace_sources(sources)?;
            owner
                .session
                .run(&SourceSession::default_limits(), &Cancellation::default())?;
        }
        Ok(owner)
    }
}
impl SourceSession {
    /// Observe declared metadata separately from replayed per-row provenance.
    /// # Errors
    /// Unknown/stale results and unsupported explanation templates remain gaps.
    pub fn explanation_metadata(&self, handle: u64, query: &str) -> Result<crate::Data> {
        let result = self.result(handle)?;
        result.rows(query)?;
        let program = crate::Catalog::observe(&self.source_program()?, &self.queries)?;
        let scope = crate::Data::object([
            (
                "sourceIdentity",
                crate::Data::Integer(result.identity()?.into()),
            ),
            (
                "sourceGeneration",
                crate::Data::Integer(result.generation()?.into()),
            ),
        ]);
        if let Some(template) = &self.explanation {
            let declaration = template.render(&program, &crate::Data::Null, query, &scope)?;
            return Ok(crate::Data::object([
                ("status", "recorded-only".into()),
                ("declaration", declaration),
                ("sources", program.field("relations")?.clone()),
                ("scope", scope),
                ("gap", "Reported source rows and declared dependencies are not a per-row proof or host authorization".into()),
            ]));
        }
        Ok(crate::Data::object([
            ("status", "recorded-only".into()), ("query", query.to_owned().into()),
            ("scope", scope), ("dependencies", program.field("rules")?.clone()),
            ("sources", program.field("relations")?.clone()),
            ("gap", "Declaration dependencies and source rows are not a per-row proof or host authorization".into()),
        ]))
    }
    /// Validate a live cell lease against this source owner.
    /// # Errors
    /// Rejects closed, stale or foreign cell leases.
    pub fn validate_value(&self, value: &crate::RowValue) -> Result<()> {
        self.scope.check()?;
        value.value()?;
        if !value.in_scope(&self.scope) {
            return Err(Error::InvalidUpdate("foreign result value".into()));
        }
        Ok(())
    }
    /// Snapshot the current admitted sources together with immutable declarations.
    /// # Errors
    /// Rejects closed source owners.
    pub fn source_program(&self) -> Result<Program> {
        self.scope.check()?;
        Ok(self.session.current_program())
    }
    /// Admitted declarations are immutable and available for typed projection.
    #[must_use]
    pub fn program(&self) -> &Program {
        self.session.program()
    }

    #[must_use]
    pub fn descriptors(&self) -> &[Relation] {
        self.public_descriptors
            .as_deref()
            .unwrap_or(&self.session.program().relations)
    }
    #[must_use]
    pub fn queries(&self) -> &[String] {
        &self.queries
    }
    #[must_use]
    pub fn fact_limits(&self) -> FactLimits {
        self.session.program().fact_limits
    }
    /// Validate and evaluate a candidate transaction before changing authority.
    /// Duplicate source occurrences count against input limits before set storage.
    /// # Errors
    /// Any admission, guard, budget or cancellation failure preserves this scope.
    pub fn replace(
        &mut self,
        sources: BTreeMap<String, Vec<Row>>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<u64> {
        self.scope.check()?;
        if self.runs == 0 {
            return Err(Error::InvalidUpdate(
                "session must run before source updates".into(),
            ));
        }
        let generation = self
            .scope
            .generation
            .checked_add(1)
            .ok_or_else(|| Error::InvalidUpdate("source generation exhausted".into()))?;
        let mut internal = BTreeMap::new();
        for (name, rows) in sources {
            let name = self
                .aliases
                .get(&name)
                .ok_or_else(|| Error::InvalidUpdate("unknown source export".into()))?;
            if internal.insert(name.clone(), rows).is_some() {
                return Err(Error::InvalidUpdate("duplicate source handle".into()));
            }
        }
        let mut candidate = self.session.clone();
        candidate.replace_sources(internal)?;
        candidate.run(limits, cancellation)?;
        self.scope.check()?;
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        self.commit_replacement(candidate, generation);
        Ok(generation)
    }
    fn commit_replacement(&mut self, candidate: Session, generation: u64) {
        self.scope.closed.store(true, Ordering::Release);
        self.scope = Arc::new(Scope {
            identity: self.scope.identity,
            engine: self.scope.engine.clone(),
            generation,
            closed: AtomicBool::new(false),
            owners: AtomicUsize::new(0),
        });
        self.session = candidate;
        self.last_run = None;
        self.results.clear();
    }
    /// # Errors
    /// Rejects invalid queries, canceled/limited runs and exhausted owner slots.
    pub fn run(
        &mut self,
        queries: Option<&[String]>,
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<SourceObservation> {
        self.scope.check()?;
        let queries = queries.unwrap_or(&self.queries);
        self.validate_queries(queries)?;
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        if limits.timeout.is_zero() {
            return Err(Error::Timeout);
        }
        {
            let queries = queries.to_vec();
            self.observe(&queries, limits, cancellation)
        }
    }
    fn validate_queries(&self, queries: &[String]) -> Result<()> {
        if queries.len() > 128
            || queries.iter().any(|q| !self.queries.contains(q))
            || queries
                .iter()
                .collect::<std::collections::BTreeSet<_>>()
                .len()
                != queries.len()
        {
            return Err(Error::InvalidUpdate("native DSL query contract".into()));
        }
        Ok(())
    }
    fn observe(
        &mut self,
        queries: &[String],
        limits: &Limits,
        cancellation: &Cancellation,
    ) -> Result<SourceObservation> {
        let run_index = self
            .runs
            .checked_add(1)
            .ok_or_else(|| Error::InvalidUpdate("run index exhausted".into()))?;
        let id = NEXT_RESULT
            .try_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                value.checked_add(1)
            })
            .map_err(|_| Error::InvalidUpdate("result handles exhausted".into()))?;
        let previous = self.last_run.as_ref();
        let evaluated = !self.session.is_clean();
        let snapshot = if limits.timeout.is_zero() {
            self.last_run.clone().ok_or(Error::Timeout)?
        } else {
            self.session.run(limits, cancellation)?
        };
        let reused = previous.is_some_and(|old| Arc::ptr_eq(old, &snapshot));
        let result = SourceResult::retain(
            self.scope.clone(),
            snapshot.clone(),
            self.queries.clone(),
            self.aliases.clone(),
        )?;
        self.results.retain(|_, result| !result.released());
        self.results.insert(id, result);
        self.runs = run_index;
        self.last_run = Some(snapshot.clone());
        Ok(SourceObservation {
            complete: true,
            relations: queries
                .iter()
                .map(|q| (q.clone(), snapshot.relations[&self.aliases[q]].clone()))
                .collect(),
            result_handle: id,
            source_generation: self.scope.generation,
            run_index,
            reused,
            active_rule_count: if evaluated {
                self.session.program().rules.len()
            } else {
                0
            },
            evaluated,
            reused_relations: if evaluated {
                Vec::new()
            } else {
                snapshot.relations.keys().cloned().collect()
            },
        })
    }
    /// Obtain an existing result without executing inference.
    /// # Errors
    /// Unknown, released and stale source-generation handles are rejected.
    pub fn result(&self, handle: u64) -> Result<SourceResult> {
        self.scope.check()?;
        let result = self
            .results
            .get(&handle)
            .ok_or_else(|| Error::InvalidUpdate("stale or unknown result".into()))?;
        result.generation()?;
        Ok(result.clone())
    }
    /// # Errors
    /// Provenance requires a current result and bounded independent replay.
    pub fn provenance(
        &self,
        handle: u64,
        query: &str,
        limits: &crate::ProvenanceLimits,
        cancel: &Cancellation,
    ) -> Result<crate::Provenance> {
        self.scope.check()?;
        crate::Provenance::generate(
            self.session.current_program(),
            &self.result(handle)?,
            query,
            limits,
            cancel,
        )
    }
    pub fn close(&mut self) {
        self.scope.closed.store(true, Ordering::Release);
        self.results.clear();
        self.session.close();
    }
    /// Scheme DSL defaults have no fact or work ceiling. Caller limits and
    /// finite declaration bounds remain independent, enforced restrictions.
    #[must_use]
    pub fn default_limits() -> Limits {
        Limits {
            timeout: Duration::from_secs(1),
            max_facts: usize::MAX,
            max_states: usize::MAX,
        }
    }
}
impl Drop for SourceSession {
    fn drop(&mut self) {
        self.close();
    }
}
