//! Declarative evidence records retain explicit mutation authority and public relation aliases.
use super::{
    evaluation::Evaluation,
    objects::{EnvId, Id, Object, fail},
};
use crate::{Result, source::Datum};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
fn symbol(name: &str) -> Datum {
    Datum::Atom(name.into())
}
fn quoted(value: Datum) -> Datum {
    Datum::List(vec![symbol("quote"), value])
}
fn bindings(form: &Datum, tag: &str) -> Result<Datum> {
    let Datum::List(items) = form else {
        return Err(fail("evidence bindings required"));
    };
    if items.first() != Some(&symbol(tag)) {
        return Err(fail("sources must be followed by outputs"));
    }
    let mut values = vec![symbol("list")];
    for item in &items[1..] {
        let (label, handle) = match item {
            Datum::Atom(name) => (name.clone(), quoted(item.clone())),
            Datum::List(pair) if pair.len() == 2 => {
                let Datum::Atom(label) = &pair[0] else {
                    return Err(fail("evidence public label required"));
                };
                (
                    label.clone(),
                    if matches!(&pair[1], Datum::Atom(_)) {
                        quoted(pair[1].clone())
                    } else {
                        pair[1].clone()
                    },
                )
            }
            _ => return Err(fail("invalid evidence binding")),
        };
        values.push(Datum::List(vec![
            symbol("cons"),
            quoted(symbol(&label)),
            handle,
        ]));
    }
    Ok(Datum::List(values))
}
impl Evaluation<'_> {
    pub(super) fn define_declared(
        &mut self,
        args: &[Datum],
        env: EnvId,
        depth: usize,
    ) -> Result<Vec<Id>> {
        let [constructor, sources, outputs, clauses @ ..] = args else {
            return Err(fail("sources must be followed by outputs"));
        };
        let source_bindings = bindings(sources, "sources")?;
        let output_bindings = bindings(outputs, "outputs")?;
        let (explain, clauses) = if let Some(Datum::List(items)) = clauses.first()
            && items.first() == Some(&symbol("explain"))
        {
            let [_, value] = items.as_slice() else {
                return Err(fail("one evidence explainer required"));
            };
            (value.clone(), &clauses[1..])
        } else {
            (symbol("recorded-evidence-explanation"), clauses)
        };
        let mut program = vec![symbol("ascent")];
        program.extend_from_slice(clauses);
        let body = Datum::List(vec![
            symbol("make-declared-evidence"),
            Datum::List(program),
            source_bindings,
            output_bindings,
            explain,
        ]);
        self.eval(
            &Datum::List(vec![symbol("def"), constructor.clone(), body]),
            env,
            depth + 1,
        )
    }
    pub(super) fn declared_primitive(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        let [root, sources, outputs, explainer] = args else {
            return Err(fail("declared evidence constructor arity"));
        };
        let Object::Compiled(program, roots) = self.arena.get(*root)?.clone() else {
            return Err(fail("native program required"));
        };
        let sources = self.binding_pairs(*sources)?;
        let outputs = self.binding_pairs(*outputs)?;
        let names = program
            .relations
            .iter()
            .map(|r| r.name.as_str())
            .collect::<BTreeSet<_>>();
        let mut combined = sources.clone();
        for (label, name) in outputs {
            if let Some(prior) = combined.get(&label) {
                if *prior != name {
                    return Err(fail("conflicting public evidence binding"));
                }
            } else {
                if combined.values().any(|n| *n == name) {
                    return Err(fail("duplicate native evidence binding"));
                }
                combined.insert(label, name);
            }
        }
        if combined.values().any(|name| !names.contains(name.as_str())) {
            return Err(fail("evidence binding does not name a declared relation"));
        }
        let source_names = sources.into_values().collect::<BTreeSet<_>>();
        let mut program = (*program).clone();
        for relation in &mut program.relations {
            relation.source = source_names.contains(&relation.name);
        }
        crate::graph::Graph::build(program.clone())?;
        let program = self.arena.add(Object::Compiled(Arc::new(program), roots))?;
        let pairs = combined
            .into_iter()
            .map(|(label, name)| {
                let label = self.arena.symbol(&label, true)?;
                let handle = self.arena.symbol(&name, true)?;
                self.arena.add(Object::Pair(label, handle))
            })
            .collect::<Result<Vec<_>>>()?;
        let aliases = self.arena.list(&pairs)?;
        self.arena
            .add(Object::Record(
                "evidence".into(),
                vec![program, *explainer, aliases],
            ))
            .map(|id| vec![id])
    }
    pub(super) fn recorded_primitive(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        let [program, _, query, scope] = args else {
            return Err(fail("recorded evidence explanation arity"));
        };
        let program = match self.arena.get(*program)?.clone() {
            Object::Compiled(value, _) => self.arena.program_object(&value, *program)?,
            _ => *program,
        };
        let Object::Record(kind, fields) = self.arena.get(program)? else {
            return Err(fail("native explanation program required"));
        };
        if kind != "program" {
            return Err(fail("native explanation program required"));
        }
        let rules = fields[1];
        let status = self.arena.add(Object::Text("recorded-only".into()))?;
        let gap=self.arena.add(Object::Text("Declaration dependencies and current source rows are not per-row proof or execution authority".into()))?;
        let entries = [
            ("status", status),
            ("query", *query),
            ("scope", *scope),
            ("dependencies", rules),
            ("gap", gap),
        ]
        .into_iter()
        .map(|(key, value)| {
            self.arena
                .add(Object::Text(key.into()))
                .map(|key| (key, value))
        })
        .collect::<Result<Vec<_>>>()?;
        self.arena
            .add(Object::Table {
                entries,
                identity: false,
            })
            .map(|id| vec![id])
    }
    fn binding_pairs(&self, root: Id) -> Result<BTreeMap<String, String>> {
        let mut pairs = BTreeMap::new();
        let mut handles = BTreeSet::new();
        for pair in self.arena.items(root)? {
            let Object::Pair(label, handle) = self.arena.get(pair)? else {
                return Err(fail("evidence binding pair required"));
            };
            let label = self.arena.checked_name(*label)?;
            let handle = self.arena.checked_name(*handle)?;
            if !handles.insert(handle.clone()) || pairs.insert(label, handle).is_some() {
                return Err(fail("duplicate evidence binding"));
            }
        }
        Ok(pairs)
    }
}
