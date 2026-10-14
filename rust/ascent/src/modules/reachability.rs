//! Scheme DSL procedures delegate to compressed Rust closure owners and immutable cuts.
use super::{
    evaluation::Evaluation,
    objects::{Id, Object, fail},
    operator_values::{count, index},
};
use crate::{Cancellation, Reachability, Result, Row};
use num_rational::BigRational;
use std::sync::{Arc, Mutex};
pub(super) const EXPORTS: &[&str] = &[
    "gerbil-ascent-trrel-uf-state",
    "gerbil-ascent-trrel-uf-count-insert!",
    "gerbil-ascent-trrel-uf-insert!",
    "gerbil-ascent-trrel-uf-freeze",
    "gerbil-ascent-trrel-uf-validate",
    "gerbil-ascent-trrel-uf-resource-observation",
    "gerbil-ascent-trrel-uf-view-lookup",
];
impl Evaluation<'_> {
    pub(super) fn reachability(
        &mut self,
        name: &str,
        args: &[Id],
        depth: usize,
    ) -> Result<Vec<Id>> {
        self.check(depth)?;
        if name == "gerbil-ascent-trrel-uf-state" {
            count(args, 0)?;
            return self
                .arena
                .add(Object::Reachability(
                    Arc::new(Mutex::new(Reachability::new())),
                    Vec::new(),
                ))
                .map(|v| vec![v]);
        }
        if name == "gerbil-ascent-trrel-uf-view-lookup" {
            count(args, 3)?;
            return self.view("gerbil-ascent-view-rows", args, depth);
        }
        let state = *args
            .first()
            .ok_or_else(|| fail("reachability state required"))?;
        let Object::Reachability(core, roots) = self.arena.get(state)?.clone() else {
            return Err(fail("reachability state required"));
        };
        let mut core = core
            .lock()
            .map_err(|_| fail("reachability lock poisoned"))?;
        let result = match name {
            "gerbil-ascent-trrel-uf-freeze" => {
                count(args, 2)?;
                if !matches!(self.arena.get(args[1])?, Object::Boolean(_)) {
                    return Err(fail("freeze mode Boolean required"));
                }
                self.arena.add(Object::ClosureView(core.freeze(), roots))?
            }
            "gerbil-ascent-trrel-uf-resource-observation" => {
                count(args, 1)?;
                let values = core
                    .resources()
                    .into_iter()
                    .map(|n| {
                        self.arena
                            .add(Object::Number(BigRational::from_integer(n.into())))
                    })
                    .collect::<Result<Vec<_>>>()?;
                self.arena.add(Object::Vector(values))?
            }
            "gerbil-ascent-trrel-uf-validate" => {
                count(args, 1)?;
                self.arena
                    .add(Object::Boolean(core.validate(&Cancellation::default())?))?
            }
            "gerbil-ascent-trrel-uf-count-insert!" | "gerbil-ascent-trrel-uf-insert!" => {
                count(args, 3)?;
                let budget = index(self.arena, args[2])?;
                let cells = self.arena.items(args[1])?;
                let snapshot = super::freeze::snapshot()?;
                let values = cells
                    .iter()
                    .map(|id| self.arena.freeze(self.arena.identity, snapshot, *id))
                    .collect::<Result<Vec<_>>>()?;
                let before = core.freeze();
                let mut next = core.clone();
                let added = next.insert(&values, budget, &Cancellation::default())?;
                let mut roots = roots;
                roots.push(args[1]);
                let result = if name == "gerbil-ascent-trrel-uf-count-insert!" {
                    self.arena
                        .add(Object::Number(BigRational::from_integer(added.into())))?
                } else {
                    let current = next.freeze();
                    let rows = current
                        .rows(&[], 200_000, &Cancellation::default())?
                        .into_iter()
                        .filter(|r| !before.contains(r))
                        .collect::<Vec<Row>>();
                    if rows.len() != added {
                        return Err(fail("closure delta count mismatch"));
                    }
                    self.arena
                        .add(Object::RowsView(rows.into(), roots.clone()))?
                };
                self.check(depth)?;
                // Retaining the input graph protects opaque cell identities through collection.
                if let Object::Reachability(_, retained) = self
                    .arena
                    .objects
                    .get_mut(&state)
                    .ok_or_else(|| fail("reachability state revoked"))?
                {
                    retained.clone_from(&roots);
                }
                *core = next;
                result
            }
            _ => return Err(fail("unknown reachability procedure")),
        };
        Ok(vec![result])
    }
}
