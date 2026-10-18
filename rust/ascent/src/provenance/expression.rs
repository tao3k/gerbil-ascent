//! Independent checked scalar evaluation for finite provenance replay.
use crate::{Error, Expression, Operator, Result, Term, Value};
use num_bigint::BigInt;
use num_traits::{ToPrimitive, Zero};
use std::collections::BTreeMap;
pub(super) fn ground(
    expression: &Expression,
    bindings: &BTreeMap<u32, Value>,
) -> Result<Expression> {
    Ok(match expression {
        Expression::Term(Term::Variable(id)) => {
            Expression::Term(Term::Literal(bindings.get(id).cloned().ok_or_else(
                || Error::Evaluation("unbound provenance expression".into()),
            )?))
        }
        Expression::Term(Term::Literal(value)) => Expression::Term(Term::Literal(value.clone())),
        Expression::Term(Term::Wildcard) => {
            return Err(Error::Evaluation("wildcard provenance expression".into()));
        }
        Expression::Call(op, args) => Expression::Call(
            *op,
            args.iter()
                .map(|arg| ground(arg, bindings))
                .collect::<Result<_>>()?,
        ),
    })
}
pub(super) fn evaluate(
    expression: &Expression,
    step: &mut impl FnMut() -> Result<()>,
) -> Result<Value> {
    step()?;
    let Expression::Call(op, args) = expression else {
        if let Expression::Term(Term::Literal(value)) = expression {
            return Ok(value.clone());
        }
        return Err(Error::Evaluation("ungrounded expression".into()));
    };
    if matches!(op, Operator::And | Operator::Or) {
        let mut value = Value::Boolean(*op == Operator::And);
        for arg in args {
            value = evaluate(arg, step)?;
            if truth(&value) == (*op == Operator::Or) {
                break;
            }
        }
        return Ok(value);
    }
    let left = evaluate(&args[0], step)?;
    match op {
        Operator::Identity => return Ok(left),
        Operator::Not => return Ok(Value::Boolean(!truth(&left))),
        _ => (),
    }
    if args.len() == 1 {
        let n = integer(&left)?;
        return Ok(Value::Boolean(match op {
            Operator::Even => !n.bit(0),
            Operator::Odd => n.bit(0),
            Operator::Zero => n.is_zero(),
            Operator::Positive => n > &BigInt::zero(),
            Operator::Negative => n < &BigInt::zero(),
            _ => return Err(Error::Evaluation("invalid unary proof operator".into())),
        }));
    }
    let right = evaluate(&args[1], step)?;
    if *op == Operator::VectorShape {
        let width = integer(&right)?.to_usize();
        return Ok(Value::Boolean(matches!(&left, Value::Object(value)
            if value.vector_items().is_some_and(|items| Some(items.len()) == width))));
    }
    if *op == Operator::VectorRef {
        let index = integer(&right)?.to_usize().ok_or_else(|| Error::Evaluation("vector proof index".into()))?;
        let Value::Object(value) = left else { return Err(Error::Evaluation("vector proof expects vector".into())); };
        for _ in 0..value.graph().nodes.len() { step()?; }
        return value.vector_item(index);
    }
    if *op == Operator::StringEqual {
        let (Value::Text(a), Value::Text(b)) = (&left, &right) else {
            return Err(Error::Evaluation("string=? proof expects strings".into()));
        };
        for _ in 0..a.len().min(b.len()) {
            step()?;
        }
        return Ok(Value::Boolean(a == b));
    }
    if *op == Operator::ImmediateEqual {
        if !matches!(
            (&left, &right),
            (
                Value::Symbol(_) | Value::Boolean(_),
                Value::Symbol(_) | Value::Boolean(_)
            )
        ) {
            return Err(Error::Evaluation(
                "eq? heap/numeric proof identity is unsupported".into(),
            ));
        }
        return Ok(Value::Boolean(left == right));
    }
    if *op == Operator::Equal {
        return Ok(Value::Boolean(left == right));
    }
    let (a, b) = (integer(&left)?, integer(&right)?);
    charge(a, b, step)?;
    Ok(match op {
        Operator::Add => Value::Integer(a + b),
        Operator::Subtract => Value::Integer(a - b),
        Operator::Multiply => Value::Integer(a * b),
        Operator::Less => Value::Boolean(a < b),
        Operator::LessEqual => Value::Boolean(a <= b),
        Operator::Greater => Value::Boolean(a > b),
        Operator::GreaterEqual => Value::Boolean(a >= b),
        Operator::NumericEqual => Value::Boolean(a == b),
        _ => return Err(Error::Evaluation("invalid binary proof operator".into())),
    })
}
fn integer(value: &Value) -> Result<&BigInt> {
    if let Value::Integer(n) = value {
        Ok(n)
    } else {
        Err(Error::Evaluation(
            "proof operator requires exact integers".into(),
        ))
    }
}
fn truth(value: &Value) -> bool {
    *value != Value::Boolean(false)
}

/// Reject excessive magnitude work before allocating arithmetic results.
pub(super) fn charge(a: &BigInt, b: &BigInt, step: &mut impl FnMut() -> Result<()>) -> Result<()> {
    let units = (a.bits() / 64 + 1).saturating_mul(b.bits() / 64 + 1);
    for _ in 0..units {
        step()?;
    }
    Ok(())
}
