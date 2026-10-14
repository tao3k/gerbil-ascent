//! Immutable finite type records and set domains carry structural signatures.
use crate::modules::{
    Arena, Evaluation, Id, Object, fail, operator_count as count, operator_index as index,
};
use crate::{Result, Value};
use std::collections::BTreeSet;
pub(in crate::modules) const EXPORTS: &[&str] = &[
    "relational-relation-type",
    "relational-arrow-type",
    "relational-type?",
    "relational-type=?",
    "relational-type-height-expression",
    "relational-type-kind",
    "relational-type-left",
    "relational-type-right",
    "relational-typed-term-kind",
    "relational-typed-term-inputs",
    "relational-typed-term-data",
    "relational-typed-source",
    "relational-typed-function",
    "relational-typed-apply",
    "relational-typed-union",
    "relational-typed-join",
    "relational-typed-project",
    "relational-typed-select-eq",
    "relational-typed-flatmap",
    "relational-typed-fix",
    "relational-typed-term?",
    "relational-typed-term-type",
    "relational-typed-compile",
];
pub(super) fn record(arena: &Arena, id: Id, kind: &str, len: usize) -> Result<Vec<Id>> {
    match arena.get(id)? {
        Object::Record(tag, fields) if tag == kind && fields.len() == len => Ok(fields.clone()),
        _ => Err(fail("finite typed descriptor required")),
    }
}
pub(super) fn signature(arena: &Arena, id: Id) -> Result<Vec<Id>> {
    record(arena, id, "finite-type", 3)
}
pub(super) fn term(arena: &Arena, id: Id) -> Result<Vec<Id>> {
    record(arena, id, "typed-term", 4)
}
pub(super) fn kind(arena: &Arena, id: Id) -> Result<String> {
    arena.checked_name(id)
}
pub(super) fn relation(arena: &Arena, id: Id) -> Result<(usize, Id)> {
    let fields = signature(arena, id)?;
    if kind(arena, fields[0])? != "relation" {
        return Err(fail("finite relation type required"));
    }
    Ok((index(arena, fields[1])?, fields[2]))
}
pub(super) fn equal(arena: &Arena, left: Id, right: Id) -> Result<bool> {
    fn visit(arena: &Arena, left: Id, right: Id, depth: usize) -> Result<bool> {
        if depth > 128 {
            return Err(fail("finite type depth bound"));
        }
        let l = signature(arena, left)?;
        let r = signature(arena, right)?;
        if kind(arena, l[0])? != kind(arena, r[0])? {
            return Ok(false);
        }
        if kind(arena, l[0])? == "relation" {
            return Ok(index(arena, l[1])? == index(arena, r[1])?
                && domain(arena, l[2])? == domain(arena, r[2])?);
        }
        Ok(visit(arena, l[1], r[1], depth + 1)? && visit(arena, l[2], r[2], depth + 1)?)
    }
    visit(arena, left, right, 0)
}
pub(super) fn domain(arena: &Arena, id: Id) -> Result<BTreeSet<Value>> {
    let admission = crate::modules::Admission::new(arena, arena.identity)?;
    arena
        .items(id)?
        .into_iter()
        .map(|id| {
            crate::modules::operator_scalar(arena, id)?;
            admission.freeze(id)
        })
        .collect()
}
impl Evaluation<'_> {
    pub(in crate::modules) fn typed(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        match name {
            "relational-relation-type" => {
                count(args, 2)?;
                self.finite_relation_type(args[0], args[1])
                    .map(|id| vec![id])
            }
            "relational-arrow-type" => {
                count(args, 2)?;
                self.finite_arrow_type(args[0], args[1]).map(|id| vec![id])
            }
            "relational-type?" | "relational-typed-term?" => {
                count(args, 1)?;
                let valid = if name == "relational-type?" {
                    signature(self.arena, args[0]).is_ok()
                } else {
                    term(self.arena, args[0]).is_ok()
                };
                self.arena.add(Object::Boolean(valid)).map(|id| vec![id])
            }
            "relational-type=?" => {
                count(args, 2)?;
                let valid = equal(self.arena, args[0], args[1])?;
                self.arena.add(Object::Boolean(valid)).map(|id| vec![id])
            }
            "relational-type-kind" | "relational-type-left" | "relational-type-right" => {
                self.type_field(name, args)
            }
            "relational-typed-term-kind"
            | "relational-typed-term-inputs"
            | "relational-typed-term-data"
            | "relational-typed-term-type" => self.term_field(name, args),
            "relational-type-height-expression" => {
                count(args, 1)?;
                self.height_expression(args[0], 0).map(|id| vec![id])
            }
            "relational-typed-compile" => self.normalize_typed(args, depth),
            _ => self.typed_constructor(name, args, depth),
        }
    }
    pub(super) fn finite_relation_type(&mut self, arity: Id, atoms: Id) -> Result<Id> {
        if index(self.arena, arity)? > 128 || self.arena.items(atoms)?.len() > 4096 {
            return Err(fail("finite relation type bound"));
        }
        let values = domain(self.arena, atoms)?;
        let atoms = self.arena.rows_object(
            &values
                .into_iter()
                .map(|v| std::sync::Arc::from([v]))
                .collect::<Vec<crate::Row>>(),
        )?;
        let rows = self.arena.items(atoms)?;
        let cells = rows
            .into_iter()
            .map(|r| self.arena.items(r).map(|v| v[0]))
            .collect::<Result<Vec<_>>>()?;
        let atoms = self.arena.list(&cells)?;
        let kind = self.arena.symbol("relation", true)?;
        self.arena.add(Object::Record(
            "finite-type".into(),
            vec![kind, arity, atoms],
        ))
    }
    pub(super) fn finite_arrow_type(&mut self, input: Id, output: Id) -> Result<Id> {
        signature(self.arena, input)?;
        signature(self.arena, output)?;
        let kind = self.arena.symbol("arrow", true)?;
        self.arena.add(Object::Record(
            "finite-type".into(),
            vec![kind, input, output],
        ))
    }
    fn type_field(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        count(args, 1)?;
        let fields = signature(self.arena, args[0])?;
        let index = match name {
            "relational-type-kind" => 0,
            "relational-type-left" => 1,
            _ => 2,
        };
        let value = if index == 2 && kind(self.arena, fields[0])? == "relation" {
            let values = self.arena.items(fields[2])?;
            self.arena.list(&values)?
        } else {
            fields[index]
        };
        Ok(vec![value])
    }
    fn term_field(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        count(args, 1)?;
        let fields = term(self.arena, args[0])?;
        let index = match name {
            "relational-typed-term-type" => 0,
            "relational-typed-term-kind" => 1,
            "relational-typed-term-inputs" => 2,
            _ => 3,
        };
        // Construction metadata is not a mutable backdoor into an admitted term.
        let value = if index >= 2 {
            self.copy_metadata(fields[index], 0)?
        } else {
            fields[index]
        };
        Ok(vec![value])
    }
    fn copy_metadata(&mut self, id: Id, depth: usize) -> Result<Id> {
        self.check(depth)?;
        let object = match self.arena.get(id)?.clone() {
            Object::Pair(_, _) => return self.copy_metadata_pairs(id, depth),
            Object::Vector(values) => Object::Vector(
                values
                    .into_iter()
                    .map(|v| self.copy_metadata(v, depth + 1))
                    .collect::<Result<Vec<_>>>()?,
            ),
            _ => return Ok(id),
        };
        self.arena.add(object)
    }
    fn copy_metadata_pairs(&mut self, root: Id, depth: usize) -> Result<Id> {
        let mut values = Vec::new();
        let mut tail = root;
        let mut seen = BTreeSet::new();
        while let Object::Pair(head, next) = self.arena.get(tail)?.clone() {
            self.check(depth)?;
            if !seen.insert(tail) {
                return Err(fail("cyclic typed metadata"));
            }
            values.push(self.copy_metadata(head, depth + 1)?);
            tail = next;
        }
        let mut result = self.copy_metadata(tail, depth + 1)?;
        for value in values.into_iter().rev() {
            result = self.arena.add(Object::Pair(value, result))?;
        }
        Ok(result)
    }
    fn expression(&mut self, operator: &str, left: Id, right: Id) -> Result<Id> {
        let operator = self.arena.symbol(operator, true)?;
        self.arena.list(&[operator, left, right])
    }
    fn cardinality_expression(&mut self, ty: Id, depth: usize) -> Result<Id> {
        self.check(depth)?;
        let fields = signature(self.arena, ty)?;
        if kind(self.arena, fields[0])? == "relation" {
            let height = self.height_expression(ty, depth + 1)?;
            let two = self
                .arena
                .add(Object::Number(num_rational::BigRational::from_integer(
                    2.into(),
                )))?;
            self.expression("expt", two, height)
        } else {
            let left = self.cardinality_expression(fields[1], depth + 1)?;
            let right = self.cardinality_expression(fields[2], depth + 1)?;
            self.expression("expt", right, left)
        }
    }
    fn height_expression(&mut self, ty: Id, depth: usize) -> Result<Id> {
        self.check(depth)?;
        let fields = signature(self.arena, ty)?;
        if kind(self.arena, fields[0])? == "relation" {
            let domain = self.arena.items(fields[2])?.len();
            let domain =
                self.arena
                    .add(Object::Number(num_rational::BigRational::from_integer(
                        domain.into(),
                    )))?;
            self.expression("expt", domain, fields[1])
        } else {
            let input = self.cardinality_expression(fields[1], depth + 1)?;
            let output = self.height_expression(fields[2], depth + 1)?;
            self.expression("*", input, output)
        }
    }
}
