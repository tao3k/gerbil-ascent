//! Exercise publication I/O against the archive produced for this benchmark.
use gerbil_ascent::{Error, Result};
use sha2::{Digest, Sha256};
use std::{
    fs::{self, File},
    io,
    path::Path,
    process::{Child, Command, Stdio},
    sync::Barrier,
    thread,
    time::{Duration, Instant},
};

const CLIENTS: usize = 12;
const ROUNDS: usize = 8;
const LIMIT: Duration = Duration::from_mins(3);
pub const WORKER_ARG: &str = "--archive-load";

pub struct ArchiveLoad {
    child: Child,
    scratch: tempfile::TempDir,
    started: Instant,
}

impl ArchiveLoad {
    pub fn start() -> Result<Self> {
        let scratch = tempfile::tempdir().map_err(evaluation)?;
        let started = Instant::now();
        let child = Command::new(std::env::current_exe().map_err(evaluation)?)
            .arg(WORKER_ARG)
            .arg(scratch.path())
            .stdin(Stdio::null())
            .spawn()
            .map_err(evaluation)?;
        let mut load = Self {
            child,
            scratch,
            started,
        };
        let ready = load.scratch.path().join("start");
        while load.started.elapsed() < LIMIT {
            if let Some(status) = load.child.try_wait().map_err(evaluation)? {
                return Err(evaluation(format!(
                    "archive load exited before release: {status}"
                )));
            }
            if ready.try_exists().map_err(evaluation)? {
                return Ok(load);
            }
            thread::sleep(Duration::from_millis(5));
        }
        Err(evaluation("archive load did not start within 180s"))
    }

    pub fn finish(mut self) -> Result<()> {
        while self.started.elapsed() < LIMIT {
            if let Some(status) = self.child.try_wait().map_err(evaluation)? {
                return if status.success() {
                    Ok(())
                } else {
                    Err(evaluation(status))
                };
            }
            thread::sleep(Duration::from_millis(5));
        }
        Err(evaluation("archive load exceeded 180s"))
    }
}

impl Drop for ArchiveLoad {
    fn drop(&mut self) {
        if !matches!(self.child.try_wait(), Ok(Some(_))) {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}

pub fn publish(directory: &Path) -> Result<()> {
    let source = Path::new(env!("OUT_DIR")).join("archive/libascent_hybrid.a");
    let (size, digest) = fingerprint(&source)?;
    if size == 0 {
        return Err(evaluation("empty production archive"));
    }
    let start = Barrier::new(CLIENTS + 1);
    thread::scope(|scope| {
        let workers = (0..CLIENTS)
            .map(|client| {
                let source = &source;
                let start = &start;
                scope.spawn(move || {
                    let output = directory.join(format!("archive-{client}.a"));
                    start.wait();
                    for _ in 0..ROUNDS {
                        let written = fs::copy(source, &output).map_err(evaluation)?;
                        if written != size || fingerprint(&output)? != (size, digest) {
                            return Err(evaluation("archive load copy differs from its source"));
                        }
                    }
                    Ok(())
                })
            })
            .collect::<Vec<_>>();
        let marked = fs::write(directory.join("start"), []).map_err(evaluation);
        start.wait();
        marked?;
        for worker in workers {
            worker
                .join()
                .map_err(|_| evaluation("archive load worker panicked"))??;
        }
        Ok(())
    })?;
    eprintln!(
        "PROVENANCE-ARCHIVE-OK clients={CLIENTS} rounds={ROUNDS} copies={} bytes={size} sha256={digest:x}",
        CLIENTS * ROUNDS,
    );
    Ok(())
}

fn fingerprint(path: &Path) -> Result<(u64, sha2::digest::Output<Sha256>)> {
    let mut file = File::open(path).map_err(evaluation)?;
    let mut hash = Sha256::new();
    let size = io::copy(&mut file, &mut hash).map_err(evaluation)?;
    Ok((size, hash.finalize()))
}

fn evaluation(error: impl std::fmt::Display) -> Error {
    Error::Evaluation(error.to_string())
}
