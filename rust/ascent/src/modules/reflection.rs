//! Owned native field observations preserve genuine program/session data.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, Procedure, fail},
    operator_values::count,
};
use crate::Result;
use num_rational::BigRational;
impl Evaluation<'_> {
    pub(super) fn reference_primitive(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        count(args, 2)?;
        let Object::Symbol(field, _) = self.arena.get(args[1])?.clone() else {
            return Err(fail("record field symbol required"));
        };
        if let Object::Completed(snapshot, roots) = self.arena.get(args[0])?.clone() {
            if field == "rows-of" {
                return self
                    .arena
                    .add(Object::Procedure(Procedure::Rows(snapshot, roots)))
                    .map(|id| vec![id]);
            }
            if field == "finished" {
                return self.arena.add(Object::Boolean(true)).map(|id| vec![id]);
            }
            return Err(fail("unknown completed result field"));
        }
        let receiver = if let Object::Compiled(program, _) = self.arena.get(args[0])?.clone() {
            self.arena.program_object(&program, args[0])?
        } else {
            args[0]
        };
        if let Object::Relation(relation, _) = self.arena.get(receiver)?.clone() {
            let id = match field.as_str() {
                "name" => self.arena.relation_name(&relation.name)?,
                "arity" => self.arena.add(Object::Number(BigRational::from_integer(
                    relation.columns.len().into(),
                )))?,
                "rows" => self.arena.rows_object(&relation.rows)?,
                _ => return Err(fail("unknown relation field")),
            };
            return Ok(vec![id]);
        }
        let Object::Record(kind, fields) = self.arena.get(receiver)? else {
            return Err(fail("record required"));
        };
        let names: &[&str] = match kind.as_str() {
            "program" => &[
                "relations",
                "rules",
                "max-input-facts",
                "max-derived-facts",
                "max-output-facts",
                "source-handles",
            ],
            "relation" => &["name", "arity", "rows"],
            "result" => &["rows-of"],
            _ => return Err(fail("record has no public fields")),
        };
        let index = names
            .iter()
            .position(|name| *name == field)
            .ok_or_else(|| fail("unknown record field"))?;
        Ok(vec![fields[index]])
    }
}
