//! Native real arithmetic also accepts inexact values returned by reducers.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, fail},
    operator_values::count,
};
use crate::{Result, numbers::Number};
use std::cmp::Ordering;
pub(super) const EXPORTS: &[&str] = &[
    "even?",
    "odd?",
    "zero?",
    "positive?",
    "negative?",
    "exact->inexact",
];
impl Evaluation<'_> {
    fn native_number(&self, id: Id) -> Result<Number> {
        match self.arena.get(id)? {
            Object::Number(n) => Ok(Number::Exact(n.clone())),
            Object::Inexact(n) => Ok(Number::Inexact(*n)),
            _ => Err(fail("real number required")),
        }
    }
    pub(super) fn numeric_test(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        count(args, 1)?;
        if name == "exact->inexact" {
            let number = self.native_number(args[0])?.inexact();
            return self.arena.add(Object::Inexact(number)).map(|id| vec![id]);
        }
        let result = match name {
            "even?" | "odd?" => {
                let n = self.arena.integer(args[0])?;
                n.bit(0) == (name == "odd?")
            }
            _ => {
                let n = self.native_number(args[0])?;
                let ordering = n.compare(&Number::Exact(num_rational::BigRational::from_integer(
                    0.into(),
                )));
                match name {
                    "zero?" => ordering == Some(Ordering::Equal),
                    "positive?" => ordering == Some(Ordering::Greater),
                    "negative?" => ordering == Some(Ordering::Less),
                    _ => return Err(fail("unknown numeric predicate")),
                }
            }
        };
        self.arena.add(Object::Boolean(result)).map(|id| vec![id])
    }
    pub(super) fn numeric_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let values = args
            .iter()
            .map(|id| self.native_number(*id))
            .collect::<Result<Vec<_>>>()?;
        let id = if matches!(name, "=" | "<" | ">" | "<=" | ">=") {
            if values.len() < 2 {
                return Err(fail("comparison requires two or more numbers"));
            }
            let mut matches = true;
            for pair in values.windows(2) {
                self.charge_numbers(&pair[0], &pair[1])?;
                let ordering = pair[0].compare(&pair[1]);
                matches &= match name {
                    "=" => ordering == Some(Ordering::Equal),
                    "<" => ordering == Some(Ordering::Less),
                    ">" => ordering == Some(Ordering::Greater),
                    "<=" => matches!(ordering, Some(Ordering::Less | Ordering::Equal)),
                    _ => matches!(ordering, Some(Ordering::Greater | Ordering::Equal)),
                };
            }
            self.arena.add(Object::Boolean(matches))?
        } else {
            let value = self.real_arithmetic(name, &values)?;
            let object = match value {
                Number::Exact(n) => Object::Number(n),
                Number::Inexact(n) => Object::Inexact(n),
            };
            self.arena.add(object)?
        };
        Ok(vec![id])
    }
    fn real_arithmetic(&mut self, name: &str, values: &[Number]) -> Result<Number> {
        let Some((first, rest)) = values.split_first() else {
            return match name {
                "+" => Ok(Number::Exact(num_rational::BigRational::from_integer(
                    0.into(),
                ))),
                "*" => Ok(Number::Exact(num_rational::BigRational::from_integer(
                    1.into(),
                ))),
                _ => Err(fail("number argument required")),
            };
        };
        let mut total = first.clone();
        if rest.is_empty() {
            return match name {
                "-" => Ok(total.negative()),
                "/" => {
                    Number::Exact(num_rational::BigRational::from_integer(1.into())).divide(total)
                }
                _ => Ok(total),
            };
        }
        for value in rest {
            self.charge_numbers(&total, value)?;
            total = match name {
                "+" => total.add(value.clone()),
                "-" => total.subtract(value.clone()),
                "*" => total.multiply(value.clone()),
                "/" => total.divide(value.clone())?,
                "min" => total.extreme(value.clone(), true),
                "max" => total.extreme(value.clone(), false),
                _ => return Err(fail("unknown numeric operator")),
            };
        }
        Ok(total)
    }
    fn charge_numbers(&mut self, a: &Number, b: &Number) -> Result<()> {
        for _ in 0..a.units().saturating_mul(b.units()) {
            self.check(0)?;
        }
        Ok(())
    }
}
