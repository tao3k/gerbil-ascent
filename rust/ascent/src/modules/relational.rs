//! Module-level lifecycle operations use the same Rust session and snapshots.
use super::{
    constructors::Admission,
    evaluation::Evaluation,
    objects::{Arena, Id, Object, Procedure, fail},
    operator_values::{self, count},
};
use crate::{Cancellation, FactLimits, Program, Result, SourceSession};
use num_traits::ToPrimitive;
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex},
};
pub(super) const EXPORTS: &[&str] = &[
    "relational-compose",
    "relational-export",
    "relational-admit",
    "relational-solve",
    "relational-open-session",
    "relational-open-program-session",
    "gerbil-ascent-open-session",
    "relational-session-run",
    "gerbil-ascent-session-run",
    "gerbil-ascent-session-run-timeout",
    "relational-session-replace-source!",
    "gerbil-ascent-session-replace-source!",
    "relational-query",
    "relational-query-name",
    "relational-program-query",
    "relational-prepare-query",
    "evidence-module-program",
];
pub(super) fn limits(arena: &Arena, args: &[Id]) -> Result<FactLimits> {
    if args.len() > 3 {
        return Err(fail("fact limit argument count"));
    }
    let mut limits = [None; 3];
    for (target, value) in limits.iter_mut().zip(args) {
        if matches!(arena.get(*value)?,Object::Inexact(n) if *n==f64::INFINITY) {
            continue;
        }
        *target = Some(
            arena
                .integer(*value)?
                .to_usize()
                .filter(|n| *n > 0)
                .ok_or_else(|| fail("positive fact limit required"))?,
        );
    }
    Ok(FactLimits {
        input: limits[0],
        derived: limits[1],
        output: limits[2],
    })
}
pub(super) fn export(arena: &Arena, fragment: Id, label: Id) -> Result<String> {
    let Object::Fragment(fragment) = arena.get(fragment)? else {
        return Err(fail("fragment required"));
    };
    let name = Admission::new(arena, arena.identity)?.name(label)?;
    fragment
        .exports
        .get(&name)
        .cloned()
        .ok_or_else(|| fail("unknown fragment export"))
}
impl Evaluation<'_> {
    pub(super) fn relational(&mut self, name: &str, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        let id = match name {
            "relational-compose" => self.compose(args)?,
            "relational-export" => {
                count(args, 2)?;
                let name = export(self.arena, args[0], args[1])?;
                self.arena.relation_name(&name)?
            }
            "evidence-module-program" => {
                count(args, 1)?;
                let Object::Record(kind, fields) = self.arena.get(args[0])? else {
                    return Err(fail("evidence module required"));
                };
                if kind != "evidence" {
                    return Err(fail("evidence module required"));
                }
                fields[0]
            }
            "relational-admit" => {
                count(args, 1)?;
                let program = Admission::new(self.arena, self.arena.identity)?.program(args[0])?;
                checked(&program)?;
                self.engine.open(program.clone())?;
                self.arena
                    .add(Object::Compiled(Arc::new(program), vec![args[0]]))?
            }
            "relational-solve" => {
                count(args, 1)?;
                let program = Admission::new(self.arena, self.arena.identity)?.program(args[0])?;
                checked(&program)?;
                let mut session = self.engine.open(program)?;
                let snapshot =
                    session.run(&SourceSession::default_limits(), &Cancellation::default())?;
                self.arena.add(Object::Completed(snapshot, vec![args[0]]))?
            }
            "relational-open-session"
            | "relational-open-program-session"
            | "gerbil-ascent-open-session" => {
                count(args, 1)?;
                let program = Admission::new(self.arena, self.arena.identity)?.program(args[0])?;
                if name != "gerbil-ascent-open-session" {
                    checked(&program)?;
                }
                let session = self.engine.open(program)?;
                self.arena.add(Object::Execution(
                    Arc::new(Mutex::new(session)),
                    BTreeMap::from([(String::new(), args[0])]),
                ))?
            }
            "relational-session-run"
            | "gerbil-ascent-session-run"
            | "gerbil-ascent-session-run-timeout" => self.run_session(name, args)?,
            "relational-session-replace-source!" | "gerbil-ascent-session-replace-source!" => {
                self.replace_session(name, args, depth)?;
                self.arena.add(Object::Void)?
            }
            "relational-prepare-query" => {
                count(args, 2)?;
                let name = export(self.arena, args[0], args[1])?;
                self.arena.add(Object::Procedure(Procedure::Query(name)))?
            }
            "relational-query" => {
                count(args, 3)?;
                let name = export(self.arena, args[1], args[2])?;
                self.query(args[0], &name)?
            }
            "relational-query-name" | "relational-program-query" => {
                count(args, 2)?;
                let name = Admission::new(self.arena, self.arena.identity)?.name(args[1])?;
                self.query(args[0], &name)?
            }
            _ => return Err(fail("unknown relational lifecycle procedure")),
        };
        Ok(vec![id])
    }
    fn compose(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 4)?;
        let fact_limits = limits(self.arena, &args[1..])?;
        let mut program = Program {
            fact_limits,
            ..Program::default()
        };
        let roots = self.arena.items(args[0])?;
        let mut seen = BTreeSet::new();
        for root in &roots {
            if !seen.insert(*root) {
                continue;
            }
            let Object::Fragment(fragment) = self.arena.get(*root)? else {
                return Err(fail("compose requires fragments"));
            };
            program
                .relations
                .extend(fragment.program.relations.iter().cloned());
            program.rules.extend(fragment.program.rules.iter().cloned());
        }
        self.engine.open(program.clone())?;
        self.arena.add(Object::Compiled(Arc::new(program), roots))
    }
    fn run_session(&mut self, name: &str, args: &[Id]) -> Result<Id> {
        count(
            args,
            if name == "gerbil-ascent-session-run-timeout" {
                2
            } else {
                1
            },
        )?;
        let Object::Execution(session, roots) = self.arena.get(args[0])?.clone() else {
            return Err(fail("session required"));
        };
        let mut limits = SourceSession::default_limits();
        if args.len() == 2 {
            let nanos = self
                .arena
                .integer(args[1])?
                .to_u64()
                .ok_or_else(|| fail("nonnegative deadline required"))?;
            limits.timeout = std::time::Duration::from_nanos(nanos);
        }
        let snapshot = session
            .lock()
            .map_err(|_| fail("session lock poisoned"))?
            .run(&limits, &Cancellation::default())?;
        self.arena
            .add(Object::Completed(snapshot, roots.into_values().collect()))
    }
    fn query(&mut self, solution: Id, name: &str) -> Result<Id> {
        let Object::Completed(snapshot, _) = self.arena.get(solution)?.clone() else {
            return Err(fail("completed solution required"));
        };
        let rows = snapshot
            .relations
            .get(name)
            .ok_or_else(|| fail("unknown or foreign solution query"))?;
        self.arena.rows_object(rows)
    }
    fn replace_session(&mut self, name: &str, args: &[Id], depth: usize) -> Result<()> {
        count(
            args,
            if name == "relational-session-replace-source!" {
                4
            } else {
                3
            },
        )?;
        let (relation, rows) = if args.len() == 4 {
            (export(self.arena, args[1], args[2])?, args[3])
        } else {
            (
                Admission::new(self.arena, self.arena.identity)?.name(args[1])?,
                args[2],
            )
        };
        let Object::Execution(session, mut roots) = self.arena.get(args[0])?.clone() else {
            return Err(fail("session required"));
        };
        let values = Admission::new(self.arena, self.arena.identity)?.rows(rows)?;
        let mut owner = session.lock().map_err(|_| fail("session lock poisoned"))?;
        if name == "relational-session-replace-source!" {
            let declaration = owner
                .program()
                .relations
                .iter()
                .find(|r| r.name == relation)
                .ok_or_else(|| fail("unknown source handle"))?;
            operator_values::rows(self.arena, rows, declaration.columns.len())?;
        }
        let mut candidate = owner.clone();
        candidate.replace_sources(BTreeMap::from([(relation.clone(), values)]))?;
        candidate.run(&SourceSession::default_limits(), &Cancellation::default())?;
        self.check(depth)?;
        *owner = candidate;
        roots.insert(relation, rows);
        self.arena
            .objects
            .insert(args[0], Object::Execution(session.clone(), roots));
        Ok(())
    }
}
fn checked(program: &Program) -> Result<()> {
    if program.relations.iter().any(|r| r.lattice.is_some()) {
        Err(fail("untrusted relational lattice"))
    } else {
        Ok(())
    }
}
