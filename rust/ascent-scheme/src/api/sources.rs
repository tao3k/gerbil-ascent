//! Original Scheme source admission followed by owned-data execution.
use super::{Backend, Engine, Evidence, id, invoke, policy};
use gerbil_ascent::{Data, FactLimits, Result, SourceSession};

/// Native callback session or a finite DAG transferred to the caller's Rayon pool.
pub enum Source {
    Rayon(Box<SourceSession>),
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
        let loaded = self.load(
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
        if self.backend() == Some(Backend::Scheme) {
            return Evidence::new(self, loaded).map(Source::Scheme);
        }
        if projection.field("status")?.text()? != "supported" {
            if self.backend() == Some(Backend::Rayon) {
                invoke("close", [("handle", Data::from(id(&loaded, "handle")?))])?;
                return Err(crate::failure(
                    "program requires Scheme callbacks; Rayon projection unavailable",
                ));
            }
            return Evidence::new(self, loaded).map(Source::Scheme);
        }
        let result = self
            .open_projection(&loaded, limits)
            .map(|session| Source::Rayon(Box::new(session)));
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
        self.invoke(
            "read-rules",
            [(
                "sources",
                Data::List(texts.iter().cloned().map(Data::from).collect()),
            )],
        )
    }
}
