//! Prepared insertion and retained operator owners execute through Rust sessions.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, fail},
    operator_lowering,
    operator_values::{arity, count, index, transformer},
};
use crate::{Cancellation, Program, Result, Row, SourceSession};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::{Arc, Mutex},
};
pub(super) const EXPORTS: &[&str] = &[
    "relational-op-prepare-change",
    "relational-op-change",
    "relational-op-delta-change",
    "relational-op-open-retained",
    "relational-op-retained-replace!",
    "relational-op-retained-rows",
];
impl Evaluation<'_> {
    pub(super) fn operator_change(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        match name {
            "relational-op-prepare-change" => {
                count(args, 1)?;
                self.check_transformer(args[0])?;
                self.arena
                    .add(Object::Record("change".into(), vec![args[0]]))
                    .map(|id| vec![id])
            }
            "relational-op-change" | "relational-op-delta-change" => {
                if !(3..=4).contains(&args.len()) {
                    return Err(fail("operator change arity"));
                }
                let transformer = if name == "relational-op-change" {
                    let Object::Record(kind, f) = self.arena.get(args[0])? else {
                        return Err(fail("prepared change required"));
                    };
                    if kind != "change" {
                        return Err(fail("prepared change required"));
                    }
                    f[0]
                } else {
                    args[0]
                };
                self.change(transformer, args, depth)
            }
            "relational-op-open-retained" => {
                count(args, 5)?;
                let limits = super::relational::limits(self.arena, &args[2..])?;
                let (mut program, input, output, root) =
                    self.transform_program(args[0], args[1])?;
                program.fact_limits = limits;
                let mut session = self.engine.open(program)?;
                session.run(&SourceSession::default_limits(), &Cancellation::default())?;
                let session = self.arena.add(Object::Execution(
                    Arc::new(Mutex::new(session)),
                    BTreeMap::from([(String::new(), root), (input.clone(), args[1])]),
                ))?;
                let input = self.arena.relation_name(&input)?;
                let output = self.arena.relation_name(&output)?;
                self.arena
                    .add(Object::Record(
                        "retained".into(),
                        vec![session, input, output],
                    ))
                    .map(|id| vec![id])
            }
            "relational-op-retained-replace!" => {
                count(args, 2)?;
                let fields = self.retained(args[0])?;
                self.relational(
                    "gerbil-ascent-session-replace-source!",
                    &[fields[0], fields[1], args[1]],
                    depth,
                )?;
                self.arena.add(Object::Void).map(|id| vec![id])
            }
            "relational-op-retained-rows" => {
                count(args, 1)?;
                let fields = self.retained(args[0])?;
                let solution = self.relational("relational-session-run", &[fields[0]], depth)?[0];
                self.relational("relational-query-name", &[solution, fields[2]], depth)
            }
            _ => Err(fail("unknown operator owner procedure")),
        }
    }
    fn retained(&self, id: Id) -> Result<Vec<Id>> {
        match self.arena.get(id)? {
            Object::Record(kind, f) if kind == "retained" && f.len() == 3 => Ok(f.clone()),
            _ => Err(fail("retained operator required")),
        }
    }
    fn check_transformer(&mut self, id: Id) -> Result<()> {
        let (parameter, _) = transformer(self.arena, id)?;
        let size = arity(self.arena, parameter)?;
        let empty = self.arena.list(&[])?;
        self.transform_program(id, empty).map(|_| ())?;
        if size > 128 {
            return Err(fail("transformer input arity bound"));
        }
        Ok(())
    }
    fn transform_program(
        &mut self,
        transform: Id,
        rows: Id,
    ) -> Result<(Program, String, String, Id)> {
        let (parameter, body) = transformer(self.arena, transform)?;
        let input_arity = arity(self.arena, parameter)?;
        let size = self
            .arena
            .add(Object::Number(num_rational::BigRational::from_integer(
                input_arity.into(),
            )))?;
        let nonce = self.arena.add(Object::Void)?;
        let source_label = format!("relation-handle-{}-{}-input", self.arena.identity, nonce);
        let name = self.arena.relation_name(&source_label)?;
        let source = self.operator("relational-op-source", &[name, size, rows], 0)?[0];
        let output_size =
            self.arena
                .add(Object::Number(num_rational::BigRational::from_integer(
                    arity(self.arena, body)?.into(),
                )))?;
        let apply = self.arena.add(Object::Record(
            "op-apply".into(),
            vec![output_size, transform, source],
        ))?;
        let namespace = self.arena.add(Object::Void)?;
        let fragment = operator_lowering::lower(
            self.arena,
            self.arena.identity,
            apply,
            "change-output",
            namespace,
            false,
        )?;
        Ok((
            fragment.program,
            fragment.exports[&source_label].clone(),
            fragment.output,
            apply,
        ))
    }
    fn change(&mut self, transform: Id, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        let (mut program, input, output, _) = self.transform_program(transform, args[1])?;
        let limit = if args.len() == 4 {
            let limit = index(self.arena, args[3])?;
            if limit == 0 {
                return Err(fail("positive delta row limit required"));
            }
            Some(limit)
        } else {
            None
        };
        program.relation_limit = limit;
        let mut session = self.engine.open(program)?;
        let limits = SourceSession::default_limits();
        let cancel = Cancellation::default();
        let old = session.run(&limits, &cancel)?;
        let old_rows = old.relations[&output].clone();
        let size = session
            .program()
            .relations
            .iter()
            .find(|r| r.name == input)
            .ok_or_else(|| fail("transformer source missing"))?
            .columns
            .len();
        super::operator_values::rows(self.arena, args[2], size)?;
        let admission = super::constructors::Admission::new(self.arena, self.arena.identity)?;
        let mut rows = admission.rows(args[1])?;
        rows.extend(admission.rows(args[2])?);
        session.replace_sources(BTreeMap::from([(input, rows)]))?;
        let grown = session.run(&limits, &cancel)?;
        let grown_rows = grown.relations[&output].clone();
        self.check(depth)?;
        let known = old_rows.iter().cloned().collect::<BTreeSet<Row>>();
        let delta = grown_rows
            .iter()
            .filter(|r| !known.contains(*r))
            .cloned()
            .collect::<Vec<_>>();
        [old_rows, grown_rows, delta]
            .iter()
            .map(|rows| self.arena.rows_object(rows))
            .collect()
    }
}
