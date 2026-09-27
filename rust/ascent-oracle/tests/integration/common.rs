// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Shared Scheme process adapter for differential tests.

use std::{
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};

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
    let gerbil_path =
        std::env::var_os("GERBIL_PATH").unwrap_or_else(|| root.join(".gerbil").into());
    let inherited = std::env::var("GERBIL_LOADPATH").unwrap_or_default();
    command.env("GERBIL_PATH", gerbil_path);
    command.env("GERBIL_LOADPATH", format!("{}:{inherited}", root.display()));
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
