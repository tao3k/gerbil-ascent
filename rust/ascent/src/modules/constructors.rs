//! Admit native Scheme constructor records into the same checked relational graph.
use super::objects::{Arena, Id, Object, fail};
use crate::{Atom, FactLimits, Program, Relation, Result, Row, Rule, Term, Type};
use num_traits::ToPrimitive;
use std::collections::{BTreeMap, BTreeSet};
pub(super) struct Admission<'a> {
    pub arena: &'a Arena,
    pub owner: u64,
    snapshot: u64,
    cache: std::cell::RefCell<BTreeMap<Id, crate::Value>>,
}
impl<'a> Admission<'a> {
    pub fn new(arena: &'a Arena, owner: u64) -> Result<Self> {
        Ok(Self {
            arena,
            owner,
            snapshot: super::freeze::snapshot()?,
            cache: std::cell::RefCell::new(BTreeMap::new()),
        })
    }
    pub(super) fn freeze(&self, id: Id) -> Result<crate::Value> {
        if let Some(value) = self.cache.borrow().get(&id) {
            return Ok(value.clone());
        }
        let value = self.arena.freeze(self.owner, self.snapshot, id)?;
        self.cache.borrow_mut().insert(id, value.clone());
        Ok(value)
    }
    pub fn record(&self, id: Id, kind: &str, count: usize) -> Result<Vec<Id>> {
        match self.arena.get(id)? {
            Object::Record(name, fields) if name == kind && fields.len() == count => {
                Ok(fields.clone())
            }
            _ => Err(fail(&format!("expected {kind} constructor"))),
        }
    }
    pub fn name(&self, id: Id) -> Result<String> {
        self.arena.checked_name(id)
    }
    fn limit(&self, id: Id) -> Result<Option<usize>> {
        if matches!(self.arena.get(id)?, Object::Boolean(false))
            || matches!(self.arena.get(id)?, Object::Inexact(value) if *value==f64::INFINITY)
        {
            return Ok(None);
        }
        self.arena
            .integer(id)?
            .to_usize()
            .filter(|n| *n > 0)
            .map(Some)
            .ok_or_else(|| fail("positive fact limit required"))
    }
    pub fn rows(&self, id: Id) -> Result<Vec<Row>> {
        self.arena
            .items(id)?
            .into_iter()
            .map(|row| {
                self.arena
                    .items(row)?
                    .into_iter()
                    .map(|cell| self.freeze(cell))
                    .collect::<Result<Vec<_>>>()
                    .map(Into::into)
            })
            .collect()
    }
    pub fn program(&self, id: Id) -> Result<Program> {
        if let Object::Compiled(program, _) = self.arena.get(id)? {
            return Ok((**program).clone());
        }
        let fields = self.record(id, "program", 6)?;
        let source_names = self.arena.items(fields[5])?;
        let sources = source_names
            .iter()
            .copied()
            .map(|id| self.name(id))
            .collect::<Result<BTreeSet<_>>>()?;
        if sources.len() != source_names.len() {
            return Err(fail("duplicate source authority"));
        }
        let relations = self
            .arena
            .items(fields[0])?
            .into_iter()
            .map(|id| self.relation(id, &sources))
            .collect::<Result<Vec<_>>>()?;
        if sources
            .iter()
            .any(|name| !relations.iter().any(|r| &r.name == name))
        {
            return Err(fail("unknown source authority"));
        }
        let rules = self
            .arena
            .items(fields[1])?
            .into_iter()
            .map(|id| self.rules(id))
            .collect::<Result<Vec<_>>>()?
            .into_iter()
            .flatten()
            .collect();
        Ok(Program {
            relation_limit: None,
            relations,
            rules,
            fact_limits: FactLimits {
                input: self.limit(fields[2])?,
                derived: self.limit(fields[3])?,
                output: self.limit(fields[4])?,
            },
        })
    }
    fn relation(&self, id: Id, sources: &BTreeSet<String>) -> Result<Relation> {
        if let Object::Relation(relation, _) = self.arena.get(id)? {
            let mut relation = relation.clone();
            relation.source = sources.contains(&relation.name);
            return Ok(relation);
        }
        let (f, lattice) = match self.arena.get(id)? {
            Object::Record(kind, f) if kind == "lattice" && f.len() == 4 => {
                let mode = match self.arena.get(f[3])? {
                    Object::Procedure(super::objects::Procedure::Builtin("min")) => {
                        crate::LatticeJoin::Min
                    }
                    Object::Procedure(super::objects::Procedure::Builtin("max")) => {
                        crate::LatticeJoin::Max
                    }
                    _ => {
                        return Err(fail(
                            "lattice join requires a supported Rust-lowered numeric semilattice",
                        ));
                    }
                };
                (f[..3].to_vec(), Some(mode))
            }
            _ => (self.record(id, "relation", 3)?, None),
        };
        let name = self.name(f[0])?;
        let arity = self
            .arena
            .integer(f[1])?
            .to_usize()
            .filter(|n| *n <= 128)
            .ok_or_else(|| fail("relation arity bound"))?;
        let mut relation = Relation::new(&name, vec![Type::Any; arity], sources.contains(&name));
        relation.lattice = lattice;
        relation.rows = self.rows(f[2])?;
        Ok(relation)
    }
    fn rules(&self, id: Id) -> Result<Vec<Rule>> {
        if let Object::Rule(rule, _) = self.arena.get(id)? {
            return Ok(vec![rule.clone()]);
        }
        let mut rules = Vec::new();
        let f = self.record(id, "rule", 2)?;
        let mut variables = BTreeMap::new();
        let body = self
            .arena
            .items(f[1])?
            .into_iter()
            .map(|id| self.clause(id, &mut variables))
            .collect::<Result<Vec<_>>>()?;
        for head in self.arena.items(f[0])? {
            rules.push(Rule {
                head: self.atom(head, &mut variables)?,
                body: body.clone(),
            });
        }
        Ok(rules)
    }
    pub(super) fn atom(&self, id: Id, variables: &mut BTreeMap<String, u32>) -> Result<Atom> {
        let f = self.record(id, "atom", 2)?;
        self.atom_fields(&f, variables)
    }
    pub(super) fn atom_fields(
        &self,
        f: &[Id],
        variables: &mut BTreeMap<String, u32>,
    ) -> Result<Atom> {
        let terms = self
            .arena
            .items(f[1])?
            .into_iter()
            .map(|id| {
                if let Object::Record(kind, fields) = self.arena.get(id)?
                    && kind == "variable"
                    && fields.len() == 1
                {
                    let name = self.name(fields[0])?;
                    let next =
                        u32::try_from(variables.len()).map_err(|_| fail("variable bound"))?;
                    Ok(Term::Variable(*variables.entry(name).or_insert(next)))
                } else {
                    Ok(Term::Literal(self.arena.freeze(
                        self.owner,
                        self.snapshot,
                        id,
                    )?))
                }
            })
            .collect::<Result<_>>()?;
        Ok(Atom::new(self.name(f[0])?, terms))
    }
}
