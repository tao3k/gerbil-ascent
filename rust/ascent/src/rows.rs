//! Typed set observations can be compared without constructing an engine or an authority claim.
use crate::{Data, Result, invalid_data as invalid};
use std::collections::BTreeSet;
/// Compare relation sets, preserving native Boolean, integer, text and structured value identity.
/// # Errors
/// Rejects malformed tuple lists or inconsistent arities within either relation.
pub fn rows_equal(left: &Data, right: &Data) -> Result<bool> {
    Ok(normalize(left)? == normalize(right)?)
}
fn normalize(rows: &Data) -> Result<BTreeSet<&Data>> {
    let rows = rows.list()?;
    let arity = rows.first().map(Data::list).transpose()?.map(<[Data]>::len);
    rows.iter()
        .map(|row| {
            if Some(row.list()?.len()) != arity {
                return Err(invalid("inconsistent relation tuple arity"));
            }
            Ok(row)
        })
        .collect()
}
