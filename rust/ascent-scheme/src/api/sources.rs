//! Original Scheme source admission followed by owned-data execution.
use super::{Engine, Evidence, id, invoke, policy};
use gerbil_ascent::{Catalog, Data, FactLimits, Result, SourceSession};
use std::collections::BTreeMap;

/// Native callback session or a finite DAG transferred to the caller's Rayon pool.
pub enum Source {
    Rayon(SourceSession),
    Scheme(Evidence),
}
impl Engine {
    /// Admit original Scheme source text and select its owned execution path.
    /// # Errors
    /// Preserves native syntax/resource errors and finite DAG admission failures.
    pub fn load_sources(
        &self,
        texts: &[String],
        limits: FactLimits,
        rules_only: bool,
    ) -> Result<Source> {
        super::check(self, false)?;
        let loaded = invoke(
            if rules_only {
                "open-rule-sources"
            } else {
                "open-sources"
            },
            [
                (
                    "sources",
                    Data::List(texts.iter().cloned().map(Data::from).collect()),
                ),
                ("factLimits", policy(limits)),
            ],
        )?;
        let projection = loaded.field("projection")?;
        if projection.field("status")?.text()? != "supported" {
            return Evidence::new(self, loaded).map(Source::Scheme);
        }
        let result = (|| {
            let mut catalog = Catalog::read(projection.field("program")?)?;
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
                .map(Source::Rayon)
        })();
        // Projection owns only Rust values; release the temporary VM session on
        // admission failure as well as success, before any Rayon execution.
        invoke("close", [("handle", Data::from(id(&loaded, "handle")?))])?;
        result
    }
    /// Parse the original inert rule interface in Scheme and return owned catalog data.
    /// # Errors
    /// Rejects executable syntax and malformed declarations through native admission.
    pub fn read_rules(&self, texts: &[String]) -> Result<Data> {
        super::check(self, false)?;
        invoke(
            "read-rules",
            [(
                "sources",
                Data::List(texts.iter().cloned().map(Data::from).collect()),
            )],
        )
    }
}
