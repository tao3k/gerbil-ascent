//! Lossless typed catalog projection; execution never depends on projection success.
use crate::{
    Atom, Catalog, Clause, Data, Expression, Operator, Program, Reducer, Relation, Result, Term,
    Type, Value, invalid_data as invalid,
};

impl Catalog {
    /// Observe typed input tuples, including owned graph identities, without
    /// projecting away values that cannot be represented as native scalars.
    /// # Errors
    /// Rejects invalid graph observations.
    pub fn observe_rows(rows: &[crate::Row]) -> Result<Data> {
        Ok(Data::List(
            rows.iter()
                .map(|row| {
                    row.iter()
                        .map(|cell| value(cell, true))
                        .collect::<Result<Vec<_>>>()
                        .map(Data::List)
                })
                .collect::<Result<_>>()?,
        ))
    }
    /// Observe a typed program through the existing catalog contract.
    /// # Errors
    /// Values with no lossless catalog representation remain explicit gaps.
    pub fn encode(program: &Program, queries: &[String]) -> Result<Data> {
        encode(program, queries, false)
    }
    /// Observe full program data including owner-local graph identities.
    /// This is not a reusable catalog or authority to import opaque resources.
    /// # Errors
    /// Rejects malformed observations; it does not authorize execution.
    pub fn observe(program: &Program, queries: &[String]) -> Result<Data> {
        encode(program, queries, true)
    }
}
fn encode(program: &Program, queries: &[String], observation: bool) -> Result<Data> {
    Ok(Data::object([
        (
            "relations",
            Data::List(
                program
                    .relations
                    .iter()
                    .map(|r| relation(r, observation))
                    .collect::<Result<_>>()?,
            ),
        ),
        (
            "rules",
            Data::List(
                program
                    .rules
                    .iter()
                    .map(|rule| {
                        Ok(Data::object([
                            ("head", Data::List(vec![atom(&rule.head, observation)?])),
                            (
                                "body",
                                Data::List(
                                    rule.body
                                        .iter()
                                        .map(|c| clause(c, observation))
                                        .collect::<Result<_>>()?,
                                ),
                            ),
                        ]))
                    })
                    .collect::<Result<_>>()?,
            ),
        ),
        (
            "queries",
            Data::List(queries.iter().map(|q| q.clone().into()).collect()),
        ),
    ]))
}
fn kind(ty: Type) -> &'static str {
    match ty {
        Type::Scalar => "scalar",
        Type::Any => "value",
        Type::Integer => "integer",
        Type::Boolean => "boolean",
        Type::Text => "string",
        Type::Symbol => "symbol",
        Type::Number => "number",
    }
}
fn value(value: &Value, observation: bool) -> Result<Data> {
    Ok(match value {
        Value::Integer(v) => Data::Integer(v.clone()),
        Value::Boolean(v) => Data::Bool(*v),
        Value::Symbol(v) => {
            Data::object([("type", "symbol".into()), ("value", v.to_string().into())])
        }
        Value::Text(v) => {
            Data::object([("type", "string".into()), ("value", v.to_string().into())])
        }
        Value::Object(v) if observation => v.scheme_input(),
        Value::Object(v)
            if !v.graph().nodes.values().any(|node| {
                matches!(
                    node,
                    crate::ObjectNode::Table(_)
                        | crate::ObjectNode::Opaque(_)
                        | crate::ObjectNode::Symbol {
                            interned: false,
                            ..
                        }
                )
            }) =>
        {
            Data::object([("type", "graph".into()), ("value", v.graph().to_scheme())])
        }
        Value::Object(_) => {
            return Err(invalid(
                "identity-bearing catalog projection unavailable; execution remains independent",
            ));
        }
    })
}
fn relation(r: &Relation, observation: bool) -> Result<Data> {
    let columns = r
        .columns
        .iter()
        .zip(&r.domains)
        .map(|(ty, domain)| {
            let mut column = std::collections::BTreeMap::from([("kind".into(), kind(*ty).into())]);
            if let Some(domain) = domain {
                column.insert(
                    "domain".into(),
                    Data::List(
                        domain
                            .iter()
                            .map(|v| value(v, observation))
                            .collect::<Result<_>>()?,
                    ),
                );
            }
            Ok(Data::Map(column))
        })
        .collect::<Result<_>>()?;
    let mut fields = std::collections::BTreeMap::from([
        ("name".into(), r.name.clone().into()),
        ("source".into(), r.source.into()),
        ("columns".into(), Data::List(columns)),
        (
            "rows".into(),
            Data::List(
                r.rows
                    .iter()
                    .map(|row| {
                        row.iter()
                            .map(|v| value(v, observation))
                            .collect::<Result<Vec<_>>>()
                            .map(Data::List)
                    })
                    .collect::<Result<_>>()?,
            ),
        ),
        ("initialOccurrences".into(), r.initial_occurrences.into()),
    ]);
    if let Some(join) = r.lattice {
        fields.insert(
            "lattice".into(),
            match join {
                crate::LatticeJoin::Min => "min",
                crate::LatticeJoin::Max => "max",
            }
            .into(),
        );
    }
    Ok(Data::Map(fields))
}
fn variable(id: u32) -> String {
    format!("v{id}")
}
fn term(t: &Term, observation: bool) -> Result<Data> {
    Ok(match t {
        Term::Variable(id) => Data::object([("var", variable(*id).into())]),
        Term::Wildcard => Data::object([("wildcard", true.into())]),
        Term::Literal(v) => Data::object([("const", value(v, observation)?)]),
    })
}
fn atom(a: &Atom, observation: bool) -> Result<Data> {
    Ok(Data::object([
        ("relation", a.relation.clone().into()),
        (
            "terms",
            Data::List(
                a.terms
                    .iter()
                    .map(|t| term(t, observation))
                    .collect::<Result<_>>()?,
            ),
        ),
    ]))
}
fn expression(e: &Expression, observation: bool) -> Result<Data> {
    match e {
        Expression::Term(t) => term(t, observation),
        Expression::Call(op, arguments) => Ok(Data::object([
            ("operator", operator(*op).into()),
            (
                "arguments",
                Data::List(
                    arguments
                        .iter()
                        .map(|e| expression(e, observation))
                        .collect::<Result<_>>()?,
                ),
            ),
        ])),
    }
}
fn clause(c: &Clause, observation: bool) -> Result<Data> {
    match c {
        Clause::Relation { atom: a, negative } => {
            let Data::Map(mut fields) = atom(a, observation)? else {
                unreachable!()
            };
            fields.insert("not".into(), (*negative).into());
            Ok(Data::Map(fields))
        }
        Clause::Guard { expression: e, .. } => Ok(Data::object([
            ("mode", "guard-expression".into()),
            ("expression", expression(e, observation)?),
        ])),
        Clause::Compute {
            output,
            expression: e,
            ..
        } => Ok(Data::object([
            ("mode", "compute-expression".into()),
            ("output", variable(*output).into()),
            ("expression", expression(e, observation)?),
        ])),
        Clause::Reduce {
            output,
            operator,
            atom: a,
            inputs,
        } => {
            let Data::Map(mut fields) = atom(a, observation)? else {
                unreachable!()
            };
            fields.extend([
                ("mode".into(), "reduce".into()),
                ("output".into(), variable(*output).into()),
                (
                    "inputs".into(),
                    Data::List(inputs.iter().map(|id| variable(*id).into()).collect()),
                ),
                (
                    "operator".into(),
                    match operator {
                        Reducer::Count => "count",
                        Reducer::Sum => "sum",
                        Reducer::Mean => "mean",
                        Reducer::Min => "min",
                        Reducer::Max => "max",
                    }
                    .into(),
                ),
            ]);
            Ok(Data::Map(fields))
        }
    }
}
fn operator(op: Operator) -> &'static str {
    match op {
        Operator::Less => "<",
        Operator::LessEqual => "<=",
        Operator::Greater => ">",
        Operator::GreaterEqual => ">=",
        Operator::NumericEqual => "=",
        Operator::Equal => "equal?",
        Operator::ImmediateEqual => "eq?",
        Operator::StringEqual => "string=?",
        Operator::Add => "+",
        Operator::Subtract => "-",
        Operator::Multiply => "*",
        Operator::Not => "not",
        Operator::Even => "even?",
        Operator::Odd => "odd?",
        Operator::Zero => "zero?",
        Operator::Positive => "positive?",
        Operator::Negative => "negative?",
        Operator::And => "and",
        Operator::Or => "or",
        Operator::Identity => "identity",
        Operator::StringAppend => "string-append",
        Operator::SymbolToString => "symbol->string",
        Operator::StringToSymbol => "string->symbol",
        Operator::VectorShape => "vector-shape?",
        Operator::VectorRef => "vector-ref",
    }
}
