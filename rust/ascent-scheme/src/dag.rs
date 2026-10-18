//! Transfer the native Scheme frontend's admitted finite DAG into owned Rust data.
use crate::{Runtime, failure};
use gerbil_ascent::{Catalog, Data, FactLimits, Program, Result};

/// A native Scheme program projection with no VM roots or borrowed heap data.
#[derive(Clone, Debug)]
pub struct Dag {
    pub program: Program,
    pub queries: Vec<String>,
}
impl Runtime {
    /// Load trusted native Scheme DSL and export an admitted finite execution DAG.
    /// Scheme closures, macros and module expansion execute in Scheme. A program
    /// that requires Scheme callbacks is explicitly rejected by this projection.
    /// # Errors
    /// Preserves native admission errors and rejects non-projectable programs.
    pub fn load_dag(&self, source: &str, constructor: &str, arguments: Vec<Data>) -> Result<Dag> {
        let loaded = self.call(&Data::object([
            ("operation", Data::from("open-evidence")),
            ("source", Data::from(source)),
            ("constructor", Data::from(constructor)),
            ("arguments", Data::List(arguments)),
            ("trusted", Data::Bool(true)),
        ]))?;
        // Release the temporary native inference owner on every projection outcome.
        let closed = self.call(&Data::object([
            ("operation", Data::from("close")),
            ("handle", loaded.field("handle")?.clone()),
        ]));
        closed?;
        let projection = loaded.field("projection")?;
        if projection.field("status")?.text()? != "supported" {
            return Err(failure(
                "program requires native Scheme execution; finite DAG unavailable",
            ));
        }
        let mut catalog = Catalog::read(projection.field("program")?)?;
        let ceiling = |name| -> Result<Option<usize>> {
            let value = loaded.field("factLimits")?.field(name)?;
            if value == &Data::from("unlimited") {
                Ok(None)
            } else {
                Ok(Some(value.index()?))
            }
        };
        catalog.program.fact_limits = FactLimits {
            input: ceiling("input")?,
            derived: ceiling("derived")?,
            output: ceiling("output")?,
        };
        Ok(Dag {
            program: catalog.program,
            queries: catalog.queries,
        })
    }
}
