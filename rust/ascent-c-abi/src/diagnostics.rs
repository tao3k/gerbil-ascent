//! Opt-in real boundary timings, independent of results and admission authority.
use gerbil_ascent::Data;
use std::{collections::BTreeMap, time::Instant};
pub(super) struct Trace {
    pub enabled: bool,
    phases: BTreeMap<&'static str, u128>,
}
impl Trace {
    pub fn new(enabled: bool) -> Self {
        Self {
            enabled,
            phases: BTreeMap::new(),
        }
    }
    pub fn start(&self) -> Option<Instant> {
        self.enabled.then(Instant::now)
    }
    pub fn record(&mut self, name: &'static str, started: Option<Instant>) {
        self.elapsed(name, started.map(|v| v.elapsed().as_nanos()));
    }
    pub fn elapsed(&mut self, name: &'static str, elapsed: Option<u128>) {
        if let Some(elapsed) = elapsed {
            self.phases.insert(name, elapsed);
        }
    }
    pub fn snapshot(&self) -> Data {
        Data::object([
            ("enabled", self.enabled.into()),
            (
                "timingsNanoseconds",
                Data::Map(
                    self.phases
                        .iter()
                        .map(|(name, value)| ((*name).to_owned(), Data::Integer((*value).into())))
                        .collect(),
                ),
            ),
            (
                "scope",
                "last timing per boundary; nested phases must not be summed".into(),
            ),
        ])
    }
}
