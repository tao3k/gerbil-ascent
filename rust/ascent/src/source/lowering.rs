//! Runtime loading of Scheme rule data; no compiler, evaluator or JSON bridge.
use super::reader::{self, Datum, invalid};
use crate::{
    Atom, Clause, Expression, Operator, Program, Reducer, Relation, Result, Rule, Term, Type, Value,
};
use std::collections::{BTreeMap, BTreeSet, HashSet};

fn list(datum: &Datum) -> Result<&[Datum]> {
    match datum {
        Datum::List(items) => Ok(items),
        _ => Err(invalid("proper ASCENT form required")),
    }
}
fn name(datum: &Datum) -> Result<&str> {
    match datum {
        Datum::Atom(name) if !name.is_empty() && name.chars().count() <= 128 => Ok(name),
        _ => Err(invalid("ASCENT name required")),
    }
}
fn relation(items: &[Datum], general: bool) -> Result<Relation> {
    let [_, label, columns, rest @ ..] = items else {
        return Err(invalid("typed relation declaration required"));
    };
    if !rest.is_empty() && (!general || rest.len() != 1) {
        return Err(invalid("relation source declaration shape"));
    }
    let columns = list(columns)?
        .iter()
        .map(|column| {
            if general && matches!(column, Datum::Atom(_)) {
                name(column)?;
                return Ok(Type::Any);
            }
            let [label, predicate] = list(column)? else {
                return Err(invalid("typed column required"));
            };
            name(label)?;
            match name(predicate)? {
                "integer?" | "exact-integer?" => Ok(Type::Integer),
                "boolean?" => Ok(Type::Boolean),
                "symbol?" => Ok(Type::Symbol),
                "string?" => Ok(Type::Text),
                _ => Err(invalid("unsupported column predicate")),
            }
        })
        .collect::<Result<Vec<_>>>()?;
    if columns.len() > 16 {
        return Err(invalid("ASCENT column bound"));
    }
    let mut relation = Relation::new(name(label)?, columns, true);
    if let Some(rows) = rest.first() {
        relation.rows = initial_rows(rows)?;
    }
    Ok(relation)
}
fn quoted_scalar(datum: &Datum) -> Result<Value> {
    match datum {
        Datum::Atom(symbol) if !numeric_name(symbol) && !symbol.starts_with('#') => {
            Ok(Value::Symbol(name(datum)?.into()))
        }
        _ => literal(datum),
    }
}
fn initial_rows(datum: &Datum) -> Result<Vec<crate::Row>> {
    let raw = list(datum)?;
    if raw.is_empty() {
        return Ok(Vec::new());
    }
    let [quote, rows] = raw else {
        return Err(invalid("quoted initial rows required"));
    };
    if name(quote)? != "quote" {
        return Err(invalid("quoted initial rows required"));
    }
    list(rows)?
        .iter()
        .map(|row| {
            list(row)?
                .iter()
                .map(quoted_scalar)
                .collect::<Result<Vec<_>>>()
                .map(Into::into)
        })
        .collect()
}
fn literal(datum: &Datum) -> Result<Value> {
    match datum {
        Datum::Text(text) => Ok(Value::Text(text.clone().into())),
        Datum::Atom(atom) if atom == "#t" => Ok(Value::Boolean(true)),
        Datum::Atom(atom) if atom == "#f" => Ok(Value::Boolean(false)),
        Datum::Atom(atom) => atom
            .parse::<num_bigint::BigInt>()
            .map(Value::Integer)
            .map_err(|_| invalid("exact integer literal required")),
        Datum::List(items) => match items.as_slice() {
            [quote, symbol] if name(quote)? == "quote" => match symbol {
                Datum::Atom(s) if !numeric_name(s) && !s.starts_with('#') => {
                    Ok(Value::Symbol(name(symbol)?.into()))
                }
                _ => literal(symbol),
            },
            _ => Err(invalid("inert scalar literal required")),
        },
    }
}
fn term(datum: &Datum, variables: &mut BTreeMap<String, u32>) -> Result<Term> {
    match datum {
        Datum::Atom(atom) if atom == "_" => Ok(Term::Wildcard),
        Datum::Atom(atom)
            if !atom.starts_with('#')
                && atom.parse::<num_bigint::BigInt>().is_err()
                && !numeric_name(atom) =>
        {
            name(datum)?;
            let next = u32::try_from(variables.len()).map_err(|_| invalid("variable bound"))?;
            Ok(Term::Variable(
                *variables.entry(atom.clone()).or_insert(next),
            ))
        }
        Datum::List(items) if items.len() == 2 && name(&items[0])? == "lit" => {
            literal(&items[1]).map(Term::Literal)
        }
        _ => literal(datum).map(Term::Literal),
    }
}
fn atom(datum: &Datum, variables: &mut BTreeMap<String, u32>) -> Result<Atom> {
    let items = list(datum)?;
    let (label, terms) = items
        .split_first()
        .ok_or_else(|| invalid("nonempty atom required"))?;
    Ok(Atom::new(
        name(label)?,
        terms
            .iter()
            .map(|t| term(t, variables))
            .collect::<Result<_>>()?,
    ))
}
fn numeric_name(atom: &str) -> bool {
    let rest = atom.strip_prefix(['+', '-']).unwrap_or(atom);
    rest.chars().next().is_some_and(|c| c.is_ascii_digit())
}
fn expression(
    datum: &Datum,
    variables: &mut BTreeMap<String, u32>,
    allowed: Option<&BTreeSet<String>>,
) -> Result<Expression> {
    if let Datum::List(items) = datum
        && let Some(Datum::Atom(tag)) = items.first()
    {
        if matches!(tag.as_str(), "quote" | "lit" | "value") {
            let [_, value] = items.as_slice() else {
                return Err(invalid("operator literal arity"));
            };
            return Ok(Expression::Term(Term::Literal(if tag == "quote" {
                literal(datum)?
            } else {
                literal(value)?
            })));
        }
        let operator =
            Operator::named(tag).ok_or_else(|| invalid("unknown closed scalar operator"))?;
        if !operator.arity(items.len() - 1) {
            return Err(invalid("operator arity"));
        }
        return Ok(Expression::Call(
            operator,
            items[1..]
                .iter()
                .map(|e| expression(e, variables, allowed))
                .collect::<Result<_>>()?,
        ));
    }
    let term = term(datum, variables)?;
    if let Term::Variable(_) = term
        && allowed.is_some_and(|inputs| !matches!(datum, Datum::Atom(s) if inputs.contains(s)))
    {
        return Err(invalid("guard variable missing from inputs"));
    }
    Ok(Expression::Term(term))
}
fn guard(items: &[Datum], variables: &mut BTreeMap<String, u32>, general: bool) -> Result<Clause> {
    let [_, inputs, body] = items else {
        return Err(invalid("guard inputs/expression required"));
    };
    let raw_inputs = list(inputs)?;
    let allowed = raw_inputs
        .iter()
        .map(|d| name(d).map(str::to_owned))
        .collect::<Result<BTreeSet<_>>>()?;
    if allowed.len() != raw_inputs.len()
        || allowed
            .iter()
            .any(|name| Operator::named(name).is_some() || matches!(name.as_str(), "if" | "quote"))
    {
        return Err(invalid("guard inputs must be distinct variable names"));
    }
    if !general {
        let call = list(body)?;
        let Some(operation) = call.first() else {
            return Err(invalid("checked guard operator required"));
        };
        if !matches!(name(operation)?, "<" | "even?") || &call[1..] != raw_inputs {
            return Err(invalid(
                "only closed checked ASCENT if operators are supported by read_rules",
            ));
        }
    }
    // All declared inputs must be bound, including unused inputs.
    let inputs = raw_inputs
        .iter()
        .map(|d| match term(d, variables)? {
            Term::Variable(id) => Ok(id),
            _ => Err(invalid("guard input variable required")),
        })
        .collect::<Result<_>>()?;
    let expression = expression(body, variables, Some(&allowed))?;
    Ok(Clause::Guard { inputs, expression })
}
fn substitute(datum: &Datum, names: &BTreeMap<String, Datum>) -> Datum {
    match datum {
        Datum::Atom(name) => names.get(name).cloned().unwrap_or_else(|| datum.clone()),
        Datum::List(items) if !matches!(items.first(), Some(Datum::Atom(s)) if s == "quote") => {
            Datum::List(items.iter().map(|d| substitute(d, names)).collect())
        }
        _ => datum.clone(),
    }
}
fn procedure_body(procedure: &Datum, inputs: &Datum) -> Result<Datum> {
    let inputs = list(inputs)?;
    if let Datum::Atom(operator) = procedure {
        if Operator::named(operator).is_none() {
            return Err(invalid("unknown closed procedure"));
        }
        return Ok(Datum::List(
            std::iter::once(procedure.clone())
                .chain(inputs.iter().cloned())
                .collect(),
        ));
    }
    let [lambda, parameters, body] = list(procedure)? else {
        return Err(invalid("closed lambda required"));
    };
    let parameters = list(parameters)?;
    if name(lambda)? != "lambda" || parameters.len() != inputs.len() {
        return Err(invalid("closed lambda arity"));
    }
    let mut renames = BTreeMap::new();
    for (parameter, input) in parameters.iter().zip(inputs) {
        if renames
            .insert(name(parameter)?.to_owned(), input.clone())
            .is_some()
        {
            return Err(invalid("duplicate lambda parameter"));
        }
    }
    Ok(substitute(body, &renames))
}
fn binding(
    items: &[Datum],
    variables: &mut BTreeMap<String, u32>,
    procedure: bool,
) -> Result<Clause> {
    let [tag, output, inputs, body] = items else {
        return Err(invalid("binding output/inputs/expression required"));
    };
    let body = if procedure {
        procedure_body(body, inputs)?
    } else {
        body.clone()
    };
    let Clause::Guard { inputs, expression } =
        guard(&[tag.clone(), inputs.clone(), body], variables, true)?
    else {
        unreachable!()
    };
    let Term::Variable(output) = term(output, variables)? else {
        return Err(invalid("binding output variable required"));
    };
    Ok(Clause::Compute {
        output,
        inputs,
        expression,
    })
}
fn native_guard(items: &[Datum], variables: &mut BTreeMap<String, u32>) -> Result<Clause> {
    let [tag, inputs, procedure] = items else {
        return Err(invalid("guard inputs/procedure required"));
    };
    let body = procedure_body(procedure, inputs)?;
    guard(&[tag.clone(), inputs.clone(), body], variables, true)
}
fn aggregate(items: &[Datum], variables: &mut BTreeMap<String, u32>) -> Result<Clause> {
    let [_, output, operation, inputs, target] = items else {
        return Err(invalid("aggregate output/operation/inputs/atom required"));
    };
    let operation = name(operation)?
        .strip_prefix("gerbil-ascent-")
        .ok_or_else(|| invalid("unsupported aggregate procedure"))?;
    let operator =
        Reducer::named(operation).ok_or_else(|| invalid("unsupported aggregate procedure"))?;
    let atom = atom(target, variables)?;
    let inputs = list(inputs)?
        .iter()
        .map(|d| match term(d, variables)? {
            Term::Variable(id) => Ok(id),
            _ => Err(invalid("aggregate input variable required")),
        })
        .collect::<Result<_>>()?;
    let Term::Variable(output) = term(output, variables)? else {
        return Err(invalid("aggregate output variable required"));
    };
    Ok(Clause::Reduce {
        output,
        operator,
        atom,
        inputs,
    })
}
fn clause(datum: &Datum, variables: &mut BTreeMap<String, u32>, general: bool) -> Result<Clause> {
    let items = list(datum)?;
    let tag = items
        .first()
        .ok_or_else(|| invalid("nonempty clause required"))?;
    match name(tag)? {
        "not" => {
            let [_, target] = items else {
                return Err(invalid("negation needs one atom"));
            };
            Ok(Clause::negative(atom(target, variables)?))
        }
        "if" => guard(items, variables, general),
        "let" if general => binding(items, variables, false),
        "bind" if general => binding(items, variables, true),
        "guard" if general => native_guard(items, variables),
        "aggregate" if general => aggregate(items, variables),
        "where" if general => {
            let [_, body] = items else {
                return Err(invalid("where call required"));
            };
            let checked = expression(body, variables, None)?;
            let Expression::Call(op, _) = &checked else {
                return Err(invalid("where operator required"));
            };
            if !matches!(op, Operator::Less | Operator::Even) {
                return Err(invalid("unknown checked where operator"));
            }
            Ok(Clause::Guard {
                inputs: Vec::new(),
                expression: checked,
            })
        }
        "compute" if general => {
            let [_, output, body] = items else {
                return Err(invalid("compute output/call required"));
            };
            let checked = expression(body, variables, None)?;
            let Expression::Call(op, _) = &checked else {
                return Err(invalid("compute operator required"));
            };
            if !matches!(op, Operator::Add | Operator::Identity) {
                return Err(invalid("unknown checked compute operator"));
            }
            let Term::Variable(output) = term(output, variables)? else {
                return Err(invalid("compute variable output required"));
            };
            Ok(Clause::Compute {
                inputs: Vec::new(),
                output,
                expression: checked,
            })
        }
        "reduce" if general => {
            let [_, output, mode, target] = items else {
                return Err(invalid("reduce output/mode/atom required"));
            };
            let (operator, inputs) = list(mode)?
                .split_first()
                .ok_or_else(|| invalid("reduce mode required"))?;
            let operator =
                Reducer::named(name(operator)?).ok_or_else(|| invalid("unknown reducer"))?;
            let atom = atom(target, variables)?;
            let inputs = inputs
                .iter()
                .map(|d| match term(d, variables)? {
                    Term::Variable(id) => Ok(id),
                    _ => Err(invalid("reducer input variable required")),
                })
                .collect::<Result<_>>()?;
            let Term::Variable(output) = term(output, variables)? else {
                return Err(invalid("reduce output variable required"));
            };
            Ok(Clause::Reduce {
                output,
                operator,
                atom,
                inputs,
            })
        }
        "import" | "include" | "guard" | "bind" | "let" | "for" | "if-let" | "match"
        | "aggregate" | "where" | "compute" | "reduce" => {
            Err(invalid("unsupported executable ASCENT source clause"))
        }
        _ => Ok(Clause::positive(atom(datum, variables)?)),
    }
}
fn rule(items: &[Datum], general: bool) -> Result<Vec<Rule>> {
    if items.len() < if general { 2 } else { 3 } || name(&items[1])? != "<--" {
        return Err(invalid("ASCENT head <-- body required"));
    }
    let mut variables = BTreeMap::new();
    let body = items[2..]
        .iter()
        .map(|datum| clause(datum, &mut variables, general))
        .collect::<Result<Vec<_>>>()?;
    let head = list(&items[0])?;
    let heads = if head.first().is_some_and(|h| matches!(h, Datum::Atom(_))) {
        vec![&items[0]]
    } else {
        head.iter().collect()
    };
    if heads.is_empty() {
        return Err(invalid("nonempty rule head required"));
    }
    heads
        .into_iter()
        .map(|head| {
            Ok(Rule {
                head: atom(head, &mut variables)?,
                body: body.clone(),
            })
        })
        .collect()
}
impl Program {
    /// Read existing `(ascent ...)` / `(ascent-fragment ...)` rule fragments.
    /// # Errors
    /// Rejects malformed data, host forms and currently unsupported constructs.
    /// Runtime loading requires neither a Scheme VM nor a downstream compiler.
    pub fn read_rule_sources(sources: &[&str]) -> Result<Self> {
        load(sources, false)
    }
    /// Load native pure Scheme DSL, including closed guards and checked operators.
    /// # Errors
    /// Rejects unsupported forms and invalid relational declarations.
    pub fn read_sources(sources: &[&str]) -> Result<Self> {
        load(sources, true)
    }
}
fn load(sources: &[&str], general: bool) -> Result<Program> {
    if sources.is_empty() || sources.len() > 16 {
        return Err(invalid("1..16 rule fragments required"));
    }
    if sources.iter().map(|source| source.len()).sum::<usize>() > 262_144 {
        return Err(invalid("total source byte bound"));
    }
    let mut program = Program::default();
    let mut seen_rules = HashSet::new();
    let mut names = BTreeMap::new();
    for source in sources {
        append(
            &mut program,
            &mut names,
            &mut seen_rules,
            &reader::read(source)?,
            general,
        )?;
    }
    finish(program)
}
pub(crate) enum NativePart {
    Declaration(Datum),
    Included(Program),
}
pub(crate) fn native_parts(parts: Vec<NativePart>) -> Result<Program> {
    let mut program = Program::default();
    let mut names = BTreeMap::new();
    let mut seen = HashSet::new();
    for part in parts {
        match part {
            NativePart::Declaration(form) => append(
                &mut program,
                &mut names,
                &mut seen,
                &Datum::List(vec![Datum::Atom("ascent".into()), form]),
                true,
            )?,
            NativePart::Included(included) => merge_native(&mut program, &mut names, included)?,
        }
    }
    if program.relations.is_empty() && program.rules.is_empty() {
        return Ok(program);
    }
    finish(program)
}
fn merge_native(
    program: &mut Program,
    names: &mut BTreeMap<String, Vec<Type>>,
    included: Program,
) -> Result<()> {
    for relation in included.relations {
        if names
            .insert(relation.name.clone(), relation.columns.clone())
            .is_some()
        {
            return Err(invalid("duplicate included relation declaration"));
        }
        program.relations.push(relation);
    }
    program.rules.extend(included.rules);
    program.fact_limits = program.fact_limits.tighten(included.fact_limits)?;
    Ok(())
}
fn finish(mut program: Program) -> Result<Program> {
    let heads: BTreeSet<_> = program
        .rules
        .iter()
        .map(|r| r.head.relation.as_str())
        .collect();
    for declaration in &mut program.relations {
        declaration.source =
            !heads.contains(declaration.name.as_str()) && declaration.rows.is_empty();
    }
    if program.relations.is_empty() || program.relations.len() > 128 || program.rules.len() > 256 {
        return Err(invalid("ASCENT catalog bounds"));
    }
    crate::graph::Graph::build(program.clone())?;
    Ok(program)
}
fn fact_rules(items: &[Datum]) -> Result<Vec<Rule>> {
    let many = matches!(items.first(), Some(Datum::Atom(s)) if s == "facts");
    if (!many && items.len() != 2) || items.len() < 2 {
        return Err(invalid("fact declaration shape"));
    }
    items[1..]
        .iter()
        .map(|target| {
            Ok(Rule {
                head: atom(target, &mut BTreeMap::new())?,
                body: Vec::new(),
            })
        })
        .collect()
}
fn append(
    program: &mut Program,
    names: &mut BTreeMap<String, Vec<Type>>,
    seen_rules: &mut HashSet<Datum>,
    fragment: &Datum,
    general: bool,
) -> Result<()> {
    let (tag, forms) = list(fragment)?
        .split_first()
        .ok_or_else(|| invalid("ASCENT fragment required"))?;
    if !matches!(name(tag)?, "ascent" | "ascent-fragment") {
        return Err(invalid(
            "ASCENT fragment required; host forms are not executable",
        ));
    }
    for form in forms {
        let items = list(form)?;
        if general && items.first() == Some(&Datum::Atom("bounds".into())) {
            let [_, input, derived, output] = items else {
                return Err(invalid("bounds needs input/derived/output limits"));
            };
            let limit = |datum: &Datum| -> Result<Option<usize>> {
                let text = name(datum)?;
                if text == "+inf.0" {
                    return Ok(None);
                }
                text.parse::<usize>()
                    .map(Some)
                    .map_err(|_| invalid("positive fact limit required"))
            };
            program.fact_limits = program.fact_limits.tighten(crate::FactLimits {
                input: limit(input)?,
                derived: limit(derived)?,
                output: limit(output)?,
            })?;
            continue;
        }
        if general && matches!(items.first(), Some(Datum::Atom(s)) if s == "fact" || s == "facts") {
            program.rules.extend(fact_rules(items)?);
            continue;
        }
        if items.first().is_some_and(
            |tag| matches!(tag, Datum::Atom(s) if s == "relation" || (general && s == "lattice")),
        ) {
            let declaration = if items.first() == Some(&Datum::Atom("lattice".into())) {
                lattice(items)?
            } else {
                relation(items, general)?
            };
            match names.entry(declaration.name.clone()) {
                std::collections::btree_map::Entry::Vacant(entry) => {
                    entry.insert(declaration.columns.clone());
                    program.relations.push(declaration);
                }
                std::collections::btree_map::Entry::Occupied(entry) => {
                    if entry.get() != &declaration.columns {
                        return Err(invalid("conflicting relation declarations"));
                    }
                }
            }
        } else {
            if !seen_rules.insert(form.clone()) {
                return Err(invalid("duplicate ASCENT rule"));
            }
            program.rules.extend(rule(items, general)?);
        }
    }
    Ok(())
}

fn lattice(items: &[Datum]) -> Result<Relation> {
    let [_, name, columns, rows, join] = items else {
        return Err(invalid("lattice declaration shape"));
    };
    let mut declaration = relation(
        &[
            Datum::Atom("relation".into()),
            name.clone(),
            columns.clone(),
            rows.clone(),
        ],
        true,
    )?;
    declaration.lattice = Some(match join {
        Datum::Atom(name) if name == "min" => crate::LatticeJoin::Min,
        Datum::Atom(name) if name == "max" => crate::LatticeJoin::Max,
        _ => {
            return Err(invalid(
                "lattice join requires a checked numeric semilattice",
            ));
        }
    });
    Ok(declaration)
}
