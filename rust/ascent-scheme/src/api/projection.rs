//! One admission path for owned Scheme program projections.
use super::Engine;
use gerbil_ascent::{Catalog, Data, FactLimits, Result, SourceSession};
use std::collections::BTreeMap;
impl Engine {
    pub(super) fn open_projection(
        &self,
        loaded: &Data,
        limits: FactLimits,
    ) -> Result<SourceSession> {
        let mut catalog = Catalog::read(loaded.field("projection")?.field("program")?)?;
        let ceiling = |name| -> Result<Option<usize>> {
            let value = loaded.field("factLimits")?.field(name)?;
            if value == &Data::from("unlimited") {
                Ok(None)
            } else {
                value.index().map(Some)
            }
        };
        catalog.program.fact_limits = FactLimits {
            input: ceiling("input")?,
            derived: ceiling("derived")?,
            output: ceiling("output")?,
        };
        if loaded.field("descriptors")?.list()?.len() != catalog.program.relations.len() {
            return Err(crate::failure(
                "native projection descriptor count mismatch",
            ));
        }
        let aliases = loaded
            .field("descriptors")?
            .list()?
            .iter()
            .zip(&catalog.program.relations)
            .map(|(descriptor, relation)| {
                Ok((
                    descriptor.field("name")?.text()?.into(),
                    relation.name.clone(),
                ))
            })
            .collect::<Result<BTreeMap<_, _>>>()?;
        self.open_exported_program(catalog.program, aliases, limits)
    }
}
