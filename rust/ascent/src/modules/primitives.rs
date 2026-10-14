//! Primitive object operations; all results stay in the owner-local arena.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, Procedure, fail},
};
use crate::Result;
use num_rational::BigRational;
use num_traits::{ToPrimitive, Zero};
pub(super) const BUILTINS: &[&str] = &[
    "+",
    "-",
    "*",
    "/",
    "=",
    "<",
    ">",
    "<=",
    ">=",
    "min",
    "max",
    "not",
    "identity",
    "values",
    ".ref",
    "apply",
    "map",
    "for-each",
    "list",
    "append",
    "member",
    "assq",
    "assoc",
    "andmap",
    "ormap",
    "cons",
    "car",
    "cdr",
    "length",
    "null?",
    "pair?",
    "vector",
    "make-vector",
    "vector-ref",
    "vector-set!",
    "vector-length",
    "list->vector",
    "vector->list",
    "u8vector",
    "make-hash-table",
    "make-hash-table-eq",
    "hash-put!",
    "hash-ref",
    "hash-get",
    "string->symbol",
    "string->uninterned-symbol",
    "symbol->string",
    "string-append",
    "number->string",
    "void",
    "gensym",
    "equal?",
    "eq?",
    "gerbil-ascent-guard",
    "gerbil-ascent-binding",
    "gerbil-ascent-aggregate",
    "gerbil-ascent-negation",
    "gerbil-ascent-variable",
    "gerbil-ascent-atom",
    "gerbil-ascent-rule",
    "gerbil-ascent-relation",
    "gerbil-ascent-lattice",
    "gerbil-ascent-program",
    "ascent-evidence-module",
    "make-declared-evidence",
    "recorded-evidence-explanation",
];
impl Evaluation<'_> {
    fn apply_arguments(&mut self, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        if args.len() < 2 {
            return Err(fail("apply requires a procedure and arguments"));
        }
        let mut tail = args[1..args.len() - 1].to_vec();
        tail.extend(self.arena.items(args[args.len() - 1])?);
        self.apply(args[0], &tail, depth + 1)
    }
    pub(super) fn primitive(&mut self, name: &str, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        if super::reachability::EXPORTS.contains(&name) {
            return self.reachability(name, args, depth);
        }
        if super::numeric_values::EXPORTS.contains(&name) {
            return self.numeric_test(name, args);
        }
        if super::aggregates::EXPORTS.contains(&name) {
            return self.aggregate_primitive(name, args, depth);
        }
        if super::views::EXPORTS.contains(&name) {
            return self.view(name, args, depth);
        }
        if super::operator_change::EXPORTS.contains(&name) {
            return self.operator_change(name, args, depth);
        }
        if super::typed::EXPORTS.contains(&name) {
            return self.typed(name, args, depth);
        }
        if super::operator_values::EXPORTS.contains(&name) {
            return self.operator(name, args, depth);
        }
        if super::relational::EXPORTS.contains(&name) {
            return self.relational(name, args, depth);
        }
        if name == ".ref" {
            return self.reference_primitive(args);
        }
        if name == "gensym" {
            return self.fresh_symbol(args);
        }
        if name == "values" {
            return Ok(args.to_vec());
        }
        if name == "apply" {
            return self.apply_arguments(args, depth);
        }
        if matches!(
            name,
            "append" | "member" | "assq" | "assoc" | "andmap" | "ormap"
        ) {
            return self.list_algorithms(name, args, depth);
        }
        if name == "map" || name == "for-each" {
            return self.mapped_lists(name, args, depth);
        }
        match name {
            "+" | "-" | "*" | "/" | "min" | "max" | "=" | "<" | ">" | "<=" | ">=" => {
                self.numeric_primitive(name, args)
            }
            "identity" | "not" => self.identity_primitive(name, args),
            "null?" | "pair?" | "list" | "cons" | "car" | "cdr" | "length" => {
                self.pairs_primitive(name, args)
            }
            "vector" | "make-vector" | "vector-ref" | "vector-set!" | "vector-length"
            | "list->vector" | "vector->list" | "u8vector" => self.vectors_primitive(name, args),
            "make-hash-table" | "make-hash-table-eq" | "hash-put!" | "hash-ref" | "hash-get" => {
                self.tables_primitive(name, args)
            }
            "string->symbol"
            | "string->uninterned-symbol"
            | "symbol->string"
            | "number->string"
            | "string-append" => self.strings_primitive(name, args),
            "eq?" | "equal?" | "void" => self.equality_primitive(name, args),
            "make-declared-evidence" => self.declared_primitive(args),
            "recorded-evidence-explanation" => self.recorded_primitive(args),
            "gerbil-ascent-guard"
            | "gerbil-ascent-binding"
            | "gerbil-ascent-aggregate"
            | "gerbil-ascent-negation"
            | "gerbil-ascent-variable"
            | "gerbil-ascent-atom"
            | "gerbil-ascent-rule"
            | "gerbil-ascent-lattice"
            | "gerbil-ascent-relation"
            | "gerbil-ascent-program"
            | "ascent-evidence-module" => self.records_primitive(name, args),
            _ => Err(fail("unsupported Scheme primitive")),
        }
    }
    fn identity_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let value = match name {
            "identity" => {
                arity(args, 1)?;
                return Ok(vec![args[0]]);
            }
            "not" => {
                arity(args, 1)?;
                Object::Boolean(!self.arena.truth(args[0])?)
            }
            _ => return Err(fail("invalid primitive dispatch")),
        };
        self.arena.add(value).map(|value| vec![value])
    }
    fn pairs_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let value = match name {
            "null?" | "pair?" => {
                arity(args, 1)?;
                Object::Boolean(match self.arena.get(args[0])? {
                    Object::Null => name == "null?",
                    Object::Pair(..) => name == "pair?",
                    _ => false,
                })
            }
            "list" => return self.arena.list(args).map(|v| vec![v]),
            "cons" => {
                arity(args, 2)?;
                Object::Pair(args[0], args[1])
            }
            "car" | "cdr" => {
                arity(args, 1)?;
                let Object::Pair(a, b) = self.arena.get(args[0])? else {
                    return Err(fail("pair required"));
                };
                return Ok(vec![if name == "car" { *a } else { *b }]);
            }
            "length" => {
                arity(args, 1)?;
                Object::Number(BigRational::from_integer(
                    self.arena.items(args[0])?.len().into(),
                ))
            }
            _ => return Err(fail("invalid primitive dispatch")),
        };
        self.arena.add(value).map(|value| vec![value])
    }
    fn vectors_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let value = match name {
            "vector" => Object::Vector(args.to_vec()),
            "make-vector" => {
                if !(1..=2).contains(&args.len()) {
                    return Err(fail("make-vector arity"));
                }
                let len = self.index(args[0])?;
                if len > 65_536 {
                    return Err(fail("vector length bound"));
                }
                let fill = if args.len() == 2 {
                    args[1]
                } else {
                    self.arena.add(Object::Number(BigRational::zero()))?
                };
                Object::Vector(vec![fill; len])
            }
            "vector-ref" => {
                arity(args, 2)?;
                let index = self.index(args[1])?;
                let Object::Vector(items) = self.arena.get(args[0])? else {
                    return Err(fail("vector required"));
                };
                return items
                    .get(index)
                    .copied()
                    .map(|v| vec![v])
                    .ok_or_else(|| fail("vector index out of range"));
            }
            "vector-set!" => {
                arity(args, 3)?;
                let index = self.index(args[1])?;
                let Some(Object::Vector(items)) = self.arena.objects.get_mut(&args[0]) else {
                    return Err(fail("vector required"));
                };
                *items
                    .get_mut(index)
                    .ok_or_else(|| fail("vector index out of range"))? = args[2];
                Object::Void
            }
            "vector-length" => {
                arity(args, 1)?;
                let Object::Vector(items) = self.arena.get(args[0])? else {
                    return Err(fail("vector required"));
                };
                Object::Number(BigRational::from_integer(items.len().into()))
            }
            "list->vector" => {
                arity(args, 1)?;
                Object::Vector(self.arena.items(args[0])?)
            }
            "vector->list" => {
                arity(args, 1)?;
                let Object::Vector(items) = self.arena.get(args[0])?.clone() else {
                    return Err(fail("vector required"));
                };
                return self.arena.list(&items).map(|v| vec![v]);
            }
            "u8vector" => Object::Bytes(
                args.iter()
                    .map(|v| {
                        self.arena
                            .integer(*v)?
                            .to_u8()
                            .ok_or_else(|| fail("u8vector byte required"))
                    })
                    .collect::<Result<_>>()?,
            ),
            _ => return Err(fail("invalid primitive dispatch")),
        };
        self.arena.add(value).map(|value| vec![value])
    }
    fn tables_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let value = match name {
            "make-hash-table" | "make-hash-table-eq" => {
                arity(args, 0)?;
                Object::Table {
                    entries: Vec::new(),
                    identity: name == "make-hash-table-eq",
                }
            }
            "hash-put!" => {
                arity(args, 3)?;
                let Object::Table { entries, identity } = self.arena.get(args[0])? else {
                    return Err(fail("hash table required"));
                };
                let position = self.table_position(entries, *identity, args[1])?;
                let Some(Object::Table { entries, .. }) = self.arena.objects.get_mut(&args[0])
                else {
                    unreachable!()
                };
                if let Some(i) = position {
                    entries[i].1 = args[2];
                } else {
                    entries.push((args[1], args[2]));
                }
                Object::Void
            }
            "hash-ref" | "hash-get" => {
                if !(2..=3).contains(&args.len()) {
                    return Err(fail("hash-ref arity"));
                }
                let Object::Table { entries, identity } = self.arena.get(args[0])? else {
                    return Err(fail("hash table required"));
                };
                if let Some(position) = self.table_position(entries, *identity, args[1])? {
                    return Ok(vec![entries[position].1]);
                }
                if args.len() == 3 {
                    return Ok(vec![args[2]]);
                }
                if name == "hash-ref" {
                    return Err(fail("missing hash key"));
                }
                Object::Boolean(false)
            }
            _ => return Err(fail("invalid primitive dispatch")),
        };
        self.arena.add(value).map(|value| vec![value])
    }
    fn strings_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let value = match name {
            "string->symbol" | "string->uninterned-symbol" => {
                arity(args, 1)?;
                let Object::Text(text) = self.arena.get(args[0])?.clone() else {
                    return Err(fail("string required"));
                };
                return self
                    .arena
                    .symbol(&text, name == "string->symbol")
                    .map(|v| vec![v]);
            }
            "symbol->string" => {
                arity(args, 1)?;
                let Object::Symbol(text, _) = self.arena.get(args[0])? else {
                    return Err(fail("symbol required"));
                };
                Object::Text(text.clone())
            }
            "number->string" => {
                arity(args, 1)?;
                Object::Text(match self.arena.get(args[0])? {
                    Object::Number(n) => n.to_string(),
                    Object::Inexact(n) => crate::numbers::format_inexact(*n),
                    _ => return Err(fail("number required")),
                })
            }
            "string-append" => {
                let mut text = String::new();
                for id in args {
                    let Object::Text(s) = self.arena.get(*id)? else {
                        return Err(fail("string required"));
                    };
                    text.push_str(s);
                }
                Object::Text(text)
            }
            _ => return Err(fail("invalid primitive dispatch")),
        };
        self.arena.add(value).map(|value| vec![value])
    }
    fn fresh_symbol(&mut self, args: &[Id]) -> Result<Vec<Id>> {
        if args.len() > 1 {
            return Err(fail("gensym arity"));
        }
        let prefix = if let Some(arg) = args.first() {
            match self.arena.get(*arg)? {
                Object::Text(s) | Object::Symbol(s, _) => s.clone(),
                _ => return Err(fail("gensym prefix")),
            }
        } else {
            "G".into()
        };
        let nonce = self.arena.add(Object::Void)?;
        let symbol = self.arena.symbol(&format!("{prefix}{nonce}"), false)?;
        Ok(vec![symbol])
    }
    fn equality_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        let value = match name {
            "eq?" => {
                arity(args, 2)?;
                Object::Boolean(
                    args[0] == args[1]
                        || match (self.arena.get(args[0])?, self.arena.get(args[1])?) {
                            (Object::Number(a), Object::Number(b)) => a == b,
                            (Object::Inexact(a), Object::Inexact(b)) => {
                                crate::numbers::format_inexact(*a)
                                    == crate::numbers::format_inexact(*b)
                            }
                            (Object::Boolean(a), Object::Boolean(b)) => a == b,
                            (Object::Null, Object::Null) => true,
                            (Object::Character(a), Object::Character(b)) => a == b,
                            _ => false,
                        },
                )
            }
            "equal?" => {
                arity(args, 2)?;
                Object::Boolean(self.equal(args[0], args[1], 0)?)
            }
            "void" => {
                arity(args, 0)?;
                Object::Void
            }
            _ => return Err(fail("invalid primitive dispatch")),
        };
        self.arena.add(value).map(|value| vec![value])
    }
    fn records_primitive(&mut self, name: &str, args: &[Id]) -> Result<Vec<Id>> {
        if matches!(
            name,
            "gerbil-ascent-relation"
                | "gerbil-ascent-lattice"
                | "gerbil-ascent-atom"
                | "gerbil-ascent-variable"
        ) && let Some(id) = args.first()
        {
            self.arena.register_name(*id)?;
        }

        if name == "gerbil-ascent-guard" || name == "gerbil-ascent-binding" {
            let offset = usize::from(name == "gerbil-ascent-binding");
            if args.len() != offset + 2 && args.len() != offset + 3 {
                return Err(fail("scalar constructor arity"));
            }
            if offset == 1 {
                self.arena.register_name(args[0])?;
            }
            for id in self.arena.items(args[offset])? {
                self.arena.register_name(id)?;
            }
            let kind = if offset == 1 { "binding" } else { "guard" };
            return self
                .arena
                .add(Object::Record(kind.into(), args.to_vec()))
                .map(|id| vec![id]);
        }
        if name == "gerbil-ascent-aggregate" {
            if !(5..=7).contains(&args.len()) {
                return Err(fail("aggregate constructor arity"));
            }
            for id in [args[0], args[1]]
                .into_iter()
                .chain(self.arena.items(args[3])?)
            {
                self.arena.register_name(id)?;
            }
            return self
                .arena
                .add(Object::Record("aggregate".into(), args.to_vec()))
                .map(|id| vec![id]);
        }
        if name == "gerbil-ascent-negation" {
            arity(args, 2)?;
            self.arena.register_name(args[0])?;
            return self
                .arena
                .add(Object::Record("negation".into(), args.to_vec()))
                .map(|id| vec![id]);
        }
        let (kind, count) = match name {
            "gerbil-ascent-variable" => ("variable", 1),
            "gerbil-ascent-atom" => ("atom", 2),
            "gerbil-ascent-rule" => ("rule", 2),
            "gerbil-ascent-relation" => ("relation", 3),
            "gerbil-ascent-lattice" => ("lattice", 4),
            "gerbil-ascent-program" => ("program", 6),
            "ascent-evidence-module" => {
                if !(2..=3).contains(&args.len()) {
                    return Err(fail("evidence module arity"));
                }
                ("evidence", args.len())
            }
            _ => return Err(fail("invalid record constructor")),
        };
        arity(args, count)?;
        self.arena
            .add(Object::Record(kind.into(), args.to_vec()))
            .map(|value| vec![value])
    }
    fn index(&self, id: Id) -> Result<usize> {
        self.arena
            .integer(id)?
            .to_usize()
            .ok_or_else(|| fail("nonnegative index required"))
    }
    fn table_position(
        &self,
        entries: &[(Id, Id)],
        identity: bool,
        key: Id,
    ) -> Result<Option<usize>> {
        for (index, (candidate, _)) in entries.iter().enumerate() {
            if (identity && *candidate == key) || (!identity && self.equal(*candidate, key, 0)?) {
                return Ok(Some(index));
            }
        }
        Ok(None)
    }
    pub(super) fn equal(&self, a: Id, b: Id, _depth: usize) -> Result<bool> {
        let mut pending = vec![(a, b)];
        let mut seen = std::collections::BTreeSet::new();
        while let Some((a, b)) = pending.pop() {
            if a == b || !seen.insert((a, b)) {
                continue;
            }
            if seen.len() > 262_144 {
                return Err(fail("equal? traversal work bound"));
            }
            if !self.equal_step(a, b, &mut pending)? {
                return Ok(false);
            }
        }
        Ok(true)
    }
    fn equal_step(&self, a: Id, b: Id, pending: &mut Vec<(Id, Id)>) -> Result<bool> {
        Ok(match (self.arena.get(a)?, self.arena.get(b)?) {
            (Object::Number(a), Object::Number(b)) => a == b,
            (Object::Inexact(a), Object::Inexact(b)) => {
                crate::numbers::format_inexact(*a) == crate::numbers::format_inexact(*b)
            }
            (Object::Boolean(a), Object::Boolean(b)) => a == b,
            (Object::Text(a), Object::Text(b)) => a == b,
            (Object::Character(a), Object::Character(b)) => a == b,
            (Object::Null, Object::Null) | (Object::Void, Object::Void) => true,
            (Object::Pair(a, b), Object::Pair(c, d)) => {
                pending.extend([(*a, *c), (*b, *d)]);
                true
            }
            (Object::Vector(a), Object::Vector(b)) => {
                if a.len() != b.len() {
                    return Ok(false);
                }
                pending.extend(a.iter().copied().zip(b.iter().copied()));
                true
            }
            (Object::Bytes(a), Object::Bytes(b)) => a == b,
            _ => false,
        })
    }
}
fn arity(args: &[Id], expected: usize) -> Result<()> {
    if args.len() == expected {
        Ok(())
    } else {
        Err(fail("Scheme primitive arity mismatch"))
    }
}
pub(super) fn install(arena: &mut super::objects::Arena, env: super::objects::EnvId) -> Result<()> {
    for name in BUILTINS
        .iter()
        .chain(super::typed::EXPORTS)
        .chain(super::operator_values::EXPORTS)
        .chain(super::relational::EXPORTS)
        .chain(super::operator_change::EXPORTS)
        .chain(super::views::EXPORTS)
        .chain(super::reachability::EXPORTS)
        .chain(super::aggregates::EXPORTS)
        .chain(super::numeric_values::EXPORTS)
    {
        let value = arena.add(Object::Procedure(Procedure::Builtin(name)))?;
        arena.bind(env, (*name).into(), value);
    }
    Ok(())
}
