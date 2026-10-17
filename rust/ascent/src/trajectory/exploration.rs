//! Read-only, open-world attempt comparison. Unknown inputs never imply equality.
use super::State;
use crate::{Data, Result};
use std::collections::BTreeMap;

const PREMISES: [&str; 6] = [
    "questionIdentity",
    "scopeIdentity",
    "operationIdentity",
    "inputIdentity",
    "toolIdentity",
    "modelIdentity",
];

impl State {
    pub(super) fn context(&self) -> Result<Data> {
        let attempts = self
            .events
            .iter()
            .filter_map(|event| self.context_attempt(event).transpose())
            .collect::<Result<Vec<_>>>()?;
        Ok(Data::object([
            ("schema", "ascent.trajectory-context.v1".into()),
            ("sourceIdentity", self.source.clone().into()),
            ("generation", self.generation.into()),
            ("eventCount", self.events.len().into()),
            ("prefixIdentity", Data::digest_slice(&self.events).into()),
            ("attempts", Data::List(attempts)),
            ("executionAuthorized", false.into()),
            ("actionSelected", false.into()),
        ]))
    }

    fn context_attempt(&self, event: &Data) -> Result<Option<Data>> {
        if event.field("kind")?.text()? != "attempt" {
            return Ok(None);
        }
        let premises = PREMISES
            .into_iter()
            .chain(["proposalIdentity", "purpose"])
            .filter_map(|key| event.get(key).map(|value| (key.into(), value.clone())))
            .collect::<BTreeMap<_, _>>();
        Ok(Some(Data::object([
            ("earlierEvent", event.field("id")?.clone()),
            ("generation", event.field("generation")?.clone()),
            (
                "historical",
                (event.field("generation")?.natural()? != &self.generation.into()).into(),
            ),
            ("premises", Data::Map(premises)),
        ])))
    }

    pub(super) fn explore(&self, candidate: &Data) -> Result<Data> {
        validate_candidate(candidate)?;
        let comparisons = self
            .events
            .iter()
            .filter_map(|earlier| self.compare_attempt(earlier, candidate).transpose())
            .collect::<Result<Vec<_>>>()?;
        Ok(Data::object([
            ("schema", "ascent.trajectory-exploration.v1".into()),
            ("sourceIdentity", self.source.clone().into()),
            ("generation", self.generation.into()),
            ("eventCount", self.events.len().into()),
            ("prefixIdentity", Data::digest_slice(&self.events).into()),
            ("comparisons", Data::List(comparisons)),
            ("executionAuthorized", false.into()),
            ("actionSelected", false.into()),
        ]))
    }

    fn compare_attempt(&self, earlier: &Data, candidate: &Data) -> Result<Option<Data>> {
        if earlier.field("kind")?.text()? != "attempt"
            || earlier.field("questionIdentity")? != candidate.field("questionIdentity")?
        {
            return Ok(None);
        }
        let historical = *earlier.field("generation")?.natural()? != self.generation.into();
        let (changed, unknown) = changed_premises(earlier, candidate);
        let relation = if historical {
            "historical"
        } else if !changed.is_empty() {
            "changed-premise"
        } else if !unknown.is_empty() {
            "comparison-unknown"
        } else {
            "exact-current"
        };
        let reference = if historical {
            Data::Bool(false)
        } else {
            self.checked_reference(earlier, candidate)
        };
        Ok(Some(Data::object([
            ("earlierEvent", earlier.field("id")?.clone()),
            ("relation", relation.into()),
            ("changedPremises", Data::List(changed)),
            ("unknownPremises", Data::List(unknown)),
            ("currentEvidenceReference", reference),
        ])))
    }

    fn checked_reference(&self, earlier: &Data, candidate: &Data) -> Data {
        earlier
            .get("resultReference")
            .filter(|value| {
                value.identity().is_ok_and(|id| {
                    self.verified_references.contains(id)
                        && earlier.get("contractIdentity") == candidate.get("contractIdentity")
                        && self.consumed.get(id).is_some_and(|contract| {
                            earlier.get("contractIdentity") == Some(&Data::from(contract.as_str()))
                        })
                })
            })
            .cloned()
            .unwrap_or(Data::Bool(false))
    }
}

fn validate_candidate(candidate: &Data) -> Result<()> {
    for key in ["questionIdentity", "operationIdentity", "inputIdentity"] {
        candidate.field(key)?.identity()?;
    }
    for key in PREMISES.into_iter().chain(["contractIdentity"]) {
        if let Some(value) = candidate.get(key) {
            value.identity()?;
        }
    }
    Ok(())
}

fn changed_premises(earlier: &Data, candidate: &Data) -> (Vec<Data>, Vec<Data>) {
    let mut changed = Vec::new();
    let mut unknown = Vec::new();
    for key in PREMISES {
        match (earlier.get(key), candidate.get(key)) {
            (Some(left), Some(right)) if left != right => changed.push(key.into()),
            (None, _) | (_, None) => unknown.push(key.into()),
            _ => {}
        }
    }
    (changed, unknown)
}
