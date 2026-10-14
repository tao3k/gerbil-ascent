//! Construction-only operator validation and lexical builder invocation.
use super::{
    constructors::Admission,
    evaluation::Evaluation,
    objects::{Arena, Id, Object, fail},
    operator_lowering,
};
use crate::Result;
use num_traits::ToPrimitive;
use std::sync::Arc;
pub(super) const EXPORTS: &[&str] = &[
    "relational-op-source",
    "relational-op-evaluate",
    "relational-op-project",
    "relational-op-union",
    "relational-op-join",
    "relational-op-select-eq",
    "relational-op-flatmap",
    "relational-op-fix",
    "relational-op-function",
    "relational-op-apply",
    "relational-op-fragment",
    "relational-op-compile",
    "relational-op?",
    "relational-op-arity",
];
pub(super) fn index(arena: &Arena, id: Id) -> Result<usize> {
    arena
        .integer(id)?
        .to_usize()
        .ok_or_else(|| fail("nonnegative exact integer required"))
}
pub(super) fn columns(arena: &Arena, id: Id, arity: usize) -> Result<Vec<usize>> {
    arena
        .items(id)?
        .into_iter()
        .map(|id| {
            let value = index(arena, id)?;
            if value >= arity {
                Err(fail("operator column outside arity"))
            } else {
                Ok(value)
            }
        })
        .collect()
}
pub(super) fn transformer(arena: &Arena, id: Id) -> Result<(Id, Id)> {
    match arena.get(id)? {
        Object::Record(kind, f) if kind == "transformer" && f.len() == 2 => Ok((f[0], f[1])),
        _ => Err(fail("relation transformer required")),
    }
}
pub(super) fn arity(arena: &Arena, id: Id) -> Result<usize> {
    operator_lowering::fields(arena, id).map(|(_, arity, _)| arity)
}
pub(super) fn scalar(arena: &Arena, id: Id) -> Result<()> {
    if matches!(
        arena.get(id)?,
        Object::Boolean(_) | Object::Character(_) | Object::Symbol(_, _)
    ) || matches!(arena.get(id)?,Object::Number(n) if n.is_integer())
    {
        Ok(())
    } else {
        Err(fail("relational scalar required"))
    }
}
pub(super) fn rows(arena: &Arena, id: Id, arity: usize) -> Result<()> {
    for row in arena.items(id)? {
        let values = arena.items(row)?;
        if values.len() != arity {
            return Err(fail("relational row arity"));
        }
        for value in values {
            scalar(arena, value)?;
        }
    }
    Ok(())
}
impl Evaluation<'_> {
    pub(super) fn operator(&mut self, name: &str, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        if name == "relational-op-evaluate" {
            return self.evaluate_operator(args);
        }
        let id = match name {
            "relational-op-source" => {
                count(args, 3)?;
                self.arena.register_name(args[0])?;
                Admission::new(self.arena, self.arena.identity)?.name(args[0])?;
                let arity = index(self.arena, args[1])?;
                if arity > 128 {
                    return Err(fail("operator arity bound"));
                }
                rows(self.arena, args[2], arity)?;
                let values = Admission::new(self.arena, self.arena.identity)?.rows(args[2])?;
                let copied = self.arena.rows_object(&values)?;
                self.descriptor("op-source", arity, &[args[0], copied])?
            }
            "relational-op-fix" | "relational-op-function" => {
                count(args, 2)?;
                let arity = index(self.arena, args[0])?;
                let parameter = self.descriptor("op-parameter", arity, &[])?;
                let values = self.apply(args[1], &[parameter], depth + 1)?;
                let [body] = values.as_slice() else {
                    return Err(fail("operator builder must return one descriptor"));
                };
                let output = super::operator_values::arity(self.arena, *body)?;
                if name == "relational-op-fix" {
                    if output != arity {
                        return Err(fail("fixed-point arity mismatch"));
                    }
                    self.descriptor("op-fix", arity, &[parameter, *body])?
                } else {
                    self.arena
                        .add(Object::Record("transformer".into(), vec![parameter, *body]))?
                }
            }
            "relational-op-fragment" => {
                count(args, 2)?;
                let label = Admission::new(self.arena, self.arena.identity)?.name(args[1])?;
                let namespace = self.arena.add(Object::Void)?;
                let fragment = operator_lowering::lower(
                    self.arena,
                    self.arena.identity,
                    args[0],
                    &label,
                    namespace,
                    true,
                )?;
                self.arena.add(Object::Fragment(Arc::new(fragment)))?
            }
            "relational-op-compile" => {
                if !(1..=4).contains(&args.len()) {
                    return Err(fail("operator compile arity"));
                }
                let namespace = self.arena.add(Object::Void)?;
                let fragment = operator_lowering::lower(
                    self.arena,
                    self.arena.identity,
                    args[0],
                    "output",
                    namespace,
                    false,
                )?;
                let mut program = fragment.program;
                program.fact_limits = super::relational::limits(self.arena, &args[1..])?;
                let output = self.arena.relation_name(&fragment.output)?;
                let program = self
                    .arena
                    .add(Object::Compiled(Arc::new(program), vec![args[0]]))?;
                return Ok(vec![program, output]);
            }
            "relational-op?" => {
                count(args, 1)?;
                self.arena
                    .add(Object::Boolean(arity(self.arena, args[0]).is_ok()))?
            }
            "relational-op-arity" => {
                count(args, 1)?;
                self.arena
                    .add(Object::Number(num_rational::BigRational::from_integer(
                        arity(self.arena, args[0])?.into(),
                    )))?
            }
            _ => self.operator_node(name, args)?,
        };
        Ok(vec![id])
    }
    fn evaluate_operator(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        if !(1..=2).contains(&args.len()) {
            return Err(fail("operator evaluation arity"));
        }
        let output_limit = super::relational::limits(self.arena, &args[1..])?.input;
        let namespace = self.arena.add(Object::Void)?;
        let graph = operator_lowering::lower(
            self.arena,
            self.arena.identity,
            args[0],
            "output",
            namespace,
            false,
        )?;
        let mut session = self.engine.open(graph.program)?;
        let snapshot = session.run(
            &crate::SourceSession::default_limits(),
            &crate::Cancellation::default(),
        )?;
        let rows = snapshot
            .relations
            .get(&graph.output)
            .ok_or_else(|| fail("operator output is missing"))?;
        if output_limit.is_some_and(|limit| rows.len() > limit) {
            return Err(crate::Error::OutputFactLimit);
        }
        self.arena.rows_object(rows).map(|id| vec![id])
    }
    pub(super) fn descriptor(&mut self, kind: &str, arity: usize, fields: &[Id]) -> Result<Id> {
        if arity > 128 {
            return Err(fail("operator arity bound"));
        }
        let size = self
            .arena
            .add(Object::Number(num_rational::BigRational::from_integer(
                arity.into(),
            )))?;
        let mut values = vec![size];
        values.extend(fields);
        self.arena.add(Object::Record(kind.into(), values))
    }
    fn operator_node(&mut self, name: &str, args: &[Id]) -> Result<Id> {
        let (kind, size) = match name {
            "relational-op-project" => {
                count(args, 2)?;
                (
                    "op-project",
                    columns(self.arena, args[1], arity(self.arena, args[0])?)?.len(),
                )
            }
            "relational-op-union" => {
                count(args, 2)?;
                let a = arity(self.arena, args[0])?;
                if a != arity(self.arena, args[1])? {
                    return Err(fail("operator union arity mismatch"));
                }
                ("op-union", a)
            }
            "relational-op-join" => {
                count(args, 4)?;
                let a = arity(self.arena, args[0])?;
                let b = arity(self.arena, args[1])?;
                if index(self.arena, args[2])? >= a || index(self.arena, args[3])? >= b {
                    return Err(fail("join key outside arity"));
                }
                ("op-join", a + b)
            }
            "relational-op-select-eq" => {
                count(args, 3)?;
                let a = arity(self.arena, args[0])?;
                if index(self.arena, args[1])? >= a {
                    return Err(fail("select column outside arity"));
                }
                scalar(self.arena, args[2])?;
                ("op-select", a)
            }
            "relational-op-apply" => {
                count(args, 2)?;
                let (parameter, body) = transformer(self.arena, args[0])?;
                if arity(self.arena, parameter)? != arity(self.arena, args[1])? {
                    return Err(fail("transformer input arity mismatch"));
                }
                ("op-apply", arity(self.arena, body)?)
            }
            "relational-op-flatmap" => {
                count(args, 3)?;
                let input = arity(self.arena, args[0])?;
                let output = index(self.arena, args[1])?;
                for entry in self.arena.items(args[2])? {
                    let pair = self.arena.items(entry)?;
                    count(&pair, 2)?;
                    rows_one(self.arena, pair[0], input)?;
                    rows_one(self.arena, pair[1], output)?;
                }
                ("op-flatmap", output)
            }
            _ => return Err(fail("unknown operator constructor")),
        };
        if kind == "op-flatmap" {
            self.descriptor(kind, size, &[args[0], args[2]])
        } else {
            self.descriptor(kind, size, args)
        }
    }
}
fn rows_one(arena: &Arena, id: Id, arity: usize) -> Result<()> {
    let values = arena.items(id)?;
    if values.len() != arity {
        return Err(fail("finite mapping row arity"));
    }
    for value in values {
        scalar(arena, value)?;
    }
    Ok(())
}
pub(super) fn count(args: &[Id], n: usize) -> Result<()> {
    if args.len() == n {
        Ok(())
    } else {
        Err(fail("relational procedure arity"))
    }
}
