//! Shared typed materialization; selected reads never substitute an export callback's order.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, fail},
    operator_values::index,
};
use crate::{Cancellation, Result, Row};
impl Evaluation<'_> {
    pub(super) fn is_view(&self, id: Id) -> Result<bool> {
        Ok(match self.arena.get(id)? {
            Object::ClosureView(_, _) | Object::RowsView(_, _) => true,
            Object::Record(kind, _) => matches!(
                kind.as_str(),
                "explicit-view" | "bound-view" | "export-view" | "lazy-view"
            ),
            _ => false,
        })
    }
    pub(super) fn view_measure(&mut self, id: Id, units: bool, depth: usize) -> Result<usize> {
        self.check(depth)?;
        match self.arena.get(id)?.clone() {
            Object::ClosureView(view, _) => Ok(if units {
                view.resources()[2]
            } else {
                view.len()
            }),
            Object::RowsView(rows, _) => Ok(rows.len()),
            Object::Record(kind, f) if kind == "explicit-view" && f.len() == 3 => {
                if units {
                    index(self.arena, f[1])
                } else {
                    Ok(self.arena.items(f[0])?.len())
                }
            }
            Object::Record(kind, f) if matches!(kind.as_str(), "export-view" | "bound-view") => {
                self.view_measure(f[0], units, depth + 1)
            }
            Object::Record(kind, f) if kind == "lazy-view" => index(self.arena, f[1]),
            _ => Err(fail("relation view required")),
        }
    }
    pub(super) fn view_selectors(
        &mut self,
        selection: &[Id],
    ) -> Result<Vec<(usize, crate::Value)>> {
        if selection.is_empty() {
            return Ok(Vec::new());
        }
        if selection.len() != 2 {
            return Err(fail("view selection arity"));
        }
        let columns = self.arena.items(selection[0])?;
        let keys = self.arena.items(selection[1])?;
        if columns.len() != keys.len() {
            return Err(fail("view selector arity"));
        }
        let snapshot = super::freeze::snapshot()?;
        columns
            .into_iter()
            .zip(keys)
            .map(|(c, k)| {
                Ok((
                    index(self.arena, c)?,
                    self.arena.freeze(self.arena.identity, snapshot, k)?,
                ))
            })
            .collect()
    }
    pub(super) fn view_tuples(
        &mut self,
        id: Id,
        selection: &[Id],
        depth: usize,
    ) -> Result<Vec<Row>> {
        self.check(depth)?;
        let object = self.arena.get(id)?.clone();
        let selectors = self.view_selectors(selection)?;
        match object {
            Object::ClosureView(view, _) => {
                view.rows(&selectors, 200_000, &Cancellation::default())
            }
            Object::RowsView(rows, _) => select(rows.iter().cloned(), &selectors),
            Object::Record(kind, f) if kind == "bound-view" => {
                self.view_tuples(f[0], selection, depth + 1)
            }
            Object::Record(kind, f) if kind == "export-view" => {
                if selection.is_empty() {
                    let values = self.apply(f[1], &[], depth + 1)?;
                    let [rows] = values.as_slice() else {
                        return Err(fail("view export must return one rows value"));
                    };
                    self.row_tuples(*rows)
                } else {
                    self.view_tuples(f[0], selection, depth + 1)
                }
            }
            Object::Record(kind, f) if kind == "explicit-view" && f.len() == 3 => {
                let rows = if selection.is_empty()
                    && !matches!(self.arena.get(f[2])?, Object::Boolean(false))
                {
                    let values = self.apply(f[2], &[], depth + 1)?;
                    let [rows] = values.as_slice() else {
                        return Err(fail("view export must return one rows value"));
                    };
                    *rows
                } else {
                    f[0]
                };
                let rows = self.row_tuples(rows)?;
                select(rows, &selectors)
            }
            Object::Record(kind, f) if kind == "lazy-view" => {
                let values = self.apply(f[0], &[], depth + 1)?;
                let [rows] = values.as_slice() else {
                    return Err(fail("lazy view must return one rows value"));
                };
                let rows = self.row_tuples(*rows)?;
                if rows.len() != index(self.arena, f[1])? {
                    return Err(fail("lazy view cardinality changed"));
                }
                select(rows, &selectors)
            }
            _ => Err(fail("relation view required")),
        }
    }
    pub(super) fn row_tuples(&mut self, id: Id) -> Result<Vec<Row>> {
        let snapshot = super::freeze::snapshot()?;
        self.arena
            .items(id)?
            .into_iter()
            .map(|r| {
                self.arena
                    .items(r)?
                    .into_iter()
                    .map(|v| self.arena.freeze(self.arena.identity, snapshot, v))
                    .collect::<Result<Vec<_>>>()
                    .map(Into::into)
            })
            .collect()
    }
}
fn select(
    rows: impl IntoIterator<Item = Row>,
    selectors: &[(usize, crate::Value)],
) -> Result<Vec<Row>> {
    let mut out = Vec::new();
    for row in rows {
        let mut matched = true;
        for (c, v) in selectors {
            let cell = row.get(*c).ok_or_else(|| fail("view column outside row"))?;
            if cell != v {
                matched = false;
                break;
            }
        }
        if matched {
            out.push(row);
        }
    }
    Ok(out)
}
