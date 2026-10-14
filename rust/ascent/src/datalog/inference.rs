//! Native union-find solves column-kind constraints; it does not evaluate relations.
use crate::{Data, Result, invalid_data as invalid};
use std::collections::BTreeMap;
#[derive(Clone, Copy, PartialEq, Eq)]
enum Kind {
    Text,
    Integer,
    Boolean,
}
impl Kind {
    fn scalar(value: &Data) -> Result<Self> {
        match value {
            Data::Text(_) => Ok(Self::Text),
            Data::Integer(_) => Ok(Self::Integer),
            Data::Bool(_) => Ok(Self::Boolean),
            _ => Err(invalid("unsupported typed Datalog scalar")),
        }
    }
    fn name(self) -> &'static str {
        match self {
            Self::Text => "string",
            Self::Integer => "integer",
            Self::Boolean => "boolean",
        }
    }
}
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Key {
    Column(String, usize),
    Variable(usize, String),
    Operand(usize, usize, usize),
}
#[derive(Default)]
struct Constraints {
    slots: BTreeMap<Key, usize>,
    parents: Vec<usize>,
    ranks: Vec<u8>,
    kinds: Vec<Option<Kind>>,
    widths: BTreeMap<String, usize>,
}
pub(super) fn infer(
    facts: &Data,
    rules: &[Data],
    queries: &BTreeMap<String, Data>,
) -> Result<BTreeMap<String, Vec<String>>> {
    let mut constraints = Constraints::default();
    constraints.facts(facts)?;
    for (scope, rule) in rules.iter().enumerate() {
        constraints.rule(rule, scope)?;
    }
    for query in queries.values() {
        constraints.declare(
            query.field("relation")?.text()?,
            query.field("terms")?.list()?.len(),
        )?;
    }
    Ok(constraints.finish())
}
impl Constraints {
    fn slot(&mut self, key: Key) -> usize {
        if let Some(i) = self.slots.get(&key) {
            return *i;
        }
        let n = self.parents.len();
        self.slots.insert(key, n);
        self.parents.push(n);
        self.ranks.push(0);
        self.kinds.push(None);
        n
    }
    fn root(&mut self, mut i: usize) -> usize {
        while self.parents[i] != i {
            self.parents[i] = self.parents[self.parents[i]];
            i = self.parents[i];
        }
        i
    }
    fn constrain(&mut self, key: Key, kind: Kind) -> Result<()> {
        let i = self.slot(key);
        let i = self.root(i);
        if self.kinds[i].is_some_and(|k| k != kind) {
            return Err(invalid("incompatible Datalog column types"));
        }
        self.kinds[i] = Some(kind);
        Ok(())
    }
    fn unify(&mut self, a: Key, b: Key) -> Result<()> {
        let a = self.slot(a);
        let b = self.slot(b);
        let mut a = self.root(a);
        let mut b = self.root(b);
        if a == b {
            return Ok(());
        }
        if self.kinds[a].is_some() && self.kinds[b].is_some() && self.kinds[a] != self.kinds[b] {
            return Err(invalid("incompatible Datalog column types"));
        }
        if self.ranks[a] < self.ranks[b] {
            std::mem::swap(&mut a, &mut b);
        }
        self.parents[b] = a;
        self.kinds[a] = self.kinds[a].or(self.kinds[b]);
        if self.ranks[a] == self.ranks[b] {
            self.ranks[a] += 1;
        }
        Ok(())
    }
    fn declare(&mut self, name: &str, width: usize) -> Result<()> {
        if self
            .widths
            .insert(name.into(), width)
            .is_some_and(|old| old != width)
        {
            return Err(invalid("inconsistent relation arity"));
        }
        for c in 0..width {
            self.slot(Key::Column(name.into(), c));
        }
        Ok(())
    }
    fn operand(&mut self, term: &Data, scope: usize, key: Key) -> Result<()> {
        if let Some(name) = term.get("var") {
            self.unify(key, Key::Variable(scope, name.text()?.into()))
        } else {
            self.constrain(key, Kind::scalar(term.field("const")?)?)
        }
    }
    fn relation(&mut self, atom: &Data, scope: usize) -> Result<()> {
        let name = atom.field("relation")?.text()?;
        let terms = atom.field("terms")?.list()?;
        self.declare(name, terms.len())?;
        for (c, term) in terms.iter().enumerate() {
            self.operand(term, scope, Key::Column(name.into(), c))?;
        }
        Ok(())
    }
    fn facts(&mut self, facts: &Data) -> Result<()> {
        for (name, rows) in facts.map()? {
            self.source_rows(name, rows)?;
        }
        Ok(())
    }
    fn source_rows(&mut self, name: &str, rows: &Data) -> Result<()> {
        for row in rows.list()? {
            let row = row.list()?;
            self.declare(name, row.len())?;
            for (c, value) in row.iter().enumerate() {
                self.constrain(Key::Column(name.into(), c), Kind::scalar(value)?)?;
            }
        }
        Ok(())
    }
    fn rule(&mut self, rule: &Data, scope: usize) -> Result<()> {
        for head in rule.field("head")?.list()? {
            self.relation(head, scope)?;
        }
        for (number, clause) in rule.field("body")?.list()?.iter().enumerate() {
            self.clause(clause, scope, number)?;
        }
        Ok(())
    }
    fn clause(&mut self, clause: &Data, scope: usize, number: usize) -> Result<()> {
        if clause.get("relation").is_some() {
            self.relation(clause, scope)?;
        }
        let Some(mode) = clause.get("mode") else {
            return Ok(());
        };
        let mode = mode.text()?;
        let operator = clause.field("operator")?.text()?;
        let slots = clause
            .field("terms")?
            .list()?
            .iter()
            .enumerate()
            .map(|(i, term)| {
                let key = Key::Operand(scope, number, i);
                self.operand(term, scope, key.clone())?;
                Ok(key)
            })
            .collect::<Result<Vec<_>>>()?;
        if mode == "where" || mode == "compute" && operator == "+" {
            for key in &slots {
                self.constrain(key.clone(), Kind::Integer)?;
            }
        }
        if mode != "compute" && mode != "reduce" {
            return Ok(());
        }
        let output = Key::Variable(scope, clause.field("output")?.text()?.into());
        if mode == "compute" && operator == "identity" && slots.len() == 1 {
            return self.unify(output, slots[0].clone());
        }
        self.constrain(output, Kind::Integer)?;
        if mode == "reduce" && operator != "count" {
            for variable in clause.field("inputs")?.list()? {
                self.constrain(Key::Variable(scope, variable.text()?.into()), Kind::Integer)?;
            }
        }
        Ok(())
    }
    fn finish(mut self) -> BTreeMap<String, Vec<String>> {
        let widths = self.widths.clone();
        widths
            .into_iter()
            .map(|(name, width)| {
                let kinds = (0..width)
                    .map(|c| {
                        let i = self.slot(Key::Column(name.clone(), c));
                        let root = self.root(i);
                        self.kinds[root].unwrap_or(Kind::Text).name().into()
                    })
                    .collect();
                (name, kinds)
            })
            .collect()
    }
}

pub(super) fn validate_schema(
    facts: &Data,
    rules: &[Data],
    schema: &BTreeMap<String, Vec<String>>,
) -> Result<()> {
    if schema.values().flatten().any(|kind| kind == "value") {
        return Ok(());
    }
    let mut constraints = Constraints::default();
    for (name, kinds) in schema {
        constraints.seed(name, kinds)?;
    }
    constraints.facts(facts)?;
    for (scope, rule) in rules.iter().enumerate() {
        constraints.rule(rule, scope)?;
    }
    Ok(())
}
impl Constraints {
    fn seed(&mut self, name: &str, kinds: &[String]) -> Result<()> {
        self.declare(name, kinds.len())?;
        for (c, kind) in kinds.iter().enumerate() {
            let kind = match kind.as_str() {
                "integer" => Kind::Integer,
                "boolean" => Kind::Boolean,
                "symbol" | "string" | "text" => Kind::Text,
                _ => return Err(invalid("unsupported declared Datalog kind")),
            };
            self.constrain(Key::Column(name.into(), c), kind)?;
        }
        Ok(())
    }
}
