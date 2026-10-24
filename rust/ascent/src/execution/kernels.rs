//! Rust-owned storage/index kernels and Rayon scheduling for Scheme AOT rules.
use super::values::Row;
use super::{Bindings, Budget, Cancellation, Cell, Fact, FactSet, Limits, Pattern};
use super::{ordering, ordinal::OrdinalRows, policy};
use crate::{
    Result,
    graph::{Atom, Clause, Graph, Rule},
};
#[cfg(feature = "rayon")]
use rayon::iter::{IntoParallelIterator, IntoParallelRefIterator, ParallelIterator};
#[cfg(feature = "rayon")]
use rayon::slice::ParallelSlice;
use smallvec::SmallVec;
use std::{
    collections::{HashMap, HashSet},
    sync::{Arc, RwLock},
};

include!(concat!(env!("OUT_DIR"), "/execution.rs"));
type Key = SmallVec<[Cell; 2]>;
const CHUNK: usize = 128;
#[cfg(feature = "rayon")]
const TASK_ROWS: usize = 256;

fn project_value(term: &Pattern, bindings: &Bindings) -> Option<Cell> {
    match term {
        Pattern::Variable(id) => bindings[*id as usize],
        Pattern::Literal(value) => Some(*value),
        Pattern::Wildcard => None,
    }
}
fn project(terms: &[Pattern], bindings: &Bindings) -> Option<Row> {
    match terms {
        [] => Some(Arc::new([])),
        [one] => Some(Arc::new([project_value(one, bindings)?])),
        [one, two] => Some(Arc::new([
            project_value(one, bindings)?,
            project_value(two, bindings)?,
        ])),
        _ => terms
            .iter()
            .map(|term| project_value(term, bindings))
            .collect::<Option<Vec<_>>>()
            .map(Into::into),
    }
}

// BEGIN GENERATED LIVE FANOUT
#[cfg(feature = "rayon")]
#[inline]
fn stage_fanout(eligible: bool, current: &(dyn Fn() -> bool + Sync)) -> bool {
    eligible && current()
}
// END GENERATED LIVE FANOUT

enum Lookup {
    One {
        column: usize,
        rows: OrdinalRows,
    },
    Many {
        columns: Vec<usize>,
        rows: HashMap<Key, Vec<Row>>,
    },
}
struct Index {
    rows: Vec<Row>,
    keys: Vec<Lookup>,
    known: FactSet,
    lattice: HashMap<Vec<Cell>, Fact>,
}
impl Index {
    fn new(requirements: &[Vec<usize>]) -> Self {
        Self {
            rows: vec![],
            known: FactSet::default(),
            lattice: HashMap::new(),
            keys: requirements
                .iter()
                .map(|columns| match columns.as_slice() {
                    [column] => Lookup::One {
                        column: *column,
                        rows: OrdinalRows::default(),
                    },
                    _ => Lookup::Many {
                        columns: columns.clone(),
                        rows: HashMap::new(),
                    },
                })
                .collect(),
        }
    }
    fn insert(&mut self, row: Fact) -> bool {
        if !self.known.insert(row.clone()) {
            return false;
        }
        self.append(row.row);
        true
    }
    fn append(&mut self, row: Row) {
        for lookup in &mut self.keys {
            match lookup {
                Lookup::One { column, rows } => {
                    rows.insert(row[*column], row.clone());
                }
                Lookup::Many { columns, rows } => {
                    rows.entry(columns.iter().map(|i| row[*i]).collect())
                        .or_default()
                        .push(row.clone());
                }
            }
        }
        self.rows.push(row);
    }
    fn candidates(&self, atom: &Atom, bindings: &Bindings) -> &[Row] {
        let Some(slot) = atom.index else {
            return &self.rows;
        };
        let value = |i: usize| match &atom.terms[i] {
            Pattern::Variable(v) => bindings[*v as usize]
                .as_ref()
                .expect("admitted bound index"),
            Pattern::Literal(value) => value,
            Pattern::Wildcard => unreachable!("wildcard is not indexed"),
        };
        match &self.keys[slot] {
            Lookup::One { column, rows } => rows.get(*value(*column)),
            Lookup::Many { columns, rows } => {
                let key: Key = columns.iter().map(|i| *value(*i)).collect();
                rows.get(&key)
            }
        }
        .map_or(&[], Vec::as_slice)
    }
}
// Only inexact folds need canonical tuple order; exact integer/rational folds commute.
fn ordered_reduction_rows<'a>(
    rows: &'a [Row],
    atom: &Atom,
    inputs: &[usize],
    store: &Store,
    budget: &Budget,
) -> std::borrow::Cow<'a, [Row]> {
    if store.initial_occurrences[atom.relation] {
        return std::borrow::Cow::Borrowed(rows);
    }
    let Some(input) = inputs.first() else {
        return std::borrow::Cow::Borrowed(rows);
    };
    let Some(column) = atom
        .terms
        .iter()
        .position(|term| matches!(term,Pattern::Variable(slot) if *slot as usize==*input))
    else {
        return std::borrow::Cow::Borrowed(rows);
    };
    let values = store.values.read().expect("reducer ordering values");
    let inexact = rows.iter().any(|row| {
        if !budget.work(1) {
            return true;
        }
        crate::numbers::Number::is_inexact(values.scalar(row[column]))
    });
    if !inexact || !budget.active() {
        return std::borrow::Cow::Borrowed(rows);
    }
    let mut ordered = rows.to_vec();
    ordered.sort_unstable_by(|a, b| {
        budget.work(1);
        a.iter()
            .map(|cell| values.scalar(*cell))
            .cmp(b.iter().map(|cell| values.scalar(*cell)))
    });
    std::borrow::Cow::Owned(ordered)
}
pub(crate) struct Store<'a> {
    lattices: Vec<Option<crate::LatticeJoin>>,
    values: RwLock<super::Values>,
    all: Vec<Index>,
    delta: Vec<Index>,
    #[cfg(feature = "rayon")]
    parallel: &'a (dyn Fn() -> bool + Sync),
    #[cfg(not(feature = "rayon"))]
    _parallel: std::marker::PhantomData<&'a ()>,
    initial_occurrences: Vec<bool>,
}

/// Binding batches are local to one rule/pivot. Indexes are immutable while
/// workers read them; only completed rounds publish delta rows.
pub(crate) struct Batch(Vec<Bindings>);
impl Batch {
    pub fn initial(variables: usize) -> Self {
        Self(vec![std::iter::repeat_n(None, variables).collect()])
    }
    pub fn join(
        self,
        (step, atom): (usize, &Atom),
        store: &Store,
        pivot: Option<usize>,
        budget: &Budget,
    ) -> Self {
        let index = if policy::delta_lane(step, pivot.unwrap_or(0), pivot.is_some()) {
            &store.delta[atom.relation]
        } else {
            &store.all[atom.relation]
        };
        // A Set witness belongs to its first fresh body occurrence. Lattice
        // refinements are not set insertion: preserve their existing traversal.
        let excluded = policy::old_lane(
            step,
            pivot.unwrap_or(0),
            pivot.is_some(),
            store.lattices[atom.relation].is_none(),
        )
        .then_some(&store.delta[atom.relation]);
        let extend = |bindings: &[Bindings]| join_group(index, atom, bindings, budget, excluded);
        #[cfg(feature = "rayon")]
        if stage_fanout(self.0.len() >= TASK_ROWS * 2, store.parallel) {
            return Self(
                self.0
                    .par_chunks(TASK_ROWS)
                    .flat_map_iter(|task| task.chunks(CHUNK).flat_map(extend))
                    .collect(),
            );
        }
        #[cfg(feature = "rayon")]
        if stage_fanout(self.0.len() == 1, store.parallel) {
            let prior = &self.0[0];
            let rows = index.candidates(atom, prior);
            if rows.len() >= TASK_ROWS * 2 {
                return Self(
                    rows.par_chunks(TASK_ROWS)
                        .flat_map_iter(|task| {
                            task.chunks(CHUNK).flat_map(|chunk| {
                                join_chunk(&atom.terms, prior, chunk, budget, excluded)
                            })
                        })
                        .collect(),
                );
            }
        }
        Self(self.0.chunks(CHUNK).flat_map(extend).collect())
    }

    pub fn exclude(self, (_step, atom): (usize, &Atom), store: &Store, budget: &Budget) -> Self {
        let index = &store.all[atom.relation];
        Self(
            self.0
                .into_iter()
                .filter(|bindings| {
                    budget.poll()
                        && !index
                            .candidates(atom, bindings)
                            .iter()
                            .any(|row| budget.work(1) && bind(&atom.terms, row, bindings).is_some())
                })
                .collect(),
        )
    }
    pub fn advance(
        self,
        (step, clause): (usize, &Clause),
        store: &Store,
        pivot: Option<usize>,
        budget: &Budget,
    ) -> Self {
        match clause {
            Clause::Relation {
                atom,
                negative: false,
            } => self.join((step, atom), store, pivot, budget),
            Clause::Relation {
                atom,
                negative: true,
            } => self.exclude((step, atom), store, budget),
            Clause::Guard(expression) => self.guard(expression, store, budget),
            Clause::Compute { output, expression } => {
                self.compute(*output, expression, store, budget)
            }
            Clause::Reduce {
                output,
                operator,
                atom,
                inputs,
            } => self.reduce(*output, *operator, atom, inputs, store, budget),
        }
    }
    fn guard(self, expression: &crate::Expression, store: &Store, budget: &Budget) -> Self {
        let values = store.values.read().expect("expression values");
        let retain =
            |bindings: &Bindings| super::expressions::guard(expression, bindings, &values, budget);
        Self(self.0.into_iter().filter(retain).collect())
    }
    fn compute(
        self,
        output: usize,
        expression: &crate::Expression,
        store: &Store,
        budget: &Budget,
    ) -> Self {
        let mut retained = Vec::new();
        for mut bindings in self.0 {
            let value = {
                let values = store.values.read().expect("expression values");
                super::expressions::evaluate(expression, &bindings, &values, budget)
            };
            match value {
                Ok(value) => {
                    let cell = store
                        .values
                        .write()
                        .expect("computed values")
                        .intern(&value);
                    if bindings[output].is_none_or(|prior| prior == cell) {
                        bindings[output] = Some(cell);
                        retained.push(bindings);
                    }
                }
                Err(error) => {
                    budget.evaluation_error(error);
                    break;
                }
            }
        }
        Self(retained)
    }
    fn reduce(
        self,
        output: usize,
        operator: crate::Reducer,
        atom: &Atom,
        inputs: &[usize],
        store: &Store,
        budget: &Budget,
    ) -> Self {
        let index = &store.all[atom.relation];
        let mut retained = Vec::new();
        for mut prior in self.0 {
            let mut accumulator = super::reductions::Reduction::default();
            let candidates =
                ordered_reduction_rows(index.candidates(atom, &prior), atom, inputs, store, budget);
            for row in candidates.iter() {
                if !budget.work(1) {
                    break;
                }
                let Some(binding) = bind(&atom.terms, row, &prior) else {
                    continue;
                };
                let values = store.values.read().expect("reducer input values");
                let value = inputs
                    .first()
                    .and_then(|input| binding[*input])
                    .map(|cell| values.scalar(cell));
                if let Err(error) = accumulator.push(operator, value, budget) {
                    budget.evaluation_error(error);
                    break;
                }
            }
            if !budget.active() {
                break;
            }
            let value = match accumulator.finish(operator) {
                Ok(value) => value,
                Err(error) => {
                    budget.evaluation_error(error);
                    break;
                }
            };
            if let Some(value) = value {
                let cell = store.values.write().expect("reduced values").intern(&value);
                if prior[output].is_none_or(|old| old == cell) {
                    prior[output] = Some(cell);
                    retained.push(prior);
                }
            }
        }
        Self(retained)
    }
    pub fn project(self, rule: &Rule, store: &Store, budget: &Budget) -> bool {
        project_group(&self.0, rule, store, budget)
    }
}
fn project_group(bindings: &[Bindings], rule: &Rule, store: &Store, budget: &Budget) -> bool {
    let mut projection = Projection {
        rule,
        store,
        budget,
        unique: FactSet::default(),
        pending: Vec::with_capacity(CHUNK),
    };
    for chunk in bindings.chunks(CHUNK) {
        if !projection.extend(chunk) {
            break;
        }
    }
    projection.flush()
}
fn match_rows<'a>(
    terms: &'a [Pattern],
    prior: &'a Bindings,
    rows: &'a [Row],
    budget: &'a Budget,
    excluded: Option<&'a Index>,
) -> impl Iterator<Item = Bindings> + 'a {
    rows.iter().filter_map(move |row| {
        if !budget.active() {
            return None;
        }
        if excluded.is_some_and(|fresh| fresh.known.contains(&budget.fact(row.clone()))) {
            return None;
        }
        let matched = bind(terms, row, prior);
        #[cfg(test)]
        if matched.is_some() {
            budget
                .matches
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        matched
    })
}
fn join_chunk(
    terms: &[Pattern],
    prior: &Bindings,
    rows: &[Row],
    budget: &Budget,
    excluded: Option<&Index>,
) -> Vec<Bindings> {
    if !budget.work(rows.len()) {
        return Vec::new();
    }
    match_rows(terms, prior, rows, budget, excluded).collect()
}
fn join_group(
    index: &Index,
    atom: &Atom,
    bindings: &[Bindings],
    budget: &Budget,
    excluded: Option<&Index>,
) -> Vec<Bindings> {
    let inputs: SmallVec<[(&Bindings, &[Row]); CHUNK]> = bindings
        .iter()
        .map(|prior| (prior, index.candidates(atom, prior)))
        .collect();
    let work = inputs
        .iter()
        .try_fold(0_usize, |total, (_, rows)| total.checked_add(rows.len()));
    if let Some(count) = work.filter(|count| *count <= CHUNK) {
        if !budget.work(count) {
            return Vec::new();
        }
        return inputs
            .into_iter()
            .flat_map(|(prior, rows)| match_rows(&atom.terms, prior, rows, budget, excluded))
            .collect();
    }
    inputs
        .into_iter()
        .flat_map(|(prior, rows)| {
            rows.chunks(CHUNK)
                .flat_map(move |chunk| join_chunk(&atom.terms, prior, chunk, budget, excluded))
        })
        .collect()
}

struct Projection<'a> {
    rule: &'a Rule,
    store: &'a Store<'a>,
    budget: &'a Budget,
    unique: FactSet,
    pending: Vec<Fact>,
}
impl Projection<'_> {
    fn extend(&mut self, chunk: &[Bindings]) -> bool {
        if !self.budget.work(chunk.len()) {
            return false;
        }
        chunk
            .iter()
            .all(|bindings| self.budget.active() && self.push(bindings))
    }
    fn push(&mut self, bindings: &Bindings) -> bool {
        #[cfg(test)]
        self.budget
            .witnesses
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        let projected = project(&self.rule.head.terms, bindings).expect("admitted head bindings");
        if let Some(types) = &self.rule.head.dynamic_types {
            if !self.budget.work(projected.len()) {
                return false;
            }
            let values = self.store.values.read().expect("derived type owner");
            if !projected
                .iter()
                .zip(types.iter())
                .all(|(cell, ty)| ty.accepts(values.scalar(*cell)))
            {
                self.budget.evaluation_error(crate::Error::Evaluation(
                    "derived row violates column type".into(),
                ));
                return false;
            }
        }
        if !self.rule.head.accepts(&projected) {
            self.budget.evaluation_error(crate::Error::Evaluation(
                "derived row violates column domain".into(),
            ));
            return false;
        }
        let row = self.budget.fact(projected);
        if let Some(mode) = self.store.lattices[self.rule.head.relation] {
            let values = self.store.values.read().expect("lattice value owner");
            if let Err(error) =
                crate::lattice::numeric(values.scalar(*row.row.last().expect("lattice arity")))
            {
                self.budget.evaluation_error(error);
                return false;
            }
            if let Some(prior) = self.store.all[self.rule.head.relation]
                .lattice
                .get(super::lattice::key(&row.row))
            {
                match super::lattice::improves(mode, &row, prior, &values) {
                    Ok(false) => return true,
                    Ok(true) => (),
                    Err(error) => {
                        self.budget.evaluation_error(error);
                        return false;
                    }
                }
            }
        }
        if self.store.all[self.rule.head.relation].known.contains(&row)
            || !self.unique.insert(row.clone())
        {
            return true;
        }
        self.pending.push(row);
        self.pending.len() < CHUNK || self.flush()
    }
    fn flush(&mut self) -> bool {
        if self.pending.is_empty() {
            return self.budget.active();
        }
        let pending = std::mem::replace(&mut self.pending, Vec::with_capacity(CHUNK));
        self.unique.clear();
        if let Some(mode) = self.store.lattices[self.rule.head.relation] {
            let values = self.store.values.read().expect("lattice value owner");
            self.budget
                .admit_lattice(self.rule.head.relation, pending, mode, &values)
        } else {
            self.budget.admit(self.rule.head.relation, pending)
        }
    }
}

pub(crate) struct Round<'a> {
    graph: &'a Graph,
    store: Store<'a>,
    budget: &'a Budget,
    stratum: usize,
    first: bool,
    done: bool,
}
type RuleKernel = fn(&Rule, &Store, Option<usize>, &Budget) -> bool;
impl Round<'_> {
    fn tasks_for<'a>(&self, rule: &'a Rule) -> Vec<(&'a Rule, Option<usize>)> {
        if self.first {
            return vec![(rule, None)];
        }
        rule.body
            .iter()
            .enumerate()
            .filter_map(|(step, clause)| match clause {
                Clause::Relation {
                    atom,
                    negative: false,
                } if !self.store.delta[atom.relation].rows.is_empty() => Some((rule, Some(step))),
                _ => None,
            })
            .collect()
    }
    fn evaluate(self, kernel: RuleKernel) -> Self {
        let tasks: Vec<_> = self
            .graph
            .rules
            .iter()
            .filter(|rule| self.graph.strata[rule.head.relation] == self.stratum)
            .flat_map(|rule| self.tasks_for(rule))
            .collect();
        let apply = |(rule, pivot): &(&Rule, Option<usize>)| {
            kernel(rule, &self.store, *pivot, self.budget);
            1_usize
        };
        #[cfg(feature = "rayon")]
        let completed = if stage_fanout(tasks.len() > 1, self.store.parallel) {
            tasks.par_iter().map(apply).sum()
        } else {
            tasks.iter().map(apply).sum()
        };
        #[cfg(not(feature = "rayon"))]
        let completed = tasks.iter().map(apply).sum();
        if !policy::joined_round(tasks.len(), completed, 0, 0, false, true) {
            self.budget.evaluation_error(crate::Error::Evaluation(
                "execution completion certificate rejected".into(),
            ));
        }
        self
    }
    fn publish(mut self) -> Self {
        self.store.delta = self
            .graph
            .indexes
            .iter()
            .map(|shapes| Index::new(shapes))
            .collect();
        let tasks: Vec<_> = self
            .store
            .all
            .iter_mut()
            .zip(&mut self.store.delta)
            .enumerate()
            .filter_map(|(relation, (all, delta))| {
                let rows = self.budget.pending_len(relation);
                (rows != 0).then_some(Publisher {
                    relation,
                    all,
                    delta,
                    rows,
                    lattice: self.graph.program.relations[relation].lattice,
                    shapes: &self.graph.indexes[relation],
                })
            })
            .collect();
        #[cfg(feature = "rayon")]
        let admitted: usize = if stage_fanout(
            tasks.len() > 1 && tasks.iter().map(|task| task.rows).sum::<usize>() >= 512,
            self.store.parallel,
        ) {
            tasks
                .into_par_iter()
                .map(|task| task.commit(self.budget))
                .sum()
        } else {
            tasks.into_iter().map(|task| task.commit(self.budget)).sum()
        };
        #[cfg(not(feature = "rayon"))]
        let admitted: usize = tasks.into_iter().map(|task| task.commit(self.budget)).sum();
        // Keep the original polling boundary: zero admissions are checked by
        // the outer budget.result() before a stratum can return successfully.
        self.done = !policy::round_continue(admitted, admitted == 0 || self.budget.poll());
        self.first = false;
        self
    }
}
struct Publisher<'a> {
    lattice: Option<crate::LatticeJoin>,
    shapes: &'a [Vec<usize>],
    relation: usize,
    all: &'a mut Index,
    delta: &'a mut Index,
    rows: usize,
}
impl Publisher<'_> {
    fn commit(self, budget: &Budget) -> usize {
        budget.publish(self.relation, |pending| {
            debug_assert_eq!(
                pending.len(),
                self.rows,
                "producer join freezes pending membership"
            );
            if self.lattice.is_some() {
                publish_lattice(self.all, self.delta, pending, self.shapes, budget)
            } else {
                publish_relation(self.all, self.delta, pending, budget)
            }
        })
    }
}

fn publish_lattice(
    all: &mut Index,
    delta: &mut Index,
    pending: &mut FactSet,
    shapes: &[Vec<usize>],
    budget: &Budget,
) -> usize {
    let changed = pending.len();
    for fact in pending.drain() {
        if !budget.work(1) {
            return 0;
        }
        all.lattice
            .insert(super::lattice::key(&fact.row).to_vec(), fact.clone());
        delta.insert(fact);
    }
    let mut rebuilt = Index::new(shapes);
    for fact in all.lattice.values() {
        if !budget.work(1) {
            return 0;
        }
        rebuilt.insert(fact.clone());
    }
    rebuilt.lattice = std::mem::take(&mut all.lattice);
    *all = rebuilt;
    changed
}

fn publish_relation(
    all: &mut Index,
    delta: &mut Index,
    pending: &mut FactSet,
    budget: &Budget,
) -> usize {
    if !budget.poll() {
        pending.clear();
        return 0;
    }
    all.known.reserve(pending.len());
    all.rows.reserve(pending.len());
    delta.rows.reserve(pending.len());
    delta.known.reserve(pending.len());
    pending
        .drain()
        .enumerate()
        .take_while(|(i, _)| (i % CHUNK != 0 || budget.poll()) && budget.active())
        .filter_map(|(_, fact)| {
            if !all.insert(fact.clone()) {
                return None;
            }
            // Exact delta membership is needed by disjoint prefix reads.
            // Keep the existing query-owned digest; never hash a Scheme value.
            delta.insert(fact);
            Some(())
        })
        .count()
}

fn initial_indexes(
    graph: &Graph,
    sources: &[Vec<crate::Row>],
    budget: &Budget,
) -> Result<(super::Values, Vec<Index>)> {
    let mut values = graph.values.clone();
    let mut all: Vec<_> = graph
        .indexes
        .iter()
        .map(|shapes| Index::new(shapes))
        .collect();
    for (relation, source_rows) in sources.iter().enumerate() {
        let fixed;
        let rows = if graph.program.relations[relation].source {
            source_rows
        } else {
            fixed = if graph.program.relations[relation].initial_occurrences {
                graph.program.relations[relation].rows.clone()
            } else {
                graph.program.relations[relation]
                    .rows
                    .iter()
                    .cloned()
                    .collect::<HashSet<_>>()
                    .into_iter()
                    .collect()
            };
            &fixed
        };
        if !graph.program.relations[relation].auxiliary
            && !budget.relation_facts(relation, rows.len())
        {
            break;
        }
        let mode = graph.program.relations[relation].lattice;
        if mode.is_none() && !budget.facts(rows.len()) {
            break;
        }
        insert_initial_rows(
            rows,
            graph.program.relations[relation].initial_occurrences,
            mode,
            &mut all[relation],
            &mut values,
            budget,
        )?;
        if mode.is_some() {
            if !budget.facts(all[relation].lattice.len()) {
                break;
            }
            let facts = all[relation].lattice.values().cloned().collect::<Vec<_>>();
            for fact in facts {
                all[relation].insert(fact);
            }
        }
    }
    budget.result()?;
    Ok((values, all))
}

fn insert_initial_rows(
    rows: &[crate::Row],
    occurrences: bool,
    mode: Option<crate::LatticeJoin>,
    index: &mut Index,
    values: &mut super::Values,
    budget: &Budget,
) -> Result<()> {
    let ordered: Box<dyn Iterator<Item = &crate::Row>> = if occurrences {
        Box::new(rows.iter().rev())
    } else {
        Box::new(rows.iter())
    };
    for (i, row) in ordered.enumerate() {
        if (i % CHUNK == 0 && !budget.poll()) || !budget.active() {
            break;
        }
        let encoded = row
            .iter()
            .map(|value| values.intern(value))
            .collect::<Vec<_>>()
            .into();
        let fact = budget.fact(encoded);
        if let Some(mode) = mode {
            super::lattice::merge(&mut index.lattice, vec![fact], mode, values)?;
        } else if occurrences {
            index.known.insert(fact.clone());
            index.append(fact.row);
        } else {
            index.insert(fact);
        }
    }
    Ok(())
}

pub(crate) fn evaluate(
    graph: &Graph,
    sources: &[Vec<crate::Row>],
    limits: &Limits,
    cancellation: &Cancellation,
    parallel: impl Fn() -> bool + Sync,
    started: std::time::Instant,
) -> Result<Vec<super::EvaluatedRows>> {
    #[cfg(not(feature = "rayon"))]
    let _ = parallel;
    // Queueing consumes the same caller budget as evaluation/publication.
    // Reject before allocating indexes when a worker accepts stale work.
    if cancellation.is_canceled() {
        return Err(crate::Error::Canceled);
    }
    if started.elapsed() >= limits.timeout {
        return Err(crate::Error::Timeout);
    }
    let budget = Budget::new(
        limits,
        cancellation,
        sources.len(),
        graph.program.fact_limits,
        graph.program.relation_limit,
        started,
    );
    evaluate_budgeted(graph, sources, &budget, parallel)
}

fn evaluate_budgeted(
    graph: &Graph,
    sources: &[Vec<crate::Row>],
    budget: &Budget,
    parallel: impl Fn() -> bool + Sync,
) -> Result<Vec<super::EvaluatedRows>> {
    #[cfg(not(feature = "rayon"))]
    let _ = parallel;
    let (values, all) = initial_indexes(graph, sources, budget)?;
    let store = Store {
        initial_occurrences: graph
            .program
            .relations
            .iter()
            .map(|r| r.initial_occurrences)
            .collect(),
        lattices: graph.program.relations.iter().map(|r| r.lattice).collect(),
        values: RwLock::new(values),
        all,
        delta: graph
            .indexes
            .iter()
            .map(|shapes| Index::new(shapes))
            .collect(),
        #[cfg(feature = "rayon")]
        parallel: &parallel,
        #[cfg(not(feature = "rayon"))]
        _parallel: std::marker::PhantomData,
    };
    let mut round = Round {
        graph,
        store,
        budget,
        stratum: 0,
        first: true,
        done: false,
    };
    for stratum in 0..=graph.strata.iter().copied().max().unwrap_or(0) {
        round.stratum = stratum;
        round.first = true;
        round.done = false;
        while !round.done {
            budget.result()?;
            round = advance_round(round);
        }
        budget.result()?;
    }
    let values = round.store.values.into_inner().expect("joined value owner");
    // Amortize actual-value ordering only for large reused vocabularies. Small
    // outputs retain the existing decoded sort and allocate no ranking table.
    let ranks = round
        .store
        .all
        .iter()
        .enumerate()
        .any(|(relation, index)| {
            (!graph.program.relations[relation].source
                || graph.program.relations[relation].lattice.is_some())
                && index.rows.len() >= 8192
                && index.rows.len() / 2 >= values.values.len()
        })
        .then(|| ordering::ranks(&values));
    budget.result()?;
    let rows = round
        .store
        .all
        .into_iter()
        .enumerate()
        .map(|(relation, index)| {
            if graph.program.relations[relation].source
                && graph.program.relations[relation].lattice.is_none()
            {
                super::EvaluatedRows::new(sources[relation].clone(), false)
            } else {
                decode_rows(index, &values, ranks.as_deref(), budget, &parallel)
            }
        })
        .collect();
    budget.result()?;
    Ok(rows)
}
fn decode_rows(
    index: Index,
    values: &super::Values,
    ranks: Option<&[usize]>,
    budget: &Budget,
    parallel: &(dyn Fn() -> bool + Sync),
) -> super::EvaluatedRows {
    let Index {
        rows,
        keys,
        known,
        lattice,
    } = index;
    drop(lattice);
    drop(keys);
    drop(known);
    ordering::decode(rows, values, ranks, budget, parallel, CHUNK)
}

#[cfg(test)]
#[path = "../../tests/unit/delta.rs"]
mod delta_tests;

#[cfg(test)]
#[path = "../../tests/unit/physical_index.rs"]
mod physical_index_tests;
