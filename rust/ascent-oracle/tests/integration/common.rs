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

pub(super) fn scheme_output(recipe: &str, request: &str) -> String {
    let root = root();
    let mut command = Command::new("just");
    command
        .current_dir(&root)
        .arg(recipe)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    let inherited = std::env::var("GERBIL_LOADPATH").unwrap_or_default();
    let local_lib = root.join(".gerbil/lib");
    let mut loadpath = vec![root.display().to_string()];
    if local_lib.is_dir() {
        loadpath.push(local_lib.display().to_string());
    }
    if !inherited.is_empty() {
        loadpath.push(inherited);
    }
    // Keep the caller's GERBIL_PATH. Gerbil's home package profile owns
    // installed dependencies; the local build only extends module lookup.
    command.env("GERBIL_LOADPATH", loadpath.join(":"));
    let mut child = command
        .spawn()
        .expect("launch gerbil-ascent Scheme fixture");
    child
        .stdin
        .take()
        .expect("Scheme fixture stdin")
        .write_all(request.as_bytes())
        .expect("write Scheme fixture request");
    let output = child
        .wait_with_output()
        .expect("collect Scheme fixture output");
    assert!(
        output.status.success(),
        "Scheme fixture failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).expect("Scheme output is UTF-8")
}
