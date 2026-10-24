//! Streaming closed reducers; arithmetic is charged before result allocation.
use super::Budget;
use crate::{Error, Reducer, Result, Value, numbers::Number};
use num_traits::ToPrimitive;
#[derive(Default)]
pub(super) struct Reduction {
    count: usize,
    value: Option<Number>,
}
impl Reduction {
    pub(super) fn push(
        &mut self,
        operator: Reducer,
        value: Option<&Value>,
        budget: &Budget,
    ) -> Result<()> {
        self.count = self.count.checked_add(1).ok_or(Error::StateLimit)?;
        if operator == Reducer::Count {
            return Ok(());
        }
        let value =
            Number::read(value.ok_or_else(|| Error::Evaluation("missing reducer input".into()))?)?;
        let units = self
            .value
            .as_ref()
            .map_or(1, Number::units)
            .saturating_mul(value.units());
        if !budget.work(usize::try_from(units).unwrap_or(usize::MAX)) {
            return Err(Error::StateLimit);
        }
        self.value = Some(match self.value.take() {
            None => value,
            Some(prior) => match operator {
                Reducer::Mean | Reducer::Sum => prior.add(value),
                Reducer::Min => prior.extreme(value, true),
                Reducer::Max => prior.extreme(value, false),
                Reducer::Count => unreachable!(),
            },
        });
        Ok(())
    }
    pub(super) fn finish(self, operator: Reducer) -> Result<Option<Value>> {
        if operator == Reducer::Count {
            return Ok(Some(Value::Integer(self.count.into())));
        }
        let value = match (operator, self.value) {
            (Reducer::Sum, None) => Some(Number::Exact(num_rational::BigRational::from_integer(
                0.into(),
            ))),
            (Reducer::Mean, Some(value)) => Some(Number::Inexact(
                value.inexact() / self.count.to_f64().ok_or(Error::StateLimit)?,
            )),
            (_, value) => value,
        };
        value.map(Number::value).transpose()
    }
}
