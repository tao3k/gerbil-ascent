//! Native aggregate constructors lower to closed Rust reducers, never host callbacks.
use super::{
    constructors::Admission,
    evaluation::Evaluation,
    objects::{Id, Object, Procedure, fail},
};
use crate::{Atom, Clause, Reducer, Result, Term};
use std::collections::BTreeMap;
pub(super) const EXPORTS: &[&str] = &[
    "gerbil-ascent-count",
    "gerbil-ascent-sum",
    "gerbil-ascent-min",
    "gerbil-ascent-max",
    "gerbil-ascent-mean",
];
pub(super) fn reducer(arena: &super::objects::Arena, id: Id) -> Result<Reducer> {
    let Object::Procedure(Procedure::Builtin(name)) = arena.get(id)? else {
        return Err(fail("aggregate requires a closed Rust reducer"));
    };
    name.strip_prefix("gerbil-ascent-")
        .and_then(Reducer::named)
        .ok_or_else(|| fail("aggregate requires a closed Rust reducer"))
}
impl Admission<'_> {
    pub(super) fn variable(&self, id: Id, variables: &mut BTreeMap<String, u32>) -> Result<u32> {
        let name = self.name(id)?;
        let next = u32::try_from(variables.len()).map_err(|_| fail("variable bound"))?;
        Ok(*variables.entry(name).or_insert(next))
    }
    pub(super) fn clause(&self, id: Id, variables: &mut BTreeMap<String, u32>) -> Result<Clause> {
        match self.arena.get(id)? {
            Object::Record(kind, f) if matches!(kind.as_str(), "guard" | "binding") => {
                self.scalar_clause(kind, f, variables)
            }
            Object::Record(kind, f) if kind == "aggregate" => self.aggregate_clause(f, variables),
            Object::Record(kind, f) if kind == "negation" && f.len() == 2 => {
                self.atom_fields(f, variables).map(Clause::negative)
            }
            _ => self.atom(id, variables).map(Clause::positive),
        }
    }
    fn scalar_clause(
        &self,
        kind: &str,
        f: &[Id],
        variables: &mut BTreeMap<String, u32>,
    ) -> Result<Clause> {
        let offset = usize::from(kind == "binding");
        if f.len() != offset + 2 && f.len() != offset + 3 {
            return Err(fail("scalar constructor arity"));
        }
        if let Some(descriptor) = f.get(offset + 2)
            && !matches!(self.arena.get(*descriptor)?, Object::Boolean(false))
        {
            return Err(fail("scalar descriptor requires checked lowering"));
        }
        let inputs = self
            .arena
            .items(f[offset])?
            .into_iter()
            .map(|id| self.variable(id, variables))
            .collect::<Result<Vec<_>>>()?;
        let expression = self.procedure(f[offset + 1], &inputs)?;
        if kind == "binding" {
            let output = self.variable(f[0], variables)?;
            Ok(Clause::Compute {
                output,
                inputs,
                expression,
            })
        } else {
            Ok(Clause::Guard { inputs, expression })
        }
    }
    fn aggregate_clause(&self, f: &[Id], variables: &mut BTreeMap<String, u32>) -> Result<Clause> {
        if !(5..=7).contains(&f.len()) {
            return Err(fail("aggregate constructor arity"));
        }
        if f[5..]
            .iter()
            .any(|id| !matches!(self.arena.get(*id), Ok(Object::Boolean(false))))
        {
            return Err(fail(
                "custom aggregate output matchers/descriptors require lowering",
            ));
        }
        let atom: Atom = self.atom_fields(&f[1..3], variables)?;
        let inputs = self
            .arena
            .items(f[3])?
            .into_iter()
            .map(|id| self.variable(id, variables))
            .collect::<Result<Vec<_>>>()?;
        if inputs
            .iter()
            .any(|slot| !atom.terms.contains(&Term::Variable(*slot)))
        {
            return Err(fail("aggregate input missing from its atom"));
        }
        let operator = reducer(self.arena, f[4])?;
        let output = self.variable(f[0], variables)?;
        Ok(Clause::Reduce {
            output,
            operator,
            atom,
            inputs,
        })
    }
}
impl Evaluation<'_> {
    pub(super) fn aggregate_primitive(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        super::operator_values::count(args, 1)?;
        let operator = name
            .strip_prefix("gerbil-ascent-")
            .and_then(Reducer::named)
            .ok_or_else(|| fail("unknown aggregate"))?;
        let width = usize::from(operator != Reducer::Count);
        let cells = self
            .arena
            .items(args[0])?
            .into_iter()
            .map(|id| {
                let row = self.arena.items(id)?;
                if row.len() != width {
                    return Err(fail("aggregate tuple arity"));
                }
                Ok(row)
            })
            .collect::<Result<Vec<_>>>()?;
        if operator == Reducer::Count {
            let value = self
                .arena
                .add(Object::Number(num_rational::BigRational::from_integer(
                    cells.len().into(),
                )))?;
            return self.arena.list(&[value]).map(|id| vec![id]);
        }
        let admission = Admission::new(self.arena, self.arena.identity)?;
        let values = cells
            .iter()
            .map(|row| admission.freeze(row[0]))
            .collect::<Result<Vec<_>>>()?;
        let mut total = None;
        for value in &values {
            self.check(depth)?;
            let value = crate::numbers::Number::read(value)?;
            let units = total
                .as_ref()
                .map_or(1, crate::numbers::Number::units)
                .saturating_mul(value.units());
            for _ in 0..units {
                self.check(depth)?;
            }
            total = Some(match total {
                None => value,
                Some(prior) => match operator {
                    Reducer::Sum | Reducer::Mean => prior.add(value),
                    Reducer::Min => prior.extreme(value, true),
                    Reducer::Max => prior.extreme(value, false),
                    Reducer::Count => unreachable!(),
                },
            });
        }
        let value = match (operator, total) {
            (Reducer::Sum, None) => Some(crate::numbers::Number::Exact(
                num_rational::BigRational::from_integer(0.into()),
            )),
            (Reducer::Mean, Some(total)) => {
                use num_traits::ToPrimitive;
                Some(crate::numbers::Number::Inexact(
                    total.inexact()
                        / values
                            .len()
                            .to_f64()
                            .ok_or_else(|| fail("aggregate count bound"))?,
                ))
            }
            (_, total) => total,
        };
        let values = value
            .map(|n| self.arena.thaw(&n.value()?))
            .transpose()?
            .into_iter()
            .collect::<Vec<_>>();
        self.arena.list(&values).map(|id| vec![id])
    }
}
