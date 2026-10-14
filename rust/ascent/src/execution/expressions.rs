//! Closed expressions execute on Rust-owned values under the shared budget.
use super::{Bindings, Budget, Values};
use crate::{Error, Expression, Operator, Result, Term, Value};
use num_bigint::BigInt;
use num_traits::Zero;

fn failure(message: &str) -> Error {
    Error::Evaluation(message.into())
}
fn integer(value: &Value) -> Result<&BigInt> {
    match value {
        Value::Integer(value) => Ok(value),
        _ => Err(failure("operator expects exact integers")),
    }
}
fn truth(value: &Value) -> bool {
    *value != Value::Boolean(false)
}

pub(super) fn evaluate(
    expression: &Expression,
    bindings: &Bindings,
    values: &Values,
    budget: &Budget,
) -> Result<Value> {
    if !budget.work(1) {
        return Err(Error::StateLimit);
    }
    let (operator, operands) = match expression {
        Expression::Term(Term::Literal(value)) => return Ok(value.clone()),
        Expression::Term(Term::Variable(slot)) => {
            return Ok(values
                .scalar(bindings[*slot as usize].expect("checked expression variable"))
                .clone());
        }
        Expression::Term(Term::Wildcard) => unreachable!("checked expression"),
        Expression::Call(operator, operands) => (*operator, operands),
    };
    if matches!(operator, Operator::And | Operator::Or) {
        let mut last = Value::Boolean(operator == Operator::And);
        for operand in operands {
            last = evaluate(operand, bindings, values, budget)?;
            if truth(&last) == (operator == Operator::Or) {
                break;
            }
        }
        return Ok(last);
    }
    let left = evaluate(&operands[0], bindings, values, budget)?;
    if operator == Operator::Identity {
        return Ok(left);
    }
    if operator == Operator::Not {
        return Ok(Value::Boolean(!truth(&left)));
    }
    if operands.len() == 1 {
        let value = integer(&left)?;
        return Ok(Value::Boolean(match operator {
            Operator::Even => !value.bit(0),
            Operator::Odd => value.bit(0),
            Operator::Zero => value.is_zero(),
            Operator::Positive => value > &BigInt::zero(),
            Operator::Negative => value < &BigInt::zero(),
            _ => unreachable!("checked unary operator"),
        }));
    }
    let right = evaluate(&operands[1], bindings, values, budget)?;
    if operator == Operator::Equal {
        return Ok(Value::Boolean(left == right));
    }
    let (left, right) = (integer(&left)?, integer(&right)?);
    // Charge magnitude work before allocating arithmetic results. Cooperative
    // deadline/cancellation gates still protect final snapshot publication.
    let units = (left.bits() / 64 + 1).saturating_mul(right.bits() / 64 + 1);
    if !budget.work(usize::try_from(units).unwrap_or(usize::MAX)) {
        return Err(Error::StateLimit);
    }
    Ok(match operator {
        Operator::Add => Value::Integer(left + right),
        Operator::Subtract => Value::Integer(left - right),
        Operator::Multiply => Value::Integer(left * right),
        Operator::Less => Value::Boolean(left < right),
        Operator::LessEqual => Value::Boolean(left <= right),
        Operator::Greater => Value::Boolean(left > right),
        Operator::GreaterEqual => Value::Boolean(left >= right),
        Operator::NumericEqual => Value::Boolean(left == right),
        _ => unreachable!("checked binary operator"),
    })
}

pub(super) fn guard(
    expression: &Expression,
    bindings: &Bindings,
    values: &Values,
    budget: &Budget,
) -> bool {
    match evaluate(expression, bindings, values, budget) {
        Ok(Value::Boolean(value)) => value,
        Ok(_) => {
            budget.evaluation_error(failure("guard must return a boolean"));
            false
        }
        Err(error) => {
            budget.evaluation_error(error);
            false
        }
    }
}
