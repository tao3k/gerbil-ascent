//! Typed operation transport and admission helpers.
use gerbil_ascent::{Data, Error, Result};
use std::collections::BTreeMap;

pub(super) fn invoke(
    operation: &str,
    fields: impl IntoIterator<Item = (&'static str, Data)>,
) -> Result<Data> {
    let mut request = BTreeMap::from([("operation".into(), Data::from(operation))]);
    request.extend(fields.into_iter().map(|(k, v)| (k.into(), v)));
    crate::call(Data::Map(request))
}
pub(super) fn check(engine: &gerbil_ascent::Engine, closed: bool) -> Result<()> {
    if closed || engine.is_closed() {
        Err(Error::Closed)
    } else {
        Ok(())
    }
}
pub(super) fn policy(limits: gerbil_ascent::FactLimits) -> Data {
    Data::Map(
        [
            ("input", limits.input),
            ("derived", limits.derived),
            ("output", limits.output),
        ]
        .into_iter()
        .filter_map(|(k, v)| v.map(|v| (k.into(), Data::from(v))))
        .collect(),
    )
}
pub(super) fn id(value: &Data, name: &str) -> Result<u64> {
    u64::try_from(value.field(name)?.index()?).map_err(|_| crate::failure("native handle range"))
}
