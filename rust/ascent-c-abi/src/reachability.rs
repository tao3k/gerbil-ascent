//! Fixed transport over the existing compressed closure and immutable cut algorithms.
use crate::operations::fields;
use gerbil_ascent::{
    Cancellation, Catalog, Data, Error, Reachability, ReachabilitySnapshot, Result, Value,
};
use std::collections::BTreeMap;

pub(super) struct Owner {
    state: Option<Reachability>,
    cuts: BTreeMap<u64, ReachabilitySnapshot>,
    next: u64,
    pub trace: crate::diagnostics::Trace,
}
impl Owner {
    pub fn open(input: &Data) -> Result<Self> {
        fields(input, &[])?;
        Ok(Self {
            state: Some(Reachability::new()),
            cuts: BTreeMap::new(),
            next: 0,
            trace: crate::diagnostics::Trace::new(false),
        })
    }
    pub fn invoke(&mut self, input: &Data) -> Result<Data> {
        let method = admitted_method(input)?;
        match method {
            "insert" => self.insert(input),
            "freeze" => self.freeze(),
            "close-state" => {
                self.state = None;
                Ok(Data::Null)
            }
            "release-cut" => {
                self.cuts.remove(&cut_id(input)?);
                Ok(Data::Null)
            }
            _ => self.query(method, input),
        }
    }
    fn insert(&mut self, input: &Data) -> Result<Data> {
        let edge = scalar_row(input.field("edge")?)?;
        Ok(self
            .state
            .as_mut()
            .ok_or(Error::Closed)?
            .insert(
                &edge,
                input.field("budget")?.index()?,
                &Cancellation::default(),
            )?
            .into())
    }
    fn freeze(&mut self) -> Result<Data> {
        let cut = self.state.as_ref().ok_or(Error::Closed)?.freeze();
        self.next = self.next.checked_add(1).ok_or(Error::StateLimit)?;
        self.cuts.insert(self.next, cut);
        Ok(self.next.into())
    }
    fn query(&self, method: &str, input: &Data) -> Result<Data> {
        match method {
            "resources" => Ok(resources(
                self.state.as_ref().ok_or(Error::Closed)?.resources(),
            )),
            "validate" => Ok(self
                .state
                .as_ref()
                .ok_or(Error::Closed)?
                .validate(&Cancellation::default())?
                .into()),
            "cut-resources" => Ok(resources(self.cut(input)?.resources())),
            "contains" => Ok(self
                .cut(input)?
                .contains(&scalar_row(input.field("row")?)?)
                .into()),
            "difference" => self.cut_difference(input),
            "rows" => self.rows(input),
            _ => Err(invalid("unknown fixed reachability operation")),
        }
    }
    fn cut_difference(&self, input: &Data) -> Result<Data> {
        let current = self.cut(input)?;
        let other_id =
            u64::try_from(input.field("other")?.index()?).map_err(|_| invalid("cut identity"))?;
        let old = self.cuts.get(&other_id).ok_or(Error::Closed)?;
        difference(current, old, input.field("budget")?.index()?)
    }
    fn rows(&self, input: &Data) -> Result<Data> {
        let columns = input.field("columns")?.list()?;
        let key = scalar_row(input.field("key")?)?;
        if columns.len() != key.len() {
            return Err(invalid("selector arity"));
        }
        let selectors = columns
            .iter()
            .zip(key)
            .map(|(column, value)| Ok((column.index()?, value)))
            .collect::<Result<Vec<_>>>()?;
        let rows = self.cut(input)?.rows(
            &selectors,
            input.field("limit")?.index()?,
            &Cancellation::default(),
        )?;
        Catalog::observe_rows(&rows)
    }
    fn cut(&self, input: &Data) -> Result<&ReachabilitySnapshot> {
        self.cuts.get(&cut_id(input)?).ok_or(Error::Closed)
    }
}
fn admitted_method(input: &Data) -> Result<&str> {
    let method = input.field("method")?.text()?;
    let required: &[&str] = match method {
        "resources" | "validate" | "freeze" | "close-state" => &["method"],
        "insert" => &["method", "edge", "budget"],
        "cut-resources" | "release-cut" => &["method", "cut"],
        "contains" => &["method", "cut", "row"],
        "difference" => &["method", "cut", "other", "budget"],
        "rows" => &["method", "cut", "columns", "key", "limit"],
        _ => return Err(invalid("unknown fixed reachability operation")),
    };
    fields(input, required)?;
    Ok(method)
}
fn cut_id(input: &Data) -> Result<u64> {
    u64::try_from(input.field("cut")?.index()?).map_err(|_| invalid("cut identity"))
}
fn resources(values: [usize; 4]) -> Data {
    Data::List(values.into_iter().map(Data::from).collect())
}
fn scalar_row(input: &Data) -> Result<Vec<Value>> {
    // Selector repetitions are not relation columns. Decode each typed value
    // through the existing catalog without imposing its relation-width bound.
    input
        .list()?
        .iter()
        .map(|cell| {
            let catalog = Catalog::read(&Data::object([
                (
                    "relations",
                    Data::List(vec![Data::object([
                        ("name", "input".into()),
                        ("source", true.into()),
                        (
                            "columns",
                            Data::List(vec![Data::object([("kind", "value".into())])]),
                        ),
                        ("rows", Data::List(vec![Data::List(vec![cell.clone()])])),
                    ])]),
                ),
                ("rules", Data::List(vec![])),
            ]))?;
            catalog
                .program
                .relations
                .into_iter()
                .next()
                .and_then(|relation| relation.rows.into_iter().next())
                .and_then(|row| row.first().cloned())
                .ok_or_else(|| invalid("input value"))
        })
        .collect()
}
fn invalid(message: &str) -> Error {
    Error::InvalidUpdate(message.into())
}

fn difference(
    current: &ReachabilitySnapshot,
    old: &ReachabilitySnapshot,
    budget: usize,
) -> Result<Data> {
    use gerbil_ascent::{Atom, Clause, Engine, Limits, Program, Relation, Rule, Term, Type};
    let cancel = Cancellation::default();
    let after = current.rows(&[], usize::MAX, &cancel)?;
    let before = old.rows(&[], usize::MAX, &cancel)?;
    let width = after
        .first()
        .or_else(|| before.first())
        .map_or(2, |row| row.len());
    if after.iter().chain(&before).any(|row| row.len() != width) {
        return Err(invalid("cut width mismatch"));
    }
    let mut program = Program::default();
    for (name, rows, source) in [
        ("current", after, true),
        ("previous", before, true),
        ("delta", vec![], false),
    ] {
        let mut relation = Relation::new(name, vec![Type::Any; width], source);
        relation.rows = rows;
        program.relations.push(relation);
    }
    let terms = (0..width)
        .map(|id| Term::Variable(u32::try_from(id).expect("bounded cut width")))
        .collect::<Vec<_>>();
    let absent = Atom::new("previous", terms.clone());
    program.rules.push(Rule {
        head: Atom::new("delta", terms.clone()),
        body: vec![
            Clause::positive(Atom::new("current", terms)),
            Clause::negative(absent),
        ],
    });
    // Compose existing set negation; no separate difference evaluator.
    let mut session = Engine::new(1)?.open(program)?;
    let snapshot = session.run(&Limits::default(), &cancel)?;
    let rows = &snapshot.relations["delta"];
    if rows.len() > budget {
        return Err(Error::FactLimit);
    }
    Catalog::observe_rows(rows)
}
