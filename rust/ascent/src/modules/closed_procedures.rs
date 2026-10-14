//! Snapshot pure lexical procedures into the worker-safe scalar expression graph.
use super::{
    constructors::Admission,
    objects::{EnvId, Id, Object, Procedure, fail},
};
use crate::{Expression, Operator, Result, Term, Value, source::Datum};
use std::collections::BTreeMap;
impl Admission<'_> {
    pub(super) fn procedure(&self, id: Id, inputs: &[u32]) -> Result<Expression> {
        match self.arena.get(id)? {
            Object::Procedure(Procedure::Builtin(name)) => {
                let op = Operator::named(name)
                    .ok_or_else(|| fail("procedure needs pure Rust scalar lowering"))?;
                if !op.arity(inputs.len()) {
                    return Err(fail("procedure input arity"));
                }
                Ok(Expression::Call(
                    op,
                    inputs
                        .iter()
                        .map(|id| Expression::Term(Term::Variable(*id)))
                        .collect(),
                ))
            }
            Object::Procedure(Procedure::Closure {
                parameters,
                rest: None,
                body,
                env,
            }) if parameters.len() == inputs.len() && body.len() == 1 => {
                let bindings = parameters
                    .iter()
                    .cloned()
                    .zip(inputs.iter().copied())
                    .collect();
                self.scalar_datum(&body[0], *env, &bindings, 0, &mut 0)
            }
            _ => Err(fail(
                "procedure requires a closed single-expression scalar body",
            )),
        }
    }
    fn scalar_datum(
        &self,
        datum: &Datum,
        env: EnvId,
        parameters: &BTreeMap<String, u32>,
        depth: usize,
        nodes: &mut usize,
    ) -> Result<Expression> {
        if depth > 128 || *nodes >= 65536 {
            return Err(fail("closed scalar structure bound"));
        }
        *nodes += 1;
        Ok(match datum {
            Datum::Text(text) => Expression::Term(Term::Literal(Value::Text(text.as_str().into()))),
            Datum::Atom(name) => {
                if let Some(slot) = parameters.get(name) {
                    Expression::Term(Term::Variable(*slot))
                } else if let Some(n) = super::evaluation::number(name) {
                    Expression::Term(Term::Literal(crate::numbers::Number::Exact(n).value()?))
                } else if let Some(c) = super::evaluation::character(name) {
                    Expression::Term(Term::Literal(character_value(c)?))
                } else if matches!(name.as_str(), "#t" | "#f") {
                    Expression::Term(Term::Literal(Value::Boolean(name == "#t")))
                } else {
                    Expression::Term(Term::Literal(self.freeze(self.arena.lookup(env, name)?)?))
                }
            }
            Datum::List(items) => {
                let Some(Datum::Atom(name)) = items.first() else {
                    return Err(fail("closed scalar call operator"));
                };
                if name == "quote" {
                    return Self::quoted_scalar(&items[1..]);
                }
                let op = if matches!(name.as_str(), "and" | "or") {
                    Operator::named(name)
                } else {
                    if parameters.contains_key(name) {
                        return Err(fail("scalar parameter is not a procedure"));
                    }
                    match self.arena.get(self.arena.lookup(env, name)?)? {
                        Object::Procedure(Procedure::Builtin(name)) => Operator::named(name),
                        _ => None,
                    }
                }
                .ok_or_else(|| fail("procedure call requires a pure Rust scalar operator"))?;
                if !op.arity(items.len() - 1) {
                    return Err(fail("closed scalar operator arity"));
                }
                Expression::Call(
                    op,
                    items[1..]
                        .iter()
                        .map(|arg| self.scalar_datum(arg, env, parameters, depth + 1, nodes))
                        .collect::<Result<_>>()?,
                )
            }
        })
    }
    fn quoted_scalar(items: &[Datum]) -> Result<Expression> {
        let [datum] = items else {
            return Err(fail("closed scalar quote arity"));
        };
        let value = match datum {
            Datum::Text(text) => Value::Text(text.as_str().into()),
            Datum::Atom(name) => {
                if let Some(n) = super::evaluation::number(name) {
                    crate::numbers::Number::Exact(n).value()?
                } else if let Some(c) = super::evaluation::character(name) {
                    character_value(c)?
                } else if matches!(name.as_str(), "#t" | "#f") {
                    Value::Boolean(name == "#t")
                } else {
                    super::evaluation::validate_symbol(name)?;
                    Value::Symbol(name.as_str().into())
                }
            }
            Datum::List(_) => return Err(fail("compound scalar quote requires lowering")),
        };
        Ok(Expression::Term(Term::Literal(value)))
    }
}

fn character_value(value: char) -> Result<Value> {
    crate::FrozenValue::new(
        0,
        0,
        crate::ObjectGraph {
            root: crate::GraphItem::Character(value),
            nodes: BTreeMap::new(),
        },
    )
    .map(Value::Object)
}
