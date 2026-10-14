//! Bounded lexical evaluation of loaded Scheme definitions.
use super::objects::{Arena, EnvId, Id, Object, Procedure, fail};
use crate::{Engine, Result, source::Datum};
use num_bigint::BigInt;
use num_rational::BigRational;
use std::{
    collections::BTreeMap,
    time::{Duration, Instant},
};
pub(super) struct Evaluation<'a> {
    pub arena: &'a mut Arena,
    pub engine: &'a Engine,
    steps: usize,
    deadline: Instant,
}
impl<'a> Evaluation<'a> {
    pub fn new(arena: &'a mut Arena, engine: &'a Engine) -> Self {
        Self {
            arena,
            engine,
            steps: 0,
            deadline: Instant::now() + Duration::from_secs(1),
        }
    }
    pub fn invoke(&mut self, procedure: Id, args: &[Id]) -> Result<(Id, usize)> {
        let values = self.apply(procedure, args, 0)?;
        let count = values.len();
        let root = if count == 1 {
            values[0]
        } else {
            self.arena.add(Object::Vector(values))?
        };
        self.check(0)?;
        Ok((root, count))
    }
    pub(super) fn check(&mut self, depth: usize) -> Result<()> {
        if depth > 128 {
            return Err(fail("Scheme call depth bound"));
        }
        self.steps += 1;
        if self.steps > 1_000_000 {
            return Err(fail("Scheme evaluation work bound"));
        }
        if self.engine.is_closed() {
            return Err(crate::Error::Closed);
        }
        if Instant::now() >= self.deadline {
            return Err(crate::Error::Timeout);
        }
        Ok(())
    }
    pub fn single(&mut self, datum: &Datum, env: EnvId, depth: usize) -> Result<Id> {
        let values = self.eval(datum, env, depth)?;
        match values.as_slice() {
            [value] => Ok(*value),
            _ => Err(fail("single Scheme value required")),
        }
    }
    pub fn sequence(&mut self, body: &[Datum], env: EnvId, depth: usize) -> Result<Vec<Id>> {
        let mut result = vec![self.arena.add(Object::Void)?];
        for datum in body {
            result = self.eval(datum, env, depth + 1)?;
        }
        Ok(result)
    }
    pub fn eval(&mut self, datum: &Datum, env: EnvId, depth: usize) -> Result<Vec<Id>> {
        self.check(depth)?;
        let Datum::List(items) = datum else {
            return Ok(vec![match datum {
                Datum::Text(v) => self.arena.add(Object::Text(v.clone()))?,
                Datum::Atom(v) => match v.as_str() {
                    "#t" => self.arena.add(Object::Boolean(true))?,
                    "#f" => self.arena.add(Object::Boolean(false))?,
                    _ => {
                        if let Some(v) = number(v) {
                            self.arena.add(Object::Number(v))?
                        } else if let Some(v) = inexact(v) {
                            self.arena.add(Object::Inexact(v))?
                        } else if let Some(v) = character(v) {
                            self.arena.add(Object::Character(v))?
                        } else {
                            self.arena.lookup(env, v)?
                        }
                    }
                },
                Datum::List(_) => unreachable!(),
            }]);
        };
        if items.is_empty() {
            return Ok(vec![self.arena.add(Object::Null)?]);
        }
        let name = atom(&items[0]).unwrap_or("");
        let args = &items[1..];
        match name {
            "ascent" | "ascent-fragment" => self.ascent_form(datum, env, depth),
            "hash" => self.hash_form(args, env, depth),
            "quote" if args.len() == 1 => Ok(vec![self.quote(&args[0], depth + 1)?]),
            "begin" => self.sequence(args, env, depth),
            "if" if (2..=3).contains(&args.len()) => {
                let condition = self.single(&args[0], env, depth + 1)?;
                if self.arena.truth(condition)? {
                    self.eval(&args[1], env, depth + 1)
                } else if args.len() == 3 {
                    self.eval(&args[2], env, depth + 1)
                } else {
                    Ok(vec![self.arena.add(Object::Void)?])
                }
            }
            "and" | "or" => {
                let mut result = self.arena.add(Object::Boolean(name == "and"))?;
                for arg in args {
                    result = self.single(arg, env, depth + 1)?;
                    if self.arena.truth(result)? == (name == "or") {
                        break;
                    }
                }
                Ok(vec![result])
            }
            "lambda" if args.len() >= 2 => {
                let (parameters, rest) = parameters(&args[0])?;
                Ok(vec![self.arena.add(Object::Procedure(
                    Procedure::Closure {
                        parameters: parameters.into(),
                        rest: rest.map(Into::into),
                        body: args[1..].to_vec().into(),
                        env,
                    },
                ))?])
            }
            "def" | "define" => self.define(args, env, depth),
            "set!" if args.len() == 2 => {
                let name = atom(&args[0]).ok_or_else(|| fail("set! binding required"))?;
                let value = self.single(&args[1], env, depth + 1)?;
                self.arena.assign(env, name, value)?;
                Ok(vec![self.arena.add(Object::Void)?])
            }
            "let" | "let*" => self.local(args, env, depth, name == "let*"),
            "let-values" | "let*-values" => {
                self.local_values(args, env, depth, name == "let*-values")
            }
            "defrules" => {
                self.define_macro(args, env)?;
                Ok(vec![self.arena.add(Object::Void)?])
            }
            "define-evidence" => self.define_evidence(args, env, depth),
            _ => {
                if let Some((expansion, scope)) = self.expand(name, datum, env)? {
                    return self.eval(&expansion, scope, depth + 1);
                }
                let procedure = self.single(&items[0], env, depth + 1)?;
                let mut values = Vec::new();
                for arg in args {
                    values.push(self.single(arg, env, depth + 1)?);
                }
                self.apply(procedure, &values, depth + 1)
            }
        }
    }
    fn hash_form(&mut self, args: &[Datum], env: EnvId, depth: usize) -> Result<Vec<Id>> {
        let mut entries = Vec::new();
        for field in args {
            let Datum::List(pair) = field else {
                return Err(fail("hash field pair required"));
            };
            if pair.len() != 2 {
                return Err(fail("hash field arity"));
            }
            entries.push((
                self.single(&pair[0], env, depth + 1)?,
                self.single(&pair[1], env, depth + 1)?,
            ));
        }
        Ok(vec![self.arena.add(Object::Table {
            entries,
            identity: false,
        })?])
    }
    pub fn apply(&mut self, procedure: Id, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        self.check(depth)?;
        let procedure = match self.arena.get(procedure)? {
            Object::Procedure(procedure) => procedure.clone(),
            _ => return Err(fail("Scheme value is not a procedure")),
        };
        match procedure {
            Procedure::Rows(snapshot, _) => {
                let [name] = args else {
                    return Err(fail("rows-of requires one relation"));
                };
                let name = super::constructors::Admission::new(self.arena, 0)?.name(*name)?;
                let rows = snapshot
                    .relations
                    .get(&name)
                    .ok_or_else(|| fail("unknown solution relation"))?;
                self.arena.rows_object(rows).map(|root| vec![root])
            }
            Procedure::Query(name) => {
                let [solution] = args else {
                    return Err(fail("prepared query requires one solution"));
                };
                let Object::Completed(snapshot, _) = self.arena.get(*solution)?.clone() else {
                    return Err(fail("completed relational solution required"));
                };
                let rows = snapshot
                    .relations
                    .get(&name)
                    .ok_or_else(|| fail("foreign prepared query"))?;
                self.arena.rows_object(rows).map(|root| vec![root])
            }
            Procedure::Builtin(name) => self.primitive(name, args, depth + 1),
            Procedure::Closure {
                parameters,
                rest,
                body,
                env,
            } => {
                if args.len() < parameters.len()
                    || (rest.is_none() && args.len() != parameters.len())
                {
                    return Err(fail("Scheme procedure arity mismatch"));
                }
                let local = self.arena.env(Some(env))?;
                for (name, value) in parameters.iter().zip(args) {
                    self.arena.bind(local, name.clone(), *value);
                }
                if let Some(name) = rest {
                    let tail = self.arena.list(&args[parameters.len()..])?;
                    self.arena.bind(local, name.to_string(), tail);
                }
                self.sequence(&body, local, depth + 1)
            }
        }
    }
    fn define(&mut self, args: &[Datum], env: EnvId, depth: usize) -> Result<Vec<Id>> {
        let (name, value) = match args {
            [Datum::Atom(name), expression] => {
                (name.clone(), self.single(expression, env, depth + 1)?)
            }
            [Datum::List(signature), body @ ..] if !signature.is_empty() && !body.is_empty() => {
                let name = atom(&signature[0])
                    .ok_or_else(|| fail("definition name required"))?
                    .to_owned();
                let (parameters, rest) = parameters(&Datum::List(signature[1..].to_vec()))?;
                let value = self.arena.add(Object::Procedure(Procedure::Closure {
                    parameters: parameters.into(),
                    rest: rest.map(Into::into),
                    body: body.to_vec().into(),
                    env,
                }))?;
                (name, value)
            }
            _ => return Err(fail("invalid Scheme definition")),
        };
        validate_binding(&name)?;
        self.arena.bind(env, name, value);
        Ok(vec![self.arena.add(Object::Void)?])
    }
    fn local(
        &mut self,
        args: &[Datum],
        env: EnvId,
        depth: usize,
        sequential: bool,
    ) -> Result<Vec<Id>> {
        let [bindings, body @ ..] = args else {
            return Err(fail("let bindings and body required"));
        };
        if body.is_empty() {
            return Err(fail("let body required"));
        }
        let Datum::List(bindings) = bindings else {
            return Err(fail("let binding list required"));
        };
        let mut local = self.arena.env(Some(env))?;
        // Gerbil also permits (let (name value) body).
        let normalized = if bindings.len() == 2 && atom(&bindings[0]).is_some() {
            vec![Datum::List(bindings.clone())]
        } else {
            bindings.clone()
        };
        for binding in normalized {
            let Datum::List(binding) = binding else {
                return Err(fail("invalid let binding"));
            };
            let [Datum::Atom(name), expression] = binding.as_slice() else {
                return Err(fail("invalid let binding"));
            };
            validate_binding(name)?;
            if !sequential && self.arena.environments[&local].bindings.contains_key(name) {
                return Err(fail("duplicate let binding"));
            }
            let value = self.single(expression, if sequential { local } else { env }, depth + 1)?;
            if sequential {
                local = self.arena.env(Some(local))?;
            }
            self.arena.bind(local, name.clone(), value);
        }
        self.sequence(body, local, depth + 1)
    }
    fn quote(&mut self, datum: &Datum, depth: usize) -> Result<Id> {
        self.check(depth)?;
        match datum {
            Datum::Text(v) => self.arena.add(Object::Text(v.clone())),
            Datum::Atom(v) => {
                if v == "#t" || v == "#f" {
                    self.arena.add(Object::Boolean(v == "#t"))
                } else if let Some(v) = number(v) {
                    self.arena.add(Object::Number(v))
                } else if let Some(v) = inexact(v) {
                    self.arena.add(Object::Inexact(v))
                } else if let Some(v) = character(v) {
                    self.arena.add(Object::Character(v))
                } else {
                    validate_symbol(v)?;
                    self.arena.symbol(v, true)
                }
            }
            Datum::List(items) => {
                let dot = items.iter().position(|v| atom(v) == Some("."));
                if let Some(dot) = dot {
                    if dot == 0 || dot + 2 != items.len() {
                        return Err(fail("invalid dotted datum"));
                    }
                    let mut tail = self.quote(&items[dot + 1], depth + 1)?;
                    for item in items[..dot].iter().rev() {
                        let head = self.quote(item, depth + 1)?;
                        tail = self.arena.add(Object::Pair(head, tail))?;
                    }
                    Ok(tail)
                } else {
                    let values = items
                        .iter()
                        .map(|v| self.quote(v, depth + 1))
                        .collect::<Result<Vec<_>>>()?;
                    self.arena.list(&values)
                }
            }
        }
    }
    fn define_evidence(&mut self, args: &[Datum], env: EnvId, depth: usize) -> Result<Vec<Id>> {
        if matches!(args.get(1),Some(Datum::List(values)) if values.first()==Some(&Datum::Atom("sources".into())))
        {
            return self.define_declared(args, env, depth);
        }
        if !(2..=3).contains(&args.len()) {
            return Err(fail("invalid evidence definition"));
        }
        let mut body = vec![
            Datum::Atom("ascent-evidence-module".into()),
            args[1].clone(),
        ];
        body.push(
            args.get(2)
                .cloned()
                .unwrap_or_else(|| Datum::Atom("#f".into())),
        );
        self.define(&[args[0].clone(), Datum::List(body)], env, depth)
    }
    fn define_macro(&mut self, args: &[Datum], env: EnvId) -> Result<()> {
        let [Datum::Atom(name), Datum::List(literals), clauses @ ..] = args else {
            return Err(fail("invalid defrules"));
        };
        validate_binding(name)?;
        if !literals.is_empty() {
            return Err(fail("defrules literal bindings require hygienic lowering"));
        }
        let mut rules = Vec::new();
        for clause in clauses {
            let Datum::List(parts) = clause else {
                return Err(fail("invalid defrules clause"));
            };
            let [pattern, template] = parts.as_slice() else {
                return Err(fail("invalid defrules clause"));
            };
            if !matches!(pattern, Datum::List(_)) {
                return Err(fail("proper defrules pattern required"));
            }
            validate_pattern(pattern)?;
            if contains_ellipsis(pattern) || contains_ellipsis(template) {
                return Err(fail("defrules ellipsis requires hygienic lowering"));
            }
            rules.push((pattern.clone(), template.clone()));
        }
        self.arena
            .environments
            .get_mut(&env)
            .expect("live scope")
            .macros
            .insert(name.clone(), rules);
        Ok(())
    }
    fn expand(&mut self, name: &str, datum: &Datum, env: EnvId) -> Result<Option<(Datum, EnvId)>> {
        let Some((definition, rules)) = self.macro_rules(name, env) else {
            return Ok(None);
        };
        validate_pattern(datum)?;
        let (template, captures) = rules
            .iter()
            .find_map(|(pattern, template)| {
                let mut captures = BTreeMap::new();
                matches_pattern(pattern, datum, &mut captures).then(|| (template.clone(), captures))
            })
            .ok_or_else(|| fail("no matching defrules clause"))?;
        expansion_weight(&template, &captures, 0)?;
        let scope = self.arena.env(Some(env))?;
        let expansion = self.expand_template(&template, &captures, definition, scope, false)?;
        Ok(Some((expansion, scope)))
    }
    fn macro_rules(&self, name: &str, mut env: EnvId) -> Option<(EnvId, Vec<(Datum, Datum)>)> {
        let mut name = name.to_owned();
        for _ in 0..256 {
            let scope = &self.arena.environments[&env];
            if let Some(rules) = scope.macros.get(&name) {
                return Some((env, rules.clone()));
            }
            match scope.bindings.get(&name) {
                Some(super::objects::Binding::Local(_)) => return None,
                Some(super::objects::Binding::Alias(target, binding)) => {
                    env = *target;
                    name = binding.clone();
                }
                None => env = scope.parent?,
            }
        }
        None
    }
    pub(super) fn expand_template(
        &mut self,
        datum: &Datum,
        captures: &BTreeMap<String, Datum>,
        definition: EnvId,
        scope: EnvId,
        quoted: bool,
    ) -> Result<Datum> {
        if matches!(datum,Datum::List(items) if matches!(items.first(),Some(Datum::Atom(tag)) if tag=="ascent" || tag=="ascent-fragment"))
        {
            return self.expand_dsl_template(datum, captures, definition, scope);
        }
        match datum {
            Datum::Atom(name) if captures.contains_key(name) => Ok(captures[name].clone()),
            Datum::Atom(name)
                if !quoted
                    && !matches!(
                        name.as_str(),
                        "quote" | "if" | "begin" | "and" | "or" | "#t" | "#f"
                    )
                    && number(name).is_none()
                    && character(name).is_none() =>
            {
                let alias = format!("#%module-macro-{scope}-{name}");
                self.arena
                    .environments
                    .get_mut(&scope)
                    .expect("live macro scope")
                    .bindings
                    .insert(
                        alias.clone(),
                        super::objects::Binding::Alias(definition, name.clone()),
                    );
                Ok(Datum::Atom(alias))
            }
            Datum::List(items) => {
                let quoted = quoted || items.first().and_then(atom) == Some("quote");
                if !quoted
                    && items.first().and_then(atom).is_some_and(|name| {
                        matches!(name, "lambda" | "let" | "let*" | "def" | "define" | "set!")
                    })
                {
                    return Err(fail(
                        "binding macro templates require hygienic binder lowering",
                    ));
                }
                Ok(Datum::List(
                    items
                        .iter()
                        .map(|v| self.expand_template(v, captures, definition, scope, quoted))
                        .collect::<Result<_>>()?,
                ))
            }
            _ => Ok(datum.clone()),
        }
    }
    fn expand_dsl_template(
        &mut self,
        datum: &Datum,
        captures: &BTreeMap<String, Datum>,
        definition: EnvId,
        scope: EnvId,
    ) -> Result<Datum> {
        let Datum::List(items) = datum else {
            return Err(fail("DSL template required"));
        };
        let mut forms = vec![items[0].clone()];
        for form in &items[1..] {
            let mut expanded = super::native_forms::substitute(form, captures);
            if let Datum::List(parts) = &mut expanded {
                match parts.first().and_then(atom) {
                    Some("relation" | "lattice") if parts.len() > 3 => {
                        parts[3] =
                            self.expand_template(&parts[3], captures, definition, scope, false)?;
                        if parts.len() == 5 {
                            parts[4] = self
                                .expand_template(&parts[4], captures, definition, scope, false)?;
                        }
                    }
                    Some("include") if parts.len() == 2 => {
                        parts[1] =
                            self.expand_template(&parts[1], captures, definition, scope, false)?;
                    }
                    _ => {}
                }
            }
            forms.push(expanded);
        }
        Ok(Datum::List(forms))
    }
}
pub(super) fn atom(datum: &Datum) -> Option<&str> {
    if let Datum::Atom(v) = datum {
        Some(v)
    } else {
        None
    }
}
pub(super) fn parameters(datum: &Datum) -> Result<(Vec<String>, Option<String>)> {
    if let Datum::Atom(rest) = datum {
        validate_binding(rest)?;
        return Ok((Vec::new(), Some(rest.clone())));
    }
    let Datum::List(items) = datum else {
        return Err(fail("lambda parameter list required"));
    };
    let mut names = Vec::new();
    let mut rest: Option<String> = None;
    let mut iter = items.iter();
    while let Some(item) = iter.next() {
        let name = atom(item).ok_or_else(|| fail("parameter identifier required"))?;
        if name == "." {
            rest = Some(
                atom(iter.next().ok_or_else(|| fail("rest parameter required"))?)
                    .ok_or_else(|| fail("invalid rest parameter"))?
                    .into(),
            );
            if iter.next().is_some() {
                return Err(fail("invalid rest parameters"));
            }
            break;
        }
        validate_binding(name)?;
        if names.iter().any(|v| v == name) {
            return Err(fail("duplicate parameter"));
        }
        names.push(name.into());
    }
    if let Some(name) = &rest {
        validate_binding(name)?;
    }
    if rest.as_ref().is_some_and(|v| names.contains(v)) {
        return Err(fail("duplicate rest parameter"));
    }
    Ok((names, rest))
}
pub(super) fn validate_binding(name: &str) -> Result<()> {
    validate_symbol(name)?;
    if name.is_empty()
        || name == "."
        || number(name).is_some()
        || character(name).is_some()
        || (name.chars().any(|c| c.is_ascii_digit()) && name.parse::<f64>().is_ok())
        || matches!(
            name,
            "#t" | "#f"
                | "if"
                | "lambda"
                | "def"
                | "define"
                | "set!"
                | "let"
                | "let*"
                | "quote"
                | "begin"
                | "and"
                | "or"
                | "defrules"
                | "define-evidence"
        )
    {
        return Err(fail("unsupported Scheme binding identifier"));
    }
    Ok(())
}
pub(super) fn number(text: &str) -> Option<BigRational> {
    if let Some((a, b)) = text.split_once('/') {
        let a = a.parse::<BigInt>().ok()?;
        let b = b.parse::<BigInt>().ok()?;
        if b == BigInt::from(0) {
            return None;
        }
        Some(BigRational::new(a, b))
    } else {
        text.parse::<BigInt>().ok().map(BigRational::from_integer)
    }
}
pub(super) fn character(text: &str) -> Option<char> {
    let text = text.strip_prefix("#\\")?;
    match text {
        "space" => Some(' '),
        "newline" => Some('\n'),
        _ => {
            let mut chars = text.chars();
            let c = chars.next()?;
            if chars.next().is_some() {
                None
            } else {
                Some(c)
            }
        }
    }
}
fn contains_ellipsis(datum: &Datum) -> bool {
    match datum {
        Datum::Atom(v) => v == "...",
        Datum::List(v) => v.iter().any(contains_ellipsis),
        Datum::Text(_) => false,
    }
}
fn matches_pattern(pattern: &Datum, value: &Datum, captures: &mut BTreeMap<String, Datum>) -> bool {
    match (pattern, value) {
        (Datum::Atom(name), _) if name == "_" => true,
        (Datum::Atom(name), Datum::Atom(value)) if number(name).is_some() => {
            number(name) == number(value)
        }
        (Datum::Atom(name), Datum::Atom(value)) if character(name).is_some() => {
            character(name) == character(value)
        }
        (Datum::Atom(name), _) if number(name).is_some() || character(name).is_some() => false,
        (Datum::Atom(name), _) if matches!(name.as_str(), "#t" | "#f") => pattern == value,
        (Datum::Atom(name), _) => {
            if let Some(previous) = captures.get(name) {
                previous == value
            } else {
                captures.insert(name.clone(), value.clone());
                true
            }
        }
        (Datum::List(a), Datum::List(b)) => {
            a.len() == b.len()
                && !b.iter().any(|v| atom(v) == Some("."))
                && a.iter()
                    .zip(b)
                    .all(|(a, b)| matches_pattern(a, b, captures))
        }
        (Datum::Text(a), Datum::Text(b)) => a == b,
        _ => false,
    }
}
fn validate_pattern(datum: &Datum) -> Result<()> {
    match datum {
        Datum::Atom(name)
            if number(name).is_some()
                || character(name).is_some()
                || matches!(name.as_str(), "#t" | "#f" | "_") =>
        {
            Ok(())
        }
        Datum::Atom(name) => validate_symbol(name),
        Datum::Text(_) => Ok(()),
        Datum::List(items) => items.iter().try_for_each(validate_pattern),
    }
}
pub(super) fn validate_symbol(name: &str) -> Result<()> {
    let numeric_initial = name.chars().next().is_some_and(|c| c.is_ascii_digit())
        || name
            .strip_prefix(['+', '-', '.'])
            .is_some_and(|tail| tail.chars().next().is_some_and(|c| c.is_ascii_digit()));
    let numeric_initial = numeric_initial
        || (name.chars().any(|c| c.is_ascii_digit()) && name.parse::<f64>().is_ok())
        || name
            .strip_prefix(['+', '-'])
            .and_then(|tail| tail.strip_prefix('.'))
            .is_some_and(|tail| tail.chars().next().is_some_and(|c| c.is_ascii_digit()));
    let special_number = ["+i", "-i", "+inf.0", "-inf.0", "+nan.0", "-nan.0"]
        .iter()
        .any(|candidate| name.eq_ignore_ascii_case(candidate));
    let unsupported_prefix = name.starts_with('#')
        && !name.starts_with("##")
        && !name.starts_with("#:")
        && !name.starts_with("#%module-macro-");
    if name == "." || name.ends_with(':') || numeric_initial || unsupported_prefix || special_number
    {
        return Err(fail("unsupported Scheme literal or identifier syntax"));
    }
    Ok(())
}

fn expansion_weight(
    datum: &Datum,
    captures: &BTreeMap<String, Datum>,
    depth: usize,
) -> Result<usize> {
    if depth > 128 {
        return Err(fail("macro expansion nesting bound"));
    }
    let weight = match datum {
        Datum::Atom(name) => match captures.get(name) {
            Some(value) => expansion_weight(value, &BTreeMap::new(), depth + 1)?,
            None => 64 + name.len(),
        },
        Datum::Text(value) => 64 + value.len(),
        Datum::List(items) => {
            let mut total = 64usize;
            for item in items {
                total = total
                    .checked_add(expansion_weight(item, captures, depth + 1)?)
                    .ok_or_else(|| fail("macro expansion allocation bound"))?;
                if total > 1_048_576 {
                    return Err(fail("macro expansion allocation bound"));
                }
            }
            total
        }
    };
    if weight > 1_048_576 {
        return Err(fail("macro expansion allocation bound"));
    }
    Ok(weight)
}

fn inexact(text: &str) -> Option<f64> {
    match text {
        "+inf.0" => Some(f64::INFINITY),
        "-inf.0" => Some(f64::NEG_INFINITY),
        "+nan.0" | "-nan.0" => Some(f64::NAN),
        _ if text.contains(['.', 'e', 'E']) => text.parse::<f64>().ok(),
        _ => None,
    }
}
