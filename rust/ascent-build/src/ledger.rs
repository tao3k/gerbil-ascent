//! Pair real upstream transitions, including interleaved compiler workers.
use super::policy;
use gerbil_scheme_aot_build::ProgramArchiveObservation;
use serde_json::{Value, json};
use std::collections::{BTreeMap, BTreeSet};

type Key = (String, String, Option<String>);
#[derive(Default)]
pub struct Phase {
    started: usize,
    completed: usize,
    cached: usize,
    failed: usize,
    worker_ns: u128,
}
#[derive(Default)]
pub struct Ledger {
    pending: BTreeSet<Key>,
    terminal: BTreeSet<Key>,
    phases: BTreeMap<String, Phase>,
    pub errors: Vec<String>,
    pub graphs: usize,
    pub compilation_units: usize,
}
impl Ledger {
    pub fn observe(&mut self, event: ProgramArchiveObservation<'_>) -> Result<(), String> {
        let kind = policy::decode(event.state, event.elapsed.is_some(), event.phase)
            .ok_or("unknown or malformed upstream archive transition")?;
        if kind == 4 {
            self.graphs += 1;
            return if self.graphs == 1 {
                Ok(())
            } else {
                Err("duplicate archive graph".into())
            };
        }
        self.compilation_units = self
            .compilation_units
            .checked_add(policy::compilation_units(event.phase, kind))
            .ok_or("archive compilation count overflow")?;
        let key = (
            event.phase.into(),
            event.operation.into(),
            event.subject.map(str::to_owned),
        );
        let phase = self.phases.entry(event.phase.into()).or_default();
        match kind {
            0 => {
                if self.terminal.contains(&key) || !self.pending.insert(key) {
                    return Err("duplicate archive start".into());
                }
                phase.started += 1;
            }
            1 | 3 => {
                if !self.pending.remove(&key) || !self.terminal.insert(key) {
                    return Err("unpaired archive terminal".into());
                }
                if kind == 1 {
                    phase.completed += 1;
                } else {
                    phase.failed += 1;
                }
                phase.worker_ns = phase
                    .worker_ns
                    .checked_add(event.elapsed.ok_or("missing elapsed")?.as_nanos())
                    .ok_or("archive cost overflow")?;
            }
            2 => {
                if self.pending.contains(&key) || !self.terminal.insert(key) {
                    return Err("cached work also executed or repeated".into());
                }
                phase.cached += 1;
            }
            _ => return Err("invalid decoded archive event".into()),
        }
        Ok(())
    }
    pub fn metrics(&self, changed: usize, sources: usize, builder_ok: bool) -> policy::Metrics {
        policy::Metrics {
            starts: self.phases.values().map(|p| p.started).sum(),
            completed: self.phases.values().map(|p| p.completed).sum(),
            pending: self.pending.len(),
            failed: self.phases.values().map(|p| p.failed).sum(),
            invalid: self.errors.len(),
            changed,
            sources,
            graph_ok: self.graphs == 1,
            builder_ok,
        }
    }
    pub fn phases(&self) -> Value {
        self.phases.iter().map(|(name, p)| (name.clone(), json!({
            "started": p.started, "completed": p.completed, "cached": p.cached,
            "failed": p.failed, "worker_nanoseconds": p.worker_ns,
            "scope": if name == "module-c-batch" { "inclusive-parent" } else { "operation" }
        }))).collect()
    }
}
