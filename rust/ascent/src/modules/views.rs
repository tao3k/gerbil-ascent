//! Immutable relation views share typed storage and explicit ordering contracts.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, fail},
    operator_values::{count, index},
};
use crate::Result;
use num_rational::BigRational;
use std::collections::BTreeSet;
pub(super) const EXPORTS: &[&str] = &[
    "gerbil-ascent-explicit-view",
    "gerbil-ascent-lazy-explicit-view",
    "gerbil-ascent-view-with-export",
    "gerbil-ascent-view-rows",
    "gerbil-ascent-view-contains?",
    "relation-view-count",
    "relation-view-units",
    "relation-view?",
    "gerbil-ascent-view-union",
    "gerbil-ascent-view-difference",
    "gerbil-ascent-view-bind",
    "relation-view-identity",
    "relation-view-generation",
    "relation-view-revision",
    "relation-view-lane",
];
impl Evaluation<'_> {
    pub(super) fn view(&mut self, name: &str, args: &[Id], depth: usize) -> Result<Vec<Id>> {
        self.check(depth)?;
        let result = match name {
            "gerbil-ascent-explicit-view" | "gerbil-ascent-lazy-explicit-view" => {
                self.explicit_view(name, args)?
            }
            "gerbil-ascent-view-with-export" => {
                count(args, 2)?;
                if !self.is_view(args[0])?
                    || !matches!(self.arena.get(args[1])?, Object::Procedure(_))
                {
                    return Err(fail("view and export procedure required"));
                }
                self.arena
                    .add(Object::Record("export-view".into(), args.to_vec()))?
            }
            "relation-view?" => {
                count(args, 1)?;
                let yes = self.is_view(args[0])?;
                self.arena.add(Object::Boolean(yes))?
            }
            "relation-view-count" | "relation-view-units" => {
                count(args, 1)?;
                let n = self.view_measure(args[0], name == "relation-view-units", depth + 1)?;
                self.arena
                    .add(Object::Number(BigRational::from_integer(n.into())))?
            }
            "gerbil-ascent-view-contains?" => {
                count(args, 2)?;
                let spine = self.arena.list(&[args[1]])?;
                let row = self.row_tuples(spine)?;
                let row = &row[0];
                let yes = match self.arena.get(args[0])?.clone() {
                    Object::ClosureView(view, _) => view.contains(row),
                    Object::RowsView(rows, _) => rows.contains(row),
                    _ => self.view_tuples(args[0], &[], depth + 1)?.contains(row),
                };
                self.arena.add(Object::Boolean(yes))?
            }
            "gerbil-ascent-view-rows" => {
                if args.len() != 1 && args.len() != 3 {
                    return Err(fail("view rows arity"));
                }
                let rows = self.view_tuples(args[0], &args[1..], depth + 1)?;
                self.arena.rows_object(&rows)?
            }
            "gerbil-ascent-view-union" | "gerbil-ascent-view-difference" => {
                self.view_set(name, args, depth + 1)?
            }
            "gerbil-ascent-view-bind" => {
                count(args, 5)?;
                if !self.is_view(args[0])? {
                    return Err(fail("relation view required"));
                }
                index(self.arena, args[2])?;
                index(self.arena, args[3])?;
                self.arena
                    .add(Object::Record("bound-view".into(), args.to_vec()))?
            }
            "relation-view-identity"
            | "relation-view-generation"
            | "relation-view-revision"
            | "relation-view-lane" => {
                count(args, 1)?;
                match self.arena.get(args[0])?.clone() {
                    Object::Record(kind, f) if kind == "bound-view" => {
                        f[match name {
                            "relation-view-identity" => 1,
                            "relation-view-generation" => 2,
                            "relation-view-revision" => 3,
                            _ => 4,
                        }]
                    }
                    _ => {
                        if !self.is_view(args[0])? {
                            return Err(fail("relation view required"));
                        }
                        self.arena.add(Object::Boolean(false))?
                    }
                }
            }
            _ => return Err(fail("unknown view procedure")),
        };
        Ok(vec![result])
    }
    fn explicit_view(&mut self, name: &str, args: &[Id]) -> Result<Id> {
        count(args, 2)?;
        let n = index(self.arena, args[1])?;
        if name == "gerbil-ascent-lazy-explicit-view"
            && matches!(self.arena.get(args[0])?, Object::Procedure(_))
        {
            return self
                .arena
                .add(Object::Record("lazy-view".into(), args.to_vec()));
        }
        let rows = self.row_tuples(args[0])?;
        if rows.len() != n {
            return Err(fail("explicit view cardinality mismatch"));
        }
        // A frozen typed row owns immutable structure; lexical opaque cells retain input roots.
        self.arena.add(Object::RowsView(rows.into(), vec![args[0]]))
    }
    fn view_set(&mut self, name: &str, args: &[Id], depth: usize) -> Result<Id> {
        count(
            args,
            if name == "gerbil-ascent-view-union" {
                2
            } else {
                3
            },
        )?;
        let left = self.view_tuples(args[0], &[], depth + 1)?;
        let right = self.view_tuples(args[1], &[], depth + 1)?;
        let l = left.iter().cloned().collect::<BTreeSet<_>>();
        let r = right.iter().cloned().collect::<BTreeSet<_>>();
        let rows = if name == "gerbil-ascent-view-union" {
            let mut seen = BTreeSet::new();
            left.into_iter()
                .chain(right)
                .filter(|row| seen.insert(row.clone()))
                .collect::<Vec<_>>()
        } else {
            if !r.is_subset(&l) {
                return Err(fail(
                    "view difference requires older to be a subset of newer",
                ));
            }
            let rows = left
                .into_iter()
                .filter(|row| !r.contains(row))
                .collect::<Vec<_>>();
            if rows.len() != index(self.arena, args[2])? {
                return Err(fail("view difference count mismatch"));
            }
            rows
        };
        self.check(depth)?;
        self.arena
            .add(Object::RowsView(rows.into(), args[..2].to_vec()))
    }
}
