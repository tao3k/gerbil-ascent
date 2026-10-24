//! Consume upstream observations without replacing the compiler or its cache.
use super::{
    input::{externally_owned, retain, snapshot},
    ledger::Ledger,
    policy,
};
use gerbil_scheme_aot_build::{ProgramArchiveObservation, ProgramArchiveObserver};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs::{self, File},
    io::Write,
    path::{Path, PathBuf},
    sync::Mutex,
    time::Instant,
};

struct State {
    log: File,
    ledger: Ledger,
    sources: BTreeMap<PathBuf, Value>,
}
pub struct Observer {
    state: Mutex<State>,
    receipt: PathBuf,
    wait_ns: u128,
    contents: PathBuf,
    started: Instant,
    owned_static: PathBuf,
}
impl Observer {
    pub fn new(
        out: &Path,
        contents: &Path,
        owned_static: &Path,
        wait_ns: u128,
    ) -> Result<Self, String> {
        fs::create_dir_all(contents).map_err(|e| e.to_string())?;
        let log = File::create(out.join("archive-events.jsonl")).map_err(|e| e.to_string())?;
        Ok(Self {
            state: Mutex::new(State {
                log,
                ledger: Ledger::default(),
                sources: BTreeMap::new(),
            }),
            receipt: out.join("archive-work.json"),
            wait_ns,
            contents: contents.into(),
            started: Instant::now(),
            owned_static: owned_static.into(),
        })
    }
    pub fn finish(&self, builder_ok: bool) -> Result<(), String> {
        let state = self.state.lock().map_err(|e| e.to_string())?;
        let changed = state
            .sources
            .iter()
            .filter(|(path, expected)| snapshot(path).as_ref().ok() != Some(expected))
            .count();
        let metrics = state
            .ledger
            .metrics(changed, state.sources.len(), builder_ok);
        let accepted = policy::complete(&metrics);
        let receipt = json!({"schema": "ascent.archive-work.v1", "accepted": accepted,
            "configuration": self.receipt.parent(),
            "session": format!("{}:{}", std::env::var("GITHUB_RUN_ID").unwrap_or_else(|_| "local".into()), std::env::var("GITHUB_RUN_ATTEMPT").unwrap_or_else(|_| "0".into())),
            "retained_inputs": self.contents,
            "starts": metrics.starts, "completed": metrics.completed, "pending": metrics.pending,
            "failed": metrics.failed, "invalid": metrics.invalid, "changed_inputs": changed,
            "graphs": state.ledger.graphs, "archive_object_compilations": state.ledger.compilation_units, "builder_ok": builder_ok,
            "lease_wait_ns": self.wait_ns, "observed_wall_ns": self.started.elapsed().as_nanos(), "sources": state.sources.values().collect::<Vec<_>>(),
            "phases": state.ledger.phases(), "errors": state.ledger.errors,
            "cost_scope": "upstream operation durations; parallel workers and inclusive parents are not elapsed-time totals"});
        fs::write(
            &self.receipt,
            serde_json::to_vec_pretty(&receipt).map_err(|e| e.to_string())?,
        )
        .map_err(|e| e.to_string())?;
        println!(
            "ASCENT archive work {} accepted={accepted}",
            self.receipt.display()
        );
        if accepted {
            Ok(())
        } else {
            Err(format!(
                "incomplete archive observation: {}",
                self.receipt.display()
            ))
        }
    }
}
fn record(state: &mut State, row: &Value) -> Result<(), String> {
    serde_json::to_writer(&mut state.log, row).map_err(|e| e.to_string())?;
    writeln!(&mut state.log)
        .and_then(|()| state.log.flush())
        .map_err(|e| e.to_string())
}
impl ProgramArchiveObserver for Observer {
    fn observe(&self, event: ProgramArchiveObservation<'_>) {
        let mut state = self.state.lock().expect("archive observer poisoned");
        let row = json!({"kind": "transition", "phase": event.phase, "state": event.state,
            "operation": event.operation, "subject": event.subject,
            "elapsed_ns": event.elapsed.map(|d| d.as_nanos())});
        if let Err(error) = record(&mut state, &row).and_then(|()| state.ledger.observe(event)) {
            state.ledger.errors.push(error);
        }
    }
    fn observe_source_input(&self, source: &Path) {
        let watch = externally_owned(
            source,
            self.contents.parent().expect("input directory parent"),
            &self.owned_static,
        );
        if watch {
            println!("cargo:rerun-if-changed={}", source.display());
        }
        let mut state = self.state.lock().expect("archive observer poisoned");
        let result = retain(source, &self.contents).and_then(|row| {
            record(
                &mut state,
                &json!({"kind": "source", "input": row, "cargo_watch": watch}),
            )?;
            if let Some(old) = state.sources.insert(source.into(), row.clone())
                && old != row
            {
                return Err("archive input changed between observations".into());
            }
            Ok(())
        });
        if let Err(error) = result {
            state.ledger.errors.push(error);
        }
    }
}
