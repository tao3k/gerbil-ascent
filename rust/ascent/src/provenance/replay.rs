//! Independent stratified least-closure replay followed by complete alternative enumeration.
use super::{
    ProvenanceEdge, ProvenanceGraph, ProvenanceLimits, ProvenanceNode, ProvenanceStatus,
    ProvenanceWitness, owner::invalid,
};
use crate::{Atom, Cancellation, Clause, Error, Program, Result, Row, SourceResult, Term, Value};
use std::{
    collections::{BTreeMap, BTreeSet},
    time::Instant,
};
type Bindings = BTreeMap<u32, Value>;
#[derive(Clone)]
struct Frame {
    bindings: Bindings,
    inputs: Vec<usize>,
    witnesses: Vec<ProvenanceWitness>,
}
struct Replay<'a> {
    limits: &'a ProvenanceLimits,
    cancel: &'a Cancellation,
    start: Instant,
    steps: usize,
    nodes: Vec<ProvenanceNode>,
    by_row: BTreeMap<(String, Row), usize>,
    relations: BTreeMap<String, Vec<usize>>,
    initial_occurrences: BTreeSet<String>,
    edges: BTreeSet<ProvenanceEdge>,
}
impl Replay<'_> {
    fn step(&mut self) -> Result<()> {
        if self.cancel.is_canceled() {
            return Err(Error::Canceled);
        }
        self.steps = self.steps.checked_add(1).ok_or(Error::StateLimit)?;
        if self.steps > self.limits.max_steps || self.start.elapsed() >= self.limits.timeout {
            return Err(Error::StateLimit);
        }
        Ok(())
    }
    fn node(&mut self, name: &str, row: Row, source: bool) -> Result<(usize, bool)> {
        self.step()?;
        let key = (name.into(), row.clone());
        if let Some(id) = self.by_row.get(&key) {
            return Ok((*id, false));
        }
        if self.nodes.len() >= self.limits.max_nodes {
            return Err(Error::StateLimit);
        }
        let id = self.nodes.len();
        self.nodes.push(ProvenanceNode {
            relation: name.into(),
            row,
            source,
        });
        self.by_row.insert(key, id);
        self.relations.entry(name.into()).or_default().push(id);
        Ok((id, true))
    }
    fn edge(&mut self, edge: ProvenanceEdge) -> Result<()> {
        self.step()?;
        if !self.edges.contains(&edge) && self.edges.len() >= self.limits.max_edges {
            return Err(Error::StateLimit);
        }
        self.edges.insert(edge);
        Ok(())
    }
    fn seed(&mut self, program: &Program, result: &SourceResult) -> Result<()> {
        for relation in &program.relations {
            if relation.initial_occurrences {
                self.initial_occurrences.insert(relation.name.clone());
            }
            self.relations.insert(relation.name.clone(), Vec::new());
            let rows = if relation.source && !relation.initial_occurrences {
                &result.relations()?[&relation.name]
            } else {
                &relation.rows
            };
            self.seed_rows(relation, rows)?;
        }
        Ok(())
    }
    fn seed_rows(&mut self, relation: &crate::Relation, rows: &[Row]) -> Result<()> {
        if relation.initial_occurrences {
            for row in rows.iter().rev() {
                let (id, fresh) = self.node(&relation.name, row.clone(), relation.source)?;
                if !fresh {
                    self.relations.get_mut(&relation.name).unwrap().push(id);
                }
                self.edge(ProvenanceEdge {
                    output: id,
                    rule: None,
                    inputs: vec![],
                    witnesses: vec![],
                })?;
            }
        } else {
            let rows = self.unique_rows(rows)?;
            for row in rows {
                let (id, _) = self.node(&relation.name, row, relation.source)?;
                self.edge(ProvenanceEdge {
                    output: id,
                    rule: None,
                    inputs: vec![],
                    witnesses: vec![],
                })?;
            }
        }
        Ok(())
    }
    fn unique_rows(&mut self, rows: &[Row]) -> Result<BTreeSet<Row>> {
        let mut unique = BTreeSet::new();
        for row in rows {
            self.step()?;
            if unique.len() >= self.limits.max_nodes && !unique.contains(row) {
                return Err(Error::StateLimit);
            }
            unique.insert(row.clone());
        }
        Ok(unique)
    }
    fn frames(&mut self, rule: &crate::Rule) -> Result<Vec<Frame>> {
        let mut frames = vec![Frame {
            bindings: Bindings::new(),
            inputs: Vec::new(),
            witnesses: Vec::new(),
        }];
        for clause in &rule.body {
            frames = match clause {
                Clause::Relation {
                    atom,
                    negative: false,
                } => self.join(frames, atom)?,
                Clause::Relation {
                    atom,
                    negative: true,
                } => self.exclude(frames, atom)?,
                Clause::Guard { expression, .. } => self.scalar(frames, None, expression)?,
                Clause::Compute {
                    output, expression, ..
                } => self.scalar(frames, Some(*output), expression)?,
                Clause::Reduce {
                    output,
                    operator,
                    atom,
                    inputs,
                } => self.reduce(frames, *output, *operator, atom, inputs)?,
            };
        }
        Ok(frames)
    }
    fn join(&mut self, frames: Vec<Frame>, atom: &Atom) -> Result<Vec<Frame>> {
        let candidates = self.relations[&atom.relation].clone();
        let mut next = Vec::new();
        for prior in frames {
            for id in &candidates {
                self.step()?;
                if let Some(bindings) = bind(atom, &self.nodes[*id].row, &prior.bindings) {
                    let mut frame = prior.clone();
                    frame.bindings = bindings;
                    frame.inputs.push(*id);
                    next.push(frame);
                }
            }
        }
        Ok(next)
    }
    fn exclude(&mut self, frames: Vec<Frame>, atom: &Atom) -> Result<Vec<Frame>> {
        let candidates = self.relations[&atom.relation].clone();
        let mut next = Vec::new();
        for mut frame in frames {
            let mut found = false;
            for id in &candidates {
                self.step()?;
                if bind(atom, &self.nodes[*id].row, &frame.bindings).is_some() {
                    found = true;
                    break;
                }
            }
            if !found {
                frame.witnesses.push(ProvenanceWitness::Absent(ground_atom(
                    atom,
                    &frame.bindings,
                )));
                next.push(frame);
            }
        }
        Ok(next)
    }
    fn scalar(
        &mut self,
        frames: Vec<Frame>,
        output: Option<u32>,
        expression: &crate::Expression,
    ) -> Result<Vec<Frame>> {
        let mut next = Vec::new();
        for mut frame in frames {
            let expression = super::expression::ground(expression, &frame.bindings)?;
            let value = super::expression::evaluate(&expression, &mut || self.step())?;
            if let Some(slot) = output {
                if frame.bindings.get(&slot).is_some_and(|old| old != &value) {
                    continue;
                }
                frame.bindings.insert(slot, value.clone());
                frame.witnesses.push(ProvenanceWitness::Compute {
                    slot,
                    expression,
                    value,
                });
                next.push(frame);
            } else {
                match value {
                    Value::Boolean(true) => {
                        frame.witnesses.push(ProvenanceWitness::Guard(expression));
                        next.push(frame);
                    }
                    Value::Boolean(false) => (),
                    _ => return Err(Error::Evaluation("proof guard must return boolean".into())),
                }
            }
        }
        Ok(next)
    }
    fn reduce(
        &mut self,
        frames: Vec<Frame>,
        output: u32,
        operator: crate::Reducer,
        atom: &Atom,
        inputs: &[u32],
    ) -> Result<Vec<Frame>> {
        let candidates = self.relations[&atom.relation].clone();
        frames
            .into_iter()
            .map(|frame| {
                self.reduced_frame(
                    frame,
                    output,
                    operator,
                    atom,
                    inputs.first().copied(),
                    &candidates,
                )
            })
            .collect::<Result<Vec<_>>>()
            .map(|frames| frames.into_iter().flatten().collect())
    }
    fn reduced_frame(
        &mut self,
        mut frame: Frame,
        output: u32,
        operator: crate::Reducer,
        atom: &Atom,
        input: Option<u32>,
        candidates: &[usize],
    ) -> Result<Option<Frame>> {
        let (rows, values) = self.group(atom, candidates, &frame.bindings, input)?;
        let Some(value) = reduction(operator, rows.len(), &values, &mut || self.step())? else {
            return Ok(None);
        };
        if frame.bindings.get(&output).is_some_and(|old| old != &value) {
            return Ok(None);
        }
        frame.witnesses.push(ProvenanceWitness::Aggregate {
            atom: ground_atom(atom, &frame.bindings),
            operator,
            rows,
            value: value.clone(),
        });
        frame.bindings.insert(output, value);
        Ok(Some(frame))
    }
    fn group(
        &mut self,
        atom: &Atom,
        candidates: &[usize],
        prior: &Bindings,
        input: Option<u32>,
    ) -> Result<(Vec<usize>, Vec<Value>)> {
        let mut rows = Vec::new();
        let mut values = Vec::new();
        for id in candidates {
            self.step()?;
            if let Some(bindings) = bind(atom, &self.nodes[*id].row, prior) {
                rows.push(*id);
                if let Some(input) = input {
                    values.push(bindings[&input].clone());
                }
            }
        }
        if !self.initial_occurrences.contains(&atom.relation)
            && values.iter().any(crate::numbers::Number::is_inexact)
        {
            let mut grouped = rows.into_iter().zip(values).collect::<Vec<_>>();
            grouped.sort_unstable_by(|a, b| self.nodes[a.0].row.cmp(&self.nodes[b.0].row));
            for _ in 0..grouped.len() {
                self.step()?;
            }
            return Ok(grouped.into_iter().unzip());
        }
        Ok((rows, values))
    }
    fn closure(&mut self, program: &Program) -> Result<()> {
        let strata = strata(program, &mut || self.step())?;
        for stratum in 0..=strata.values().copied().max().unwrap_or(0) {
            loop {
                let mut changed = false;
                for rule in program
                    .rules
                    .iter()
                    .filter(|r| strata[&r.head.relation] == stratum)
                {
                    for frame in self.frames(rule)? {
                        let row = ground(&rule.head, &frame.bindings)?;
                        changed |= self.node(&rule.head.relation, row, false)?.1;
                    }
                }
                if !changed {
                    break;
                }
            }
        }
        Ok(())
    }
    fn same_closure(&self, result: &SourceResult) -> Result<bool> {
        for (name, rows) in result.relations()? {
            let mut expected: Vec<_> = rows.clone();
            let mut actual: Vec<_> = self.relations[name]
                .iter()
                .map(|id| self.nodes[*id].row.clone())
                .collect();
            expected.sort();
            actual.sort();
            if !self.initial_occurrences.contains(name) {
                expected.dedup();
                actual.dedup();
            }
            if expected != actual {
                return Ok(false);
            }
        }
        Ok(true)
    }
    fn alternatives(&mut self, program: &Program) -> Result<()> {
        for (rule_id, rule) in program.rules.iter().enumerate() {
            for frame in self.frames(rule)? {
                let row = ground(&rule.head, &frame.bindings)?;
                let output = self.by_row[&(rule.head.relation.clone(), row)];
                self.edge(ProvenanceEdge {
                    output,
                    rule: Some(rule_id),
                    inputs: frame.inputs,
                    witnesses: frame.witnesses,
                })?;
            }
        }
        Ok(())
    }
}
fn bind(atom: &Atom, row: &[Value], prior: &Bindings) -> Option<Bindings> {
    if atom.terms.len() != row.len() {
        return None;
    }
    let mut bindings = prior.clone();
    for (term, value) in atom.terms.iter().zip(row) {
        match term {
            Term::Literal(expected) if expected != value => return None,
            Term::Variable(slot) => {
                if let Some(prior) = bindings.insert(*slot, value.clone())
                    && prior != *value
                {
                    return None;
                }
            }
            _ => (),
        }
    }
    Some(bindings)
}
fn ground(atom: &Atom, bindings: &Bindings) -> Result<Row> {
    atom.terms
        .iter()
        .map(|term| match term {
            Term::Literal(v) => Ok(v.clone()),
            Term::Variable(id) => bindings
                .get(id)
                .cloned()
                .ok_or_else(|| invalid("unbound proof head")),
            Term::Wildcard => Err(invalid("wildcard proof head")),
        })
        .collect::<Result<Vec<_>>>()
        .map(Into::into)
}
pub(super) fn generate(
    program: &Program,
    result: &SourceResult,
    query: &str,
    limits: &ProvenanceLimits,
    cancel: &Cancellation,
) -> Result<ProvenanceGraph> {
    if limits.max_steps == 0
        || limits.max_nodes == 0
        || limits.max_nodes > 4096
        || limits.max_edges == 0
        || limits.max_edges > 65_536
    {
        return Err(invalid("invalid provenance limits"));
    }
    let source_identity = result.identity()?;
    let generation = result.generation()?;
    let empty = |status| ProvenanceGraph::empty(status, source_identity, generation, query);
    if cancel.is_canceled() {
        return Err(Error::Canceled);
    }
    if program.relations.iter().any(|r| r.lattice.is_some()) {
        return Ok(empty(ProvenanceStatus::Unsupported));
    }
    let mut replay = Replay {
        limits,
        cancel,
        start: Instant::now(),
        steps: 0,
        nodes: Vec::new(),
        by_row: BTreeMap::new(),
        relations: BTreeMap::new(),
        initial_occurrences: BTreeSet::new(),
        edges: BTreeSet::new(),
    };
    let replayed = (|| {
        replay.seed(program, result)?;
        replay.closure(program)?;
        if !replay.same_closure(result)? {
            return Ok(false);
        }
        replay.alternatives(program)?;
        replay.step()?;
        Ok(true)
    })();
    match replayed {
        Err(Error::StateLimit) => return Ok(empty(ProvenanceStatus::Bounded)),
        Err(error) => return Err(error),
        Ok(false) => return Ok(empty(ProvenanceStatus::Invalid)),
        Ok(true) => (),
    }
    result.generation()?;
    if cancel.is_canceled() {
        return Err(Error::Canceled);
    }
    let roots = replay.relations[query].clone();
    let status = if roots.is_empty() {
        ProvenanceStatus::ClosedAbsent
    } else {
        ProvenanceStatus::Complete
    };
    Ok(ProvenanceGraph {
        status,
        source_identity,
        checker_version: 3,
        generation,
        query: query.into(),
        nodes: replay.nodes,
        edges: replay.edges.into_iter().collect(),
        roots,
    })
}

fn ground_atom(atom: &Atom, bindings: &Bindings) -> Atom {
    Atom::new(
        &atom.relation,
        atom.terms
            .iter()
            .map(|term| match term {
                Term::Variable(id) => bindings
                    .get(id)
                    .map_or_else(|| term.clone(), |value| Term::Literal(value.clone())),
                _ => term.clone(),
            })
            .collect(),
    )
}
fn reduction(
    operator: crate::Reducer,
    count: usize,
    values: &[Value],
    step: &mut impl FnMut() -> Result<()>,
) -> Result<Option<Value>> {
    use crate::{Reducer, numbers::Number};
    use num_traits::ToPrimitive;
    if operator == Reducer::Count {
        return Ok(Some(Value::Integer(count.into())));
    }
    let mut total = None;
    for value in values {
        step()?;
        let value = Number::read(value)?;
        let units = total
            .as_ref()
            .map_or(1, Number::units)
            .saturating_mul(value.units());
        for _ in 0..units {
            step()?;
        }
        total = Some(match total {
            None => value,
            Some(prior) => match operator {
                Reducer::Sum | Reducer::Mean => prior.add(value),
                Reducer::Min => prior.extreme(value, true),
                Reducer::Max => prior.extreme(value, false),
                Reducer::Count => unreachable!(),
            },
        });
    }
    let result = match (operator, total) {
        (Reducer::Sum, None) => Some(Number::Exact(num_rational::BigRational::from_integer(
            0.into(),
        ))),
        (Reducer::Mean, Some(total)) => Some(Number::Inexact(
            total.inexact() / count.to_f64().ok_or(Error::StateLimit)?,
        )),
        (_, total) => total,
    };
    result.map(Number::value).transpose()
}

fn strata(
    program: &Program,
    step: &mut impl FnMut() -> Result<()>,
) -> Result<BTreeMap<String, usize>> {
    let mut strata = program
        .relations
        .iter()
        .map(|r| (r.name.clone(), 0usize))
        .collect::<BTreeMap<_, _>>();
    for iteration in 0..=program.relations.len() {
        let mut changed = false;
        for rule in &program.rules {
            changed |= raise(rule, &mut strata, step)?;
        }
        if !changed {
            return Ok(strata);
        }
        if iteration == program.relations.len() {
            return Err(invalid("unstratifiable proof"));
        }
    }
    unreachable!()
}

fn raise(
    rule: &crate::Rule,
    strata: &mut BTreeMap<String, usize>,
    step: &mut impl FnMut() -> Result<()>,
) -> Result<bool> {
    let mut changed = false;
    for clause in &rule.body {
        step()?;
        let dependency = match clause {
            Clause::Relation { atom, negative } => Some((&atom.relation, usize::from(*negative))),
            Clause::Reduce { atom, .. } => Some((&atom.relation, 1)),
            _ => None,
        };
        if let Some((source, strict)) = dependency {
            let required = strata[source] + strict;
            let head = strata
                .get_mut(&rule.head.relation)
                .ok_or_else(|| invalid("unknown proof head"))?;
            if *head < required {
                *head = required;
                changed = true;
            }
        }
    }
    Ok(changed)
}
