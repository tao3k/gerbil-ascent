//! Reify immutable execution observations for declared Scheme explanation callbacks.
use super::objects::{Arena, Id, Object, Procedure};
use crate::{GraphItem, ObjectGraph, ObjectNode, Result, Row, Value, source::Datum};
use std::{collections::BTreeMap, sync::Arc};
impl Arena {
    pub(super) fn program_object(&mut self, program: &crate::Program, parent: Id) -> Result<Id> {
        let relations = program
            .relations
            .iter()
            .map(|r| self.add(Object::Relation(r.clone(), parent)))
            .collect::<Result<Vec<_>>>()?;
        let rules = program
            .rules
            .iter()
            .map(|r| self.add(Object::Rule(r.clone(), parent)))
            .collect::<Result<Vec<_>>>()?;
        let relations = self.list(&relations)?;
        let rules = self.list(&rules)?;
        let mut fields = vec![relations, rules];
        for limit in [
            program.fact_limits.input,
            program.fact_limits.derived,
            program.fact_limits.output,
        ] {
            fields.push(self.add(match limit {
                Some(n) => Object::Number(num_rational::BigRational::from_integer(n.into())),
                None => Object::Inexact(f64::INFINITY),
            })?);
        }
        let sources = program
            .relations
            .iter()
            .filter(|r| r.source)
            .map(|r| self.relation_name(&r.name))
            .collect::<Result<Vec<_>>>()?;
        fields.push(self.list(&sources)?);
        self.add(Object::Record("program".into(), fields))
    }
    pub(super) fn explanation_scope(
        &mut self,
        generation: u64,
        sources: &[(String, Vec<Row>)],
    ) -> Result<Id> {
        let generation = self.add(Object::Number(num_rational::BigRational::from_integer(
            generation.into(),
        )))?;
        let mut values = Vec::new();
        for (name, rows) in sources {
            let name = self.relation_name(name)?;
            let rows = self.rows_object(rows)?;
            values.push(self.add(Object::Pair(name, rows))?);
        }
        let sources = self.list(&values)?;
        let premise = self.add(Object::Text(
            "immutable Rust admission snapshot; opaque identity remains owner scoped".into(),
        ))?;
        self.named_table(&[
            ("sourceGeneration", generation),
            ("sources", sources),
            ("premise", premise),
        ])
    }
    pub(super) fn default_explanation(&mut self, program: Id, scope: Id) -> Result<Id> {
        let program = if let Object::Compiled(data, _) = self.get(program)?.clone() {
            self.program_object(&data, program)?
        } else {
            program
        };
        let Object::Record(_, fields) = self.get(program)?.clone() else {
            unreachable!("admitted program")
        };
        let status = self.add(Object::Text("unsupported".into()))?;
        let gap = self.add(Object::Text(
            "native row derivation proof not supplied by this module".into(),
        ))?;
        self.named_table(&[
            ("status", status),
            ("gap", gap),
            ("dependencies", fields[1]),
            ("declarations", fields[0]),
            ("scope", scope),
        ])
    }
    fn named_table(&mut self, fields: &[(&str, Id)]) -> Result<Id> {
        let entries = fields
            .iter()
            .map(|(name, value)| Ok((self.add(Object::Text((*name).into()))?, *value)))
            .collect::<Result<_>>()?;
        self.add(Object::Table {
            entries,
            identity: false,
        })
    }
    pub(super) fn thaw(&mut self, value: &Value) -> Result<Id> {
        match value {
            Value::Integer(v) => self.add(Object::Number(num_rational::BigRational::from_integer(
                v.clone(),
            ))),
            Value::Boolean(v) => self.add(Object::Boolean(*v)),
            Value::Text(v) => self.add(Object::Text(v.to_string())),
            Value::Symbol(v) => self.symbol(v, true),
            Value::Object(v) => self.thaw_graph(v.graph()),
        }
    }
    fn thaw_graph(&mut self, graph: &ObjectGraph) -> Result<Id> {
        let mut ids = BTreeMap::new();
        let mut native = std::collections::BTreeSet::new();
        for (id, node) in &graph.nodes {
            let mapped = match node {
                ObjectNode::Opaque(_)
                | ObjectNode::Table(_)
                | ObjectNode::Symbol {
                    interned: false, ..
                } => {
                    self.get(*id)?;
                    native.insert(*id);
                    *id
                }
                ObjectNode::Symbol {
                    name,
                    interned: true,
                } => {
                    native.insert(*id);
                    self.symbol(name, true)?
                }
                _ => self.add(Object::Void)?,
            };
            ids.insert(*id, mapped);
        }
        for (id, node) in &graph.nodes {
            if native.contains(id) {
                continue;
            }
            let object = match node {
                ObjectNode::Text(v) => Object::Text(v.clone()),
                ObjectNode::Symbol { name, interned } => Object::Symbol(name.clone(), *interned),
                ObjectNode::Pair(a, b) => {
                    Object::Pair(self.thaw_item(a, &ids)?, self.thaw_item(b, &ids)?)
                }
                ObjectNode::Vector(items) => Object::Vector(
                    items
                        .iter()
                        .map(|v| self.thaw_item(v, &ids))
                        .collect::<Result<_>>()?,
                ),
                ObjectNode::Bytes(v) => Object::Bytes(v.clone()),
                ObjectNode::Table(entries) => Object::Table {
                    identity: false,
                    entries: entries
                        .iter()
                        .map(|(a, b)| Ok((self.thaw_item(a, &ids)?, self.thaw_item(b, &ids)?)))
                        .collect::<Result<_>>()?,
                },
                ObjectNode::Opaque(_) => {
                    return Err(super::objects::fail(
                        "opaque values require a live lexical object reference",
                    ));
                }
            };
            self.objects.insert(ids[id], object);
        }
        self.thaw_item(&graph.root, &ids)
    }
    fn thaw_item(&mut self, item: &GraphItem, ids: &BTreeMap<usize, Id>) -> Result<Id> {
        let object = match item {
            GraphItem::Reference(id) => return Ok(ids[id]),
            GraphItem::Void => Object::Void,
            GraphItem::Null => Object::Null,
            GraphItem::Boolean(v) => Object::Boolean(*v),
            GraphItem::Character(v) => Object::Character(*v),
            GraphItem::Number(v) => {
                if let Some(n) = super::evaluation::number(v) {
                    Object::Number(n)
                } else {
                    Object::Inexact(
                        crate::numbers::parse_inexact(v)
                            .ok_or_else(|| super::objects::fail("invalid observed number"))?,
                    )
                }
            }
        };
        self.add(object)
    }
    pub(super) fn rows_object(&mut self, rows: &[Row]) -> Result<Id> {
        let mut values = Vec::new();
        for row in rows {
            let cells = row
                .iter()
                .map(|v| self.thaw(v))
                .collect::<Result<Vec<_>>>()?;
            values.push(self.list(&cells)?);
        }
        self.list(&values)
    }
    pub(super) fn solution(&mut self, relations: &BTreeMap<String, Vec<Row>>) -> Result<Id> {
        let mut entries = Vec::new();
        for (name, rows) in relations {
            let key = self.relation_name(name)?;
            let rows = self.rows_object(rows)?;
            entries.push((key, rows));
        }
        let table = self.add(Object::Table {
            entries,
            identity: false,
        })?;
        let env = self.env(None)?;
        self.bind(env, "rows".into(), table);
        let lookup = self.add(Object::Procedure(Procedure::Builtin("hash-ref")))?;
        self.bind(env, "hash-ref".into(), lookup);
        let body = Datum::List(vec![
            Datum::Atom("hash-ref".into()),
            Datum::Atom("rows".into()),
            Datum::Atom("name".into()),
        ]);
        let procedure = self.add(Object::Procedure(Procedure::Closure {
            parameters: Arc::from(["name".into()]),
            rest: None,
            body: Arc::from([body]),
            env,
        }))?;
        self.add(Object::Record("result".into(), vec![procedure]))
    }
}
