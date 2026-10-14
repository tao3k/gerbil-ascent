//! Catalog terms and checked operators are lowered exactly once at admission.
use super::{scalar, shape};
use crate::{
    Atom, Clause, Data, Expression, Operator, Reducer, Relation, Result, Term, Type,
    invalid_data as invalid,
};
use std::collections::BTreeMap;
type Names = BTreeMap<String, u32>;
pub(super) fn variable(name: &str, names: &mut Names) -> Result<u32> {
    if name.is_empty() || name.chars().count() > 128 {
        return Err(invalid("variable name bound"));
    }
    let next = u32::try_from(names.len()).map_err(|_| invalid("variable bound"))?;
    Ok(*names.entry(name.into()).or_insert(next))
}
fn term(value: &Data, ty: Type, names: &mut Names) -> Result<Term> {
    if value.map()?.len() != 1 {
        return Err(invalid("one variable or constant field required"));
    }
    if let Some(wildcard) = value.get("wildcard") {
        if wildcard.boolean()? {
            return Ok(Term::Wildcard);
        }
        return Err(invalid("wildcard must be true"));
    }
    if let Some(name) = value.get("var") {
        return variable(name.text()?, names).map(Term::Variable);
    }
    scalar(value.field("const")?, ty).map(Term::Literal)
}
pub(super) fn atom(
    value: &Data,
    relations: &BTreeMap<String, &Relation>,
    names: &mut Names,
) -> Result<Atom> {
    let label = value.field("relation")?.text()?;
    let declaration = relations
        .get(label)
        .ok_or_else(|| invalid("undeclared relation"))?;
    let cells = value.field("terms")?.list()?;
    if cells.len() != declaration.columns.len() {
        return Err(invalid("atom arity"));
    }
    Ok(Atom::new(
        label,
        cells
            .iter()
            .zip(&declaration.columns)
            .map(|(cell, ty)| term(cell, *ty, names))
            .collect::<Result<_>>()?,
    ))
}
pub(super) fn clause(
    value: &Data,
    relations: &BTreeMap<String, &Relation>,
    names: &mut Names,
) -> Result<Clause> {
    let Some(mode) = value.get("mode") else {
        shape(value, &["relation", "terms"], &["not"])?;
        return Ok(Clause::Relation {
            atom: atom(value, relations, names)?,
            negative: value
                .get("not")
                .map(Data::boolean)
                .transpose()?
                .unwrap_or(false),
        });
    };
    match mode.text()? {
        "reduce" => {
            shape(
                value,
                &["mode", "operator", "terms", "output", "inputs", "relation"],
                &[],
            )?;
            let operator = Reducer::named(value.field("operator")?.text()?)
                .ok_or_else(|| invalid("unknown reducer"))?;
            let target = atom(value, relations, names)?;
            let inputs = value
                .field("inputs")?
                .list()?
                .iter()
                .map(|v| variable(v.text()?, names))
                .collect::<Result<_>>()?;
            Ok(Clause::Reduce {
                operator,
                atom: target,
                inputs,
                output: variable(value.field("output")?.text()?, names)?,
            })
        }
        "where" | "compute" => scalar_clause(value, mode.text()?, names),
        _ => Err(invalid("unknown operator mode")),
    }
}
fn scalar_clause(value: &Data, mode: &str, names: &mut Names) -> Result<Clause> {
    let required = if mode == "where" {
        vec!["mode", "operator", "terms"]
    } else {
        vec!["mode", "operator", "terms", "output"]
    };
    shape(value, &required, &[])?;
    let operator = Operator::named(value.field("operator")?.text()?)
        .ok_or_else(|| invalid("unknown checked operator"))?;
    let expression = Expression::Call(
        operator,
        value
            .field("terms")?
            .list()?
            .iter()
            .map(|v| term(v, Type::Symbol, names).map(Expression::Term))
            .collect::<Result<_>>()?,
    );
    match mode {
        "where" if matches!(operator, Operator::Less | Operator::Even) => Ok(Clause::Guard {
            inputs: Vec::new(),
            expression,
        }),
        "compute" if matches!(operator, Operator::Add | Operator::Identity) => {
            Ok(Clause::Compute {
                inputs: Vec::new(),
                expression,
                output: variable(value.field("output")?.text()?, names)?,
            })
        }
        _ => Err(invalid("unsupported checked operator mode")),
    }
}
