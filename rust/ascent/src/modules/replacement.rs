//! Freeze replacement cells and retain lexical roots before transactional publication.
use super::{
    ObjectInput,
    objects::{Id, Object, fail},
    owner::State,
};
use crate::{Result, Row, SourceSession, Value};
use std::collections::BTreeMap;
type Replacements = BTreeMap<String, Vec<Row>>;
pub(super) fn prepare(
    state: &mut State,
    sources: BTreeMap<String, Vec<Vec<ObjectInput>>>,
    snapshot: u64,
) -> Result<(Replacements, BTreeMap<String, Id>)> {
    let mut conversion = Conversion {
        state,
        snapshot,
        cache: BTreeMap::new(),
    };
    let mut updates = BTreeMap::new();
    let mut roots = BTreeMap::new();
    for (name, rows) in sources {
        let mut retained = Vec::new();
        let frozen = rows
            .iter()
            .map(|row| conversion.row(row, &mut retained))
            .collect::<Result<_>>()?;
        let root = conversion
            .state
            .arena
            .add(Object::Record("source-roots".into(), retained))?;
        roots.insert(name.clone(), root);
        updates.insert(name, frozen);
    }
    Ok((updates, roots))
}
struct Conversion<'a> {
    state: &'a mut State,
    snapshot: u64,
    cache: BTreeMap<Id, Value>,
}
impl Conversion<'_> {
    fn row(&mut self, row: &[ObjectInput], retained: &mut Vec<Id>) -> Result<Row> {
        row.iter()
            .map(|cell| self.cell(cell, retained))
            .collect::<Result<Vec<_>>>()
            .map(Into::into)
    }
    fn cell(&mut self, cell: &ObjectInput, retained: &mut Vec<Id>) -> Result<Value> {
        let id = self.state.input(cell, 0)?;
        retained.push(id);
        match cell {
            ObjectInput::ResultValue(value) => value.value(),
            ObjectInput::Value(value) => Ok(value.clone()),
            _ => self.freeze(id),
        }
    }
    fn freeze(&mut self, id: Id) -> Result<Value> {
        if let Some(value) = self.cache.get(&id) {
            return Ok(value.clone());
        }
        let value = self
            .state
            .arena
            .freeze(self.state.identity, self.snapshot, id)?;
        self.cache.insert(id, value.clone());
        Ok(value)
    }
}
pub(super) fn validate(input: &ObjectInput, session: &SourceSession, depth: usize) -> Result<()> {
    if depth > 128 {
        return Err(fail("argument nesting bound"));
    }
    match input {
        ObjectInput::ResultValue(value) => session.validate_value(value),
        ObjectInput::List(items) | ObjectInput::Vector(items) => {
            for item in items {
                validate(item, session, depth + 1)?;
            }
            Ok(())
        }
        ObjectInput::Pair(a, b) => {
            validate(a, session, depth + 1)?;
            validate(b, session, depth + 1)
        }
        _ => Ok(()),
    }
}
