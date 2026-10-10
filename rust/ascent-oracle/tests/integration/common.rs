// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Shared Scheme process adapter for differential tests.

use std::{
    cmp::Ordering,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};

use ascent::lattice::Lattice;

// Ascent 0.8.0's public Product<T> lacks Hash, which its lattice storage
// requires. This newtype has the same coordinatewise product order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub(super) struct CoordinateMax(pub u32, pub u32);

impl PartialOrd for CoordinateMax {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        match (self.0.cmp(&other.0), self.1.cmp(&other.1)) {
            (Ordering::Equal, axis) | (axis, Ordering::Equal) => Some(axis),
            (Ordering::Less, Ordering::Less) => Some(Ordering::Less),
            (Ordering::Greater, Ordering::Greater) => Some(Ordering::Greater),
            _ => None,
        }
    }
}

impl Lattice for CoordinateMax {
    fn meet_mut(&mut self, other: Self) -> bool {
        let joined = Self(self.0.min(other.0), self.1.min(other.1));
        let changed = *self != joined;
        *self = joined;
        changed
    }

    fn join_mut(&mut self, other: Self) -> bool {
        let joined = Self(self.0.max(other.0), self.1.max(other.1));
        let changed = *self != joined;
        *self = joined;
        changed
    }
}

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(2)
        .expect("gerbil-ascent repository root")
        .to_path_buf()
}

#[path = "../support/pipe_capture.rs"]
mod pipe_capture;
#[path = "../unit/pipe_capture.rs"]
#[cfg(test)]
mod pipe_capture_tests;

fn reader_panic(payload: &(dyn std::any::Any + Send)) -> &str {
    payload
        .downcast_ref::<String>()
        .map(String::as_str)
        .or_else(|| payload.downcast_ref::<&str>().copied())
        .unwrap_or("non-string reader panic payload")
}

fn panic_receipt_path() -> PathBuf {
    root()
        .join(".cache/ascent")
        .join(format!("oracle-panics-{}.out", std::process::id()))
}

fn install_panic_receipt() {
    static INSTALL: std::sync::Once = std::sync::Once::new();
    INSTALL.call_once(|| {
        let path = panic_receipt_path();
        let _ = std::fs::create_dir_all(path.parent().expect("panic receipt directory"));
        let previous = std::panic::take_hook();
        std::panic::set_hook(Box::new(move |info| {
            static WRITER: std::sync::Mutex<()> = std::sync::Mutex::new(());
            // Keep the actual cause even when the shared stderr stream cannot
            // deliver the default hook. This never turns a panic into success.
            if let Ok(_guard) = WRITER.lock()
                && let Ok(mut output) = std::fs::OpenOptions::new()
                    .create(true)
                    .append(true)
                    .open(&path)
            {
                let _ = writeln!(output, "{info}");
            }
            previous(info);
        }));
    });
}

pub(super) fn scheme_output(recipe: &str, request: &str) -> String {
    install_panic_receipt();
    let root = root();
    let mut command = Command::new("just");
    command
        .current_dir(&root)
        .arg(recipe)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let gerbil_path = std::env::var_os("GERBIL_PATH")
        .expect("run the Rust oracle through `gerbil env` to set GERBIL_PATH");
    let inherited = std::env::var("GERBIL_LOADPATH").unwrap_or_default();
    command.env("GERBIL_PATH", gerbil_path);
    command.env("GERBIL_LOADPATH", format!("{}:{inherited}", root.display()));
    let mut child = command
        .spawn()
        .expect("launch gerbil-ascent Scheme fixture");
    eprintln!("ORACLE-FIXTURE-SPAWN recipe={recipe} pid={}", child.id());
    // Preserve the exact fixture bytes while exposing real IO progress. The
    // readers drain both streams independently, preventing pipe backpressure
    // and exposing real admission diagnostics without changing row bytes.
    let stdout = child.stdout.take().expect("Scheme fixture stdout");
    let reader_recipe = recipe.to_owned();
    let reader = std::thread::spawn(move || {
        pipe_capture::capture(stdout, |count| {
            eprintln!("ORACLE-FIXTURE-READ recipe={reader_recipe} bytes={count}");
        })
    });
    let stderr = child.stderr.take().expect("Scheme fixture stderr");
    let stderr_recipe = recipe.to_owned();
    let stderr_reader = std::thread::spawn(move || {
        pipe_capture::capture(stderr, |count| {
            eprintln!("ORACLE-FIXTURE-STDERR recipe={stderr_recipe} bytes={count}");
        })
    });
    // Always close stdin and collect the child/readers before admitting bytes.
    // A write/read failure must retain typed diagnostics, not a reader Any panic.
    let request_result = child
        .stdin
        .take()
        .expect("Scheme fixture stdin")
        .write_all(request.as_bytes());
    let status = child.wait().expect("collect Scheme fixture status");
    let stdout = reader.join().unwrap_or_else(|payload| {
        panic!(
            "Scheme stdout reader panicked recipe={recipe}: {}",
            reader_panic(payload.as_ref())
        )
    });
    let stderr = stderr_reader.join().unwrap_or_else(|payload| {
        panic!(
            "Scheme stderr reader panicked recipe={recipe}: {}",
            reader_panic(payload.as_ref())
        )
    });
    assert!(
        request_result.is_ok() && stdout.error.is_none() && stderr.error.is_none(),
        "Scheme fixture transport failed recipe={recipe} status={status}: request={request_result:?} stdout={:?} stderr={:?}\npartial stdout:\n{}\npartial stderr:\n{}",
        stdout.error,
        stderr.error,
        String::from_utf8_lossy(&stdout.bytes),
        String::from_utf8_lossy(&stderr.bytes)
    );
    let stdout = stdout.bytes;
    let stderr = stderr.bytes;
    eprintln!(
        "ORACLE-FIXTURE-END recipe={recipe} status={} bytes={}",
        status,
        stdout.len()
    );
    assert!(
        status.success(),
        "Scheme fixture failed:\nstdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&stdout),
        String::from_utf8_lossy(&stderr)
    );
    String::from_utf8(stdout).expect("Scheme output is UTF-8")
}
