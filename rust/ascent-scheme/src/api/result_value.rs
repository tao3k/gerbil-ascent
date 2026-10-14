//! Native result cells retain the exact source generation and owning result.
use super::session::EvidenceResult;
use gerbil_ascent::{Data, ObjectInput, Result, ValueReference};

#[derive(Clone)]
pub struct ResultValue {
    pub(super) result: EvidenceResult,
    pub(super) relation: String,
    pub(super) row: usize,
    pub(super) column: usize,
}
impl ResultValue {
    /// Resolve a generation-checked native cell as a typed argument.
    /// # Errors
    /// Rejects revoked results or invalid row/column coordinates.
    pub fn input(&self) -> Result<ObjectInput> {
        let receipt = self.result.rows(&self.relation)?;
        let graph = receipt.field("value")?;
        let row = list_cell(graph, graph.field("root")?, self.row)?;
        let cell = list_cell(graph, row, self.column)?;
        if let Some(node) = cell.get("ref") {
            Ok(ObjectInput::Reference(ValueReference {
                owner: self.result.owner_id(),
                result: self.result.handle(),
                node: node.index()?,
            }))
        } else {
            match cell.field("type")?.text()? {
                "boolean" => Ok(ObjectInput::Boolean(cell.field("value")?.boolean()?)),
                "number" => Ok(ObjectInput::Number(cell.field("value")?.text()?.into())),
                "character" => Ok(ObjectInput::Character(
                    char::from_u32(
                        u32::try_from(cell.field("value")?.index()?)
                            .map_err(|_| crate::failure("character range"))?,
                    )
                    .ok_or_else(|| crate::failure("character range"))?,
                )),
                _ => Err(crate::failure(
                    "native cell requires a retained object reference",
                )),
            }
        }
    }
}
fn node<'a>(graph: &'a Data, item: &'a Data) -> Result<&'a Data> {
    if let Some(id) = item.get("ref") {
        let id = id.index()?;
        graph
            .field("nodes")?
            .list()?
            .iter()
            .find(|n| n.field("id").and_then(Data::index) == Ok(id))
            .ok_or_else(|| crate::failure("unknown native node"))
    } else {
        Ok(item)
    }
}
fn list_cell<'a>(graph: &'a Data, mut item: &'a Data, index: usize) -> Result<&'a Data> {
    for _ in 0..index {
        item = node(graph, item)?.field("cdr")?;
    }
    node(graph, item)?.field("car")
}
