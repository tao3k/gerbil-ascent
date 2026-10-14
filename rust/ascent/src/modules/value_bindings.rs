//! Multiple values retain normal parallel or sequential lexical binding semantics.
use super::{
    evaluation::{Evaluation, parameters},
    objects::{EnvId, Id, fail},
};
use crate::{Result, source::Datum};
use std::collections::BTreeSet;
impl Evaluation<'_> {
    pub(super) fn local_values(
        &mut self,
        args: &[Datum],
        env: EnvId,
        depth: usize,
        sequential: bool,
    ) -> Result<Vec<Id>> {
        let [Datum::List(bindings), body @ ..] = args else {
            return Err(fail("multiple-value binding shape"));
        };
        if body.is_empty() {
            return Err(fail("multiple-value body required"));
        }
        let mut local = self.arena.env(Some(env))?;
        let mut seen = BTreeSet::new();
        for binding in bindings {
            let Datum::List(pair) = binding else {
                return Err(fail("multiple-value binding pair required"));
            };
            let [pattern, expression] = pair.as_slice() else {
                return Err(fail("multiple-value binding pair required"));
            };
            let (names, rest) = parameters(pattern)?;
            if !sequential
                && names
                    .iter()
                    .chain(rest.iter())
                    .any(|name| !seen.insert(name.clone()))
            {
                return Err(fail("duplicate multiple-value binding"));
            }
            let values = self.eval(expression, if sequential { local } else { env }, depth + 1)?;
            if values.len() < names.len() || (rest.is_none() && values.len() != names.len()) {
                return Err(fail("multiple-value binding arity mismatch"));
            }
            if sequential {
                local = self.arena.env(Some(local))?;
            }
            for (name, value) in names.iter().zip(&values) {
                self.arena.bind(local, name.clone(), *value);
            }
            if let Some(rest) = rest {
                let tail = self.arena.list(&values[names.len()..])?;
                self.arena.bind(local, rest, tail);
            }
        }
        self.sequence(body, local, depth + 1)
    }
}
