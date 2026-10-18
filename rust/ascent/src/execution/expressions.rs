//! Closed expressions execute on Rust-owned values under the shared budget.
use super::{Bindings, Budget, Values};
use crate::{Error, Expression, Operator, Result, Term, Value};
use num_bigint::BigInt;
use num_traits::{ToPrimitive, Zero};

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

fn short_circuit(
    operator: Operator,
    operands: &[Expression],
    bindings: &Bindings,
    values: &Values,
    budget: &Budget,
) -> Result<Value> {
    let mut last = Value::Boolean(operator == Operator::And);
    for operand in operands {
        last = evaluate(operand, bindings, values, budget)?;
        if truth(&last) == (operator == Operator::Or) {
            break;
        }
    }
    Ok(last)
}

fn append_strings(
    operands: &[Expression],
    bindings: &Bindings,
    values: &Values,
    budget: &Budget,
) -> Result<Value> {
    let mut output = String::new();
    for operand in operands {
        let Value::Text(text) = evaluate(operand, bindings, values, budget)? else {
            return Err(failure("string-append expects strings"));
        };
        if !budget.work(text.len()) {
            return Err(Error::StateLimit);
        }
        output.push_str(&text);
    }
    Ok(Value::Text(output.into()))
}
fn vector_operator(operator: Operator, left: &Value, right: &Value, budget: &Budget) -> Result<Value> {
    let index = integer(right)?.to_usize();
    if operator == Operator::VectorShape {
        return Ok(Value::Boolean(matches!(left, Value::Object(value)
            if value.vector_items().is_some_and(|items| Some(items.len()) == index))));
    }
    let index = index.ok_or_else(|| failure("vector index"))?;
    let Value::Object(value) = left else { return Err(failure("vector-ref expects vector")); };
    if !budget.work(value.graph().nodes.len()) { return Err(Error::StateLimit); }
    value.vector_item(index)
}
fn symbol_to_string(value: Value, budget: &Budget) -> Result<Value> {
    let Value::Symbol(value) = value else { return Err(failure("symbol->string expects a symbol")); };
    if !budget.work(value.len()) { return Err(Error::StateLimit); }
    Ok(Value::Text(value))
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
        return short_circuit(operator, operands, bindings, values, budget);
    }
    if operator == Operator::StringAppend {
        return append_strings(operands, bindings, values, budget);
    }
    let left = evaluate(&operands[0], bindings, values, budget)?;
    if operator == Operator::Identity {
        return Ok(left);
    }
    if operator == Operator::SymbolToString {
        return symbol_to_string(left, budget);
    }
    if operator == Operator::StringToSymbol {
        return string_to_symbol(left, budget);
    }
    if operator == Operator::Not {
        return Ok(Value::Boolean(!truth(&left)));
    }
    if operands.len() == 1 {
        let value = integer(&left)?;
        if operator == Operator::Subtract {
            if !budget.work(usize::try_from(value.bits() / 64 + 1).unwrap_or(usize::MAX)) {
                return Err(Error::StateLimit);
            }
            return Ok(Value::Integer(-value));
        }
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
    if matches!(operator, Operator::VectorShape | Operator::VectorRef) {
        return vector_operator(operator, &left, &right, budget);
    }
    if operator == Operator::StringEqual {
        let (Value::Text(a), Value::Text(b)) = (&left, &right) else {
            return Err(failure("string=? expects strings"));
        };
        if !budget.work(a.len().min(b.len())) {
            return Err(Error::StateLimit);
        }
        return Ok(Value::Boolean(a == b));
    }
    if operator == Operator::ImmediateEqual {
        if !matches!(
            (&left, &right),
            (
                Value::Symbol(_) | Value::Boolean(_),
                Value::Symbol(_) | Value::Boolean(_)
            )
        ) {
            return Err(failure(
                "eq? heap/numeric identity is unsupported; use equal? or =",
            ));
        }
        return Ok(Value::Boolean(left == right));
    }
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

fn string_to_symbol(value: Value, budget: &Budget) -> Result<Value> {
    let Value::Text(value) = value else {
        return Err(failure("string->symbol expects a string"));
    };
    if !budget.work(value.len()) {
        return Err(Error::StateLimit);
    }
    Ok(Value::Symbol(value))
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
