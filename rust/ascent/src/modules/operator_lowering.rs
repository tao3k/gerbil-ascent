//! Finite operator descriptors lower to the existing checked positive rule graph.
use super::{
    constructors::Admission,
    objects::{Arena, Id, Object, fail},
};
use crate::{Atom, Clause, Program, Relation, Result, Rule, Term, Type};
use num_traits::ToPrimitive;
use std::collections::BTreeMap;
#[derive(Clone)]
pub(super) struct Fragment {
    pub root: Id,
    pub output: String,
    pub program: Program,
    pub exports: BTreeMap<String, String>,
}
pub(super) fn fields(arena: &Arena, id: Id) -> Result<(String, usize, Vec<Id>)> {
    let Object::Record(kind, f) = arena.get(id)? else {
        return Err(fail("operator descriptor required"));
    };
    let Some(arity) = f.first() else {
        return Err(fail("operator signature missing"));
    };
    if !kind.starts_with("op-") {
        return Err(fail("operator descriptor required"));
    }
    let arity = arena
        .integer(*arity)?
        .to_usize()
        .filter(|n| *n <= 128)
        .ok_or_else(|| fail("operator arity bound"))?;
    Ok((kind.clone(), arity, f[1..].to_vec()))
}
pub(super) fn lower(
    arena: &Arena,
    owner: u64,
    root: Id,
    label: &str,
    namespace: Id,
    fresh_sources: bool,
) -> Result<Fragment> {
    let mut lower = Lower {
        arena,
        admission: Admission::new(arena, owner)?,
        program: Program::default(),
        exports: BTreeMap::new(),
        memo: BTreeMap::new(),
        sources: BTreeMap::new(),
        namespace,
        fresh_sources,
        steps: 0,
    };
    let output = lower.node(root, &BTreeMap::new(), 0)?;
    if fresh_sources
        && let Some(old) = lower.exports.insert(label.into(), output.clone())
        && old != output
    {
        return Err(fail("output export conflicts with source label"));
    }
    Ok(Fragment {
        root,
        output,
        program: lower.program,
        exports: lower.exports,
    })
}
type Environment = BTreeMap<Id, String>;
struct Lower<'a> {
    arena: &'a Arena,
    admission: Admission<'a>,
    program: Program,
    exports: BTreeMap<String, String>,
    memo: BTreeMap<(Id, Vec<(Id, String)>), String>,
    sources: BTreeMap<Id, String>,
    namespace: Id,
    fresh_sources: bool,
    steps: usize,
}
impl Lower<'_> {
    fn node(&mut self, id: Id, env: &Environment, depth: usize) -> Result<String> {
        self.steps += 1;
        if depth > 128 || self.steps > 65536 {
            return Err(fail("operator expansion bound"));
        }
        if let Some(name) = env.get(&id) {
            return Ok(name.clone());
        }
        let key = (
            id,
            env.iter().map(|(id, name)| (*id, name.clone())).collect(),
        );
        if let Some(name) = self.memo.get(&key) {
            return Ok(name.clone());
        }
        let (kind, arity, f) = fields(self.arena, id)?;
        let name = format!(
            "relation-handle-{}-{}-{}",
            self.arena.identity,
            self.namespace,
            self.program.relations.len()
        );
        let output = match kind.as_str() {
            "op-source" => self.source(id, arity, &f)?,
            "op-parameter" => return Err(fail("unbound operator parameter")),
            "op-apply" => {
                let input = self.node(f[1], env, depth + 1)?;
                let (parameter, body) = super::operator_values::transformer(self.arena, f[0])?;
                let mut nested = env.clone();
                nested.insert(parameter, input);
                self.node(body, &nested, depth + 1)?
            }
            "op-fix" => {
                self.declare(&name, arity);
                let mut nested = env.clone();
                nested.insert(f[0], name.clone());
                let body = self.node(f[1], &nested, depth + 1)?;
                self.copy_rule(&name, &body, arity);
                name
            }
            _ => {
                self.declare(&name, arity);
                self.operation(&kind, &name, arity, &f, env, depth + 1)?;
                name
            }
        };
        self.memo.insert(key, output.clone());
        Ok(output)
    }
    fn declare(&mut self, name: &str, arity: usize) {
        self.program
            .relations
            .push(Relation::new(name, vec![Type::Scalar; arity], false));
    }
    fn source(&mut self, id: Id, arity: usize, f: &[Id]) -> Result<String> {
        if let Some(name) = self.sources.get(&id) {
            return Ok(name.clone());
        }
        let label = self.admission.name(f[0])?;
        let name = if self.fresh_sources {
            format!(
                "relation-handle-{}-{}-{}",
                self.arena.identity,
                self.namespace,
                self.program.relations.len()
            )
        } else {
            label.clone()
        };
        let mut relation = Relation::new(&name, vec![Type::Scalar; arity], true);
        relation.rows = self.admission.rows(f[1])?;
        if self.exports.insert(label, name.clone()).is_some() {
            return Err(fail("duplicate operator source label"));
        }
        self.program.relations.push(relation);
        self.sources.insert(id, name.clone());
        Ok(name)
    }
    fn copy_rule(&mut self, out: &str, input: &str, arity: usize) {
        let terms = variables(arity, 0);
        self.rule(out, terms.clone(), vec![Atom::new(input, terms)]);
    }
    fn rule(&mut self, out: &str, terms: Vec<Term>, body: Vec<Atom>) {
        self.program.rules.push(Rule {
            head: Atom::new(out, terms),
            body: body.into_iter().map(Clause::positive).collect(),
        });
    }
    fn operation(
        &mut self,
        kind: &str,
        out: &str,
        arity: usize,
        f: &[Id],
        env: &Environment,
        depth: usize,
    ) -> Result<()> {
        let input = self.node(f[0], env, depth)?;
        let input_arity = fields(self.arena, f[0])?.1;
        let terms = variables(input_arity, 0);
        match kind {
            "op-project" => {
                let columns = super::operator_values::columns(self.arena, f[1], input_arity)?;
                self.rule(
                    out,
                    columns.iter().map(|i| terms[*i].clone()).collect(),
                    vec![Atom::new(input, terms)],
                );
            }
            "op-union" => {
                let right = self.node(f[1], env, depth)?;
                self.copy_rule(out, &input, arity);
                self.copy_rule(out, &right, arity);
            }
            "op-select" => {
                let column = super::operator_values::index(self.arena, f[1])?;
                let mut terms = terms;
                terms[column] = Term::Literal(self.arena.freeze(
                    self.arena.identity,
                    super::freeze::snapshot()?,
                    f[2],
                )?);
                self.rule(out, terms.clone(), vec![Atom::new(input, terms)]);
            }
            "op-join" => {
                let right = self.node(f[1], env, depth)?;
                let right_arity = fields(self.arena, f[1])?.1;
                let left_key = super::operator_values::index(self.arena, f[2])?;
                let right_key = super::operator_values::index(self.arena, f[3])?;
                let mut right_terms = variables(right_arity, input_arity);
                right_terms[right_key] = terms[left_key].clone();
                let mut head = terms.clone();
                head.extend(right_terms.clone());
                self.rule(
                    out,
                    head,
                    vec![Atom::new(input, terms), Atom::new(right, right_terms)],
                );
            }
            "op-flatmap" => {
                let table = format!(
                    "relation-handle-{}-{}-{}",
                    self.arena.identity,
                    self.namespace,
                    self.program.relations.len()
                );
                let mut relation =
                    Relation::new(&table, vec![Type::Scalar; input_arity + arity], false);
                relation.auxiliary = true;
                for entry in self.arena.items(f[1])? {
                    let pair = self.arena.items(entry)?;
                    let mut items = self.arena.items(pair[0])?;
                    items.extend(self.arena.items(pair[1])?);
                    relation.rows.push(
                        items
                            .into_iter()
                            .map(|id| self.admission.freeze(id))
                            .collect::<Result<Vec<_>>>()?
                            .into(),
                    );
                }
                self.program.relations.push(relation);
                let output = variables(arity, input_arity);
                let mut lookup = terms.clone();
                lookup.extend(output.clone());
                self.rule(
                    out,
                    output,
                    vec![Atom::new(input, terms), Atom::new(table, lookup)],
                );
            }
            _ => return Err(fail("unsupported operator descriptor")),
        }
        Ok(())
    }
}
fn variables(count: usize, start: usize) -> Vec<Term> {
    (start..start + count)
        .map(|n| Term::Variable(u32::try_from(n).expect("bounded operator arity")))
        .collect()
}
