// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Pinned macro admission behavior compared with Scheme diagnostics.

use super::common::scheme_output;
use std::{
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
};

const VALID: &str = r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x);
}
"#;

const INVALID: [(&str, &str, &str, &str); 24] = [
    (
        "source-field-type",
        "field-type",
        "mismatched types",
        r#"
use ascent::ascent;
ascent! {
    relation seed(u32);
}
fn bad_source() {
    let _program = AscentProgram {
        seed: vec![("bad",)],
        ..AscentProgram::default()
    };
}
"#,
    ),
    (
        "derived-field-type",
        "field-type",
        "mismatched types",
        r#"
use ascent::ascent;
ascent! {
    relation seed(u32);
    relation out(u32);
    out("bad") <-- seed(_);
}
"#,
    ),
    (
        "lattice-projection-feedback",
        "lattice-projection-cycle",
        "",
        r#"
use ascent::{ascent, lattice::Dual};
ascent! {
    relation out(u32);
    lattice best(u32, Dual<u32>);
    best(x, Dual(*x)) <-- out(x);
    out(x) <-- best(x, _);
}
"#,
    ),
    (
        "negative-self",
        "negation-cycle",
        "use of aggregated relation `looped` cannot be stratified",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation looped(u32);
    looped(x) <-- node(x), !looped(x);
}
"#,
    ),
    (
        "mutual-negation",
        "negation-cycle",
        "cannot be stratified",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation left(u32);
    relation right(u32);
    left(x) <-- node(x), !right(x);
    right(x) <-- node(x), !left(x);
}
"#,
    ),
    (
        "negative-feedback",
        "negation-cycle",
        "use of aggregated relation `right` cannot be stratified",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation left(u32);
    relation right(u32);
    left(x) <-- node(x), !right(x);
    right(x) <-- left(x);
}
"#,
    ),
    (
        "aggregate-self",
        "aggregate-cycle",
        "use of aggregated relation `number` cannot be stratified",
        r#"
use ascent::ascent;
ascent! {
    relation number(u32);
    number(total) <-- agg total = count() in number(_);
}
"#,
    ),
    (
        "negative-with-unrelated-aggregate",
        "negation-cycle",
        "use of aggregated relation `left` cannot be stratified",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation left(u32);
    relation total(usize);
    left(x) <-- node(x), !left(x);
    total(n) <-- agg n = count() in node(_);
}
"#,
    ),
    (
        "unsafe-negation",
        "unsafe-negation",
        "cannot find value `y` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation block(u32);
    relation out(u32);
    out(x) <-- node(x), !block(y);
}
"#,
    ),
    (
        "unbound-head",
        "unbound-head",
        "cannot find value `y` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(y) <-- node(x);
}
"#,
    ),
    (
        "unknown-relation",
        "unknown-relation",
        "relation `missing` is not defined",
        r#"
use ascent::ascent;
ascent! {
    relation out(u32);
    out(x) <-- missing(x);
}
"#,
    ),
    (
        "atom-arity",
        "atom-arity",
        "wrong arity for relation `node` (expected 1, found 2)",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x, x);
}
"#,
    ),
    (
        "duplicate-relation",
        "duplicate-relation",
        "",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation node(u32);
}
"#,
    ),
    (
        "unbound-guard",
        "unbound-guard",
        "cannot find value `y` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x), if y > 0;
}
"#,
    ),
    (
        "head-arity",
        "atom-arity",
        "wrong arity for relation `out` (expected 1, found 2)",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x, x) <-- node(x);
}
"#,
    ),
    (
        "unbound-let-input",
        "unbound-clause",
        "cannot find value `missing` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(y) <-- node(x), let y = missing;
}
"#,
    ),
    (
        "unbound-for-input",
        "unbound-clause",
        "cannot find value `missing` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(y) <-- node(x), for y in missing;
}
"#,
    ),
    (
        "unknown-aggregate-relation",
        "unknown-relation",
        "relation `missing` is not defined",
        r#"
use ascent::ascent;
ascent! {
    relation out(usize);
    out(n) <-- agg n = count() in missing(_);
}
"#,
    ),
    (
        "negation-before-binding",
        "unsafe-negation",
        "cannot find value `x` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation block(u32);
    relation out(u32);
    out(x) <-- !block(x), node(x);
}
"#,
    ),
    (
        "unknown-head-relation",
        "unknown-relation",
        "relation `missing` is not defined",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    missing(x) <-- node(x);
}
"#,
    ),
    (
        "negation-arity",
        "atom-arity",
        "wrong arity for relation `block` (expected 1, found 2)",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation block(u32);
    relation out(u32);
    out(x) <-- node(x), !block(x, x);
}
"#,
    ),
    (
        "aggregate-arity",
        "atom-arity",
        "wrong arity for relation `node` (expected 1, found 2)",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(usize);
    out(n) <-- agg n = count() in node(_, _);
}
"#,
    ),
    (
        "unbound-head-expression",
        "unbound-head",
        "cannot find value `missing` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(missing + 1) <-- node(x);
}
"#,
    ),
    (
        "unbound-atom-expression",
        "unbound-clause",
        "cannot find value `missing` in this scope",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x), node(missing + 1);
}
"#,
    ),
];

fn compile(source: &str, library: &Path, dependencies: &Path) -> Output {
    let output_path = env::temp_dir().join(format!(
        "ascent-invalid-program-{}.rmeta",
        std::process::id()
    ));
    let mut child = Command::new(env::var_os("RUSTC").unwrap_or_else(|| "rustc".into()))
        .args(["--edition=2024", "--crate-type=lib", "--emit=metadata"])
        .args(["--crate-name", "ascent_invalid_program_probe"])
        .arg("--extern")
        .arg(format!("ascent={}", library.display()))
        .arg("-L")
        .arg(format!("dependency={}", dependencies.display()))
        .arg("-o")
        .arg(&output_path)
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("launch Rust compiler for Ascent macro probe");
    child
        .stdin
        .take()
        .expect("probe stdin")
        .write_all(source.as_bytes())
        .expect("write Ascent macro probe");
    let output = child.wait_with_output().expect("collect Rust diagnostic");
    let _ = fs::remove_file(output_path);
    output
}

fn pinned_ascent_library(dependencies: &Path) -> PathBuf {
    let mut candidates: Vec<_> = fs::read_dir(dependencies)
        .expect("read Cargo dependency artifacts")
        .filter_map(Result::ok)
        .map(|entry| entry.path())
        .filter(|path| {
            path.file_name()
                .and_then(|name| name.to_str())
                .is_some_and(|name| name.starts_with("libascent-") && name.ends_with(".rlib"))
        })
        .collect();
    candidates.sort();
    candidates
        .into_iter()
        .find(|library| compile(VALID, library, dependencies).status.success())
        .expect("a valid pinned Ascent macro must compile before rejection probes")
}

#[test]
fn invalid_program_admission_matches_or_records_rust_differences() {
    let dependencies = env::current_exe()
        .expect("test executable path")
        .parent()
        .expect("Cargo dependency directory")
        .to_path_buf();
    let library = pinned_ascent_library(&dependencies);
    let request = format!(
        "({})\n",
        INVALID
            .iter()
            .map(|(name, _, _, _)| *name)
            .collect::<Vec<_>>()
            .join(" ")
    );
    let output = scheme_output("invalid-program-rows", &request);
    let mut scheme: Vec<_> = output.lines().collect();
    assert_eq!(scheme.pop(), Some("END"));
    assert_eq!(scheme.len(), INVALID.len());

    for (index, (name, category, diagnostic, source)) in INVALID.iter().enumerate() {
        let result = compile(source, &library, &dependencies);
        let stderr = String::from_utf8(result.stderr).expect("Rust diagnostic is UTF-8");
        if matches!(*name, "duplicate-relation" | "lattice-projection-feedback") {
            // Ascent 0.8.0 accepts duplicate declarations and feedback from
            // a lattice value through an ordinary relation. Scheme rejects
            // both before evaluation: the former has ambiguous public schema;
            // the latter needs a strict stratum to preserve joined values.
            assert!(result.status.success(), "{name}: {stderr}");
        } else {
            assert!(!result.status.success(), "{name} unexpectedly compiled");
            assert!(stderr.contains(diagnostic), "{name}: {stderr}");
        }
        assert_eq!(scheme[index], format!("{name}\t{category}"));
    }
}
