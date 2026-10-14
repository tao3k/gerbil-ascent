//! Construction freezes finite domains and rows, and executes each descriptor builder once.
use super::types::{domain, equal, kind, relation, signature, term};
use crate::Result;
use crate::modules::{
    Admission, Evaluation, Id, Object, fail, operator_count as count, operator_index as index,
};
impl Evaluation<'_> {
    pub(super) fn typed_node(&mut self, ty: Id, kind: &str, inputs: &[Id], data: Id) -> Result<Id> {
        let kind = self.arena.symbol(kind, true)?;
        let inputs = self.arena.list(inputs)?;
        self.arena.add(Object::Record(
            "typed-term".into(),
            vec![ty, kind, inputs, data],
        ))
    }
    pub(super) fn term_type(&self, id: Id) -> Result<Id> {
        term(self.arena, id).map(|f| f[0])
    }
    pub(super) fn typed_constructor(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        let id = match name {
            "relational-typed-source" => self.typed_source(args)?,
            "relational-typed-function" => self.typed_function(args, depth)?,
            "relational-typed-apply" => self.typed_apply(args)?,
            "relational-typed-fix" => self.typed_fix(args)?,
            "relational-typed-union" => self.typed_union(args)?,
            "relational-typed-join" => self.typed_join(args)?,
            "relational-typed-project" => self.typed_project(args)?,
            "relational-typed-select-eq" => self.typed_select(args)?,
            "relational-typed-flatmap" => self.typed_flatmap(args)?,
            _ => return Err(fail("unknown finite typed constructor")),
        };
        Ok(vec![id])
    }
    fn typed_source(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 3)?;
        self.arena.checked_name(args[0])?;
        let rows = self.checked_domain_rows(args[1], args[2])?;
        let data = self.arena.add(Object::Vector(vec![args[0], rows]))?;
        self.typed_node(args[1], "source", &[], data)
    }
    fn typed_function(&mut self, args: &[Id], depth: usize) -> Result<Id> {
        count(args, 2)?;
        signature(self.arena, args[0])?;
        let none = self.arena.add(Object::Boolean(false))?;
        let parameter = self.typed_node(args[0], "parameter", &[], none)?;
        let values = self.apply(args[1], &[parameter], depth + 1)?;
        let [body] = values.as_slice() else {
            return Err(fail("typed builder must return one descriptor"));
        };
        let output = self.term_type(*body)?;
        let ty = self.finite_arrow_type(args[0], output)?;
        self.typed_node(ty, "function", &[*body], parameter)
    }
    fn typed_apply(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 2)?;
        let fields = signature(self.arena, self.term_type(args[0])?)?;
        if kind(self.arena, fields[0])? != "arrow"
            || !equal(self.arena, fields[1], self.term_type(args[1])?)?
        {
            return Err(fail("typed application signature mismatch"));
        }
        let none = self.arena.add(Object::Boolean(false))?;
        self.typed_node(fields[2], "apply", args, none)
    }
    fn typed_fix(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 1)?;
        let fields = signature(self.arena, self.term_type(args[0])?)?;
        if kind(self.arena, fields[0])? != "arrow" || !equal(self.arena, fields[1], fields[2])? {
            return Err(fail("typed fixed point requires a finite endofunction"));
        }
        let none = self.arena.add(Object::Boolean(false))?;
        self.typed_node(fields[1], "fix", args, none)
    }
    fn typed_union(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 2)?;
        let ty = self.term_type(args[0])?;
        relation(self.arena, ty)?;
        if !equal(self.arena, ty, self.term_type(args[1])?)? {
            return Err(fail("typed union signature mismatch"));
        }
        let none = self.arena.add(Object::Boolean(false))?;
        self.typed_node(ty, "union", args, none)
    }
    fn typed_join(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 4)?;
        let (left, ld) = relation(self.arena, self.term_type(args[0])?)?;
        let (right, rd) = relation(self.arena, self.term_type(args[1])?)?;
        if domain(self.arena, ld)? != domain(self.arena, rd)?
            || index(self.arena, args[2])? >= left
            || index(self.arena, args[3])? >= right
        {
            return Err(fail("typed join signature mismatch"));
        }
        let arity = self
            .arena
            .add(Object::Number(num_rational::BigRational::from_integer(
                (left + right).into(),
            )))?;
        let ty = self.finite_relation_type(arity, ld)?;
        let data = self.arena.add(Object::Vector(args[2..].to_vec()))?;
        self.typed_node(ty, "join", &args[..2], data)
    }
    fn typed_project(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 2)?;
        let (width, domain) = relation(self.arena, self.term_type(args[0])?)?;
        let columns = crate::modules::operator_columns(self.arena, args[1], width)?;
        let arity = self
            .arena
            .add(Object::Number(num_rational::BigRational::from_integer(
                columns.len().into(),
            )))?;
        let ty = self.finite_relation_type(arity, domain)?;
        let cells = columns
            .into_iter()
            .map(|c| {
                self.arena
                    .add(Object::Number(num_rational::BigRational::from_integer(
                        c.into(),
                    )))
            })
            .collect::<Result<Vec<_>>>()?;
        let data = self.arena.list(&cells)?;
        self.typed_node(ty, "project", &args[..1], data)
    }
    fn typed_select(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 3)?;
        let ty = self.term_type(args[0])?;
        let (width, atoms) = relation(self.arena, ty)?;
        let value = Admission::new(self.arena, self.arena.identity)?.freeze(args[2])?;
        if index(self.arena, args[1])? >= width || !domain(self.arena, atoms)?.contains(&value) {
            return Err(fail("typed selection outside signature"));
        }
        let data = self.arena.add(Object::Vector(args[1..].to_vec()))?;
        self.typed_node(ty, "select-eq", &args[..1], data)
    }
    fn typed_flatmap(&mut self, args: &[Id]) -> Result<Id> {
        count(args, 3)?;
        let input = self.term_type(args[0])?;
        relation(self.arena, args[1])?;
        let pairs = self
            .arena
            .items(args[2])?
            .into_iter()
            .map(|row| {
                let pair = self.arena.items(row)?;
                count(&pair, 2)?;
                Ok(pair)
            })
            .collect::<Result<Vec<_>>>()?;
        // Every input failure precedes every output failure, independent of table order.
        let inputs = pairs.iter().map(|p| p[0]).collect::<Vec<_>>();
        let inputs = self.arena.list(&inputs)?;
        let inputs = self.checked_domain_rows(input, inputs)?;
        let outputs = pairs.iter().map(|p| p[1]).collect::<Vec<_>>();
        let outputs = self.arena.list(&outputs)?;
        let outputs = self.checked_domain_rows(args[1], outputs)?;
        let inputs = self.arena.items(inputs)?;
        let outputs = self.arena.items(outputs)?;
        let copied = inputs
            .into_iter()
            .zip(outputs)
            .map(|(left, right)| self.arena.list(&[left, right]))
            .collect::<Result<Vec<_>>>()?;
        let data = self.arena.list(&copied)?;
        self.typed_node(args[1], "flatmap", &args[..1], data)
    }
    fn checked_domain_rows(&mut self, ty: Id, rows: Id) -> Result<Id> {
        let (width, atoms) = relation(self.arena, ty)?;
        let atoms = domain(self.arena, atoms)?;
        let admission = Admission::new(self.arena, self.arena.identity)?;
        let rows = admission.rows(rows)?;
        if rows
            .iter()
            .any(|r| r.len() != width || r.iter().any(|v| !atoms.contains(v)))
        {
            return Err(fail("typed source tuple outside declared domain"));
        }
        self.arena.rows_object(&rows)
    }
}
