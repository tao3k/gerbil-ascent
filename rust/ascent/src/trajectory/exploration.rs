//! Read-only, open-world attempt comparison. Unknown inputs never imply equality.
use super::State;
use crate::{Data, Result};

const PREMISES: [&str; 6] = [
    "questionIdentity",
    "scopeIdentity",
    "operationIdentity",
    "inputIdentity",
    "toolIdentity",
    "modelIdentity",
];

impl State {
    pub(super) fn explore(&self, candidate: &Data) -> Result<Data> {
        candidate.field("questionIdentity")?.identity()?;
        candidate.field("operationIdentity")?.identity()?;
        candidate.field("inputIdentity")?.identity()?;
        for key in PREMISES {
            if let Some(value) = candidate.get(key) {
                value.identity()?;
            }
        }
        if let Some(contract) = candidate.get("contractIdentity") {
            contract.identity()?;
        }
        let mut comparisons = Vec::new();
        for earlier in &self.events {
            if earlier.field("kind")?.text()? != "attempt" {
                continue;
            }
            if earlier.field("questionIdentity")? != candidate.field("questionIdentity")? {
                continue;
            }
            let historical = *earlier.field("generation")?.natural()? != self.generation.into();
            let mut changed = Vec::new();
            let mut unknown = Vec::new();
            for key in PREMISES {
                match (earlier.get(key), candidate.get(key)) {
                    (Some(left), Some(right)) if left != right => changed.push(key.into()),
                    (None, _) | (_, None) => unknown.push(key.into()),
                    _ => {}
                }
            }
            let relation = if historical {
                "historical"
            } else if !changed.is_empty() {
                "changed-premise"
            } else if !unknown.is_empty() {
                "comparison-unknown"
            } else {
                "exact-current"
            };
            let reference = earlier
                .get("resultReference")
                .filter(|value| value.identity().is_ok_and(|id| {
                    self.verified_references.contains(id)
                        && earlier.get("contractIdentity") == candidate.get("contractIdentity")
                        && self.consumed.get(id).is_some_and(|contract| {
                            earlier.get("contractIdentity") == Some(&Data::from(contract.as_str()))
                        })
                }))
                .cloned()
                .unwrap_or(Data::Bool(false));
            comparisons.push(Data::object([
                ("earlierEvent", earlier.field("id")?.clone()),
                ("relation", relation.into()),
                ("changedPremises", Data::List(changed)),
                ("unknownPremises", Data::List(unknown)),
                ("currentEvidenceReference", if historical { Data::Bool(false) } else { reference }),
            ]));
        }
        Ok(Data::object([
            ("schema", "ascent.trajectory-exploration.v1".into()),
            ("sourceIdentity", self.source.clone().into()),
            ("generation", self.generation.into()),
            ("eventCount", self.events.len().into()),
            ("comparisons", Data::List(comparisons)),
            ("executionAuthorized", false.into()),
            ("actionSelected", false.into()),
        ]))
    }
}
