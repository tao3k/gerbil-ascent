// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

//! Pinned macro admission behavior compared with Scheme diagnostics.

use super::common::scheme_output;
use std::{
    env, fs,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};

const VALID: &str = r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x);
}
"#;

const INVALID: [(&str, &str, &str, &str); 31] = [
    (
        "source-row-arity",
        "source-row-arity",
        "mismatched types",
        r#"
use ascent::ascent;
ascent! {
    relation seed(u32, u32);
}
fn bad_source() {
    let _program = AscentProgram {
        seed: vec![(1,)],
        ..AscentProgram::default()
    };
}
"#,
    ),
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
        "unknown-negated-relation",
        "unknown-relation",
        "relation `missing` is not defined",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x), !missing(x);
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
        "unbound-aggregate-input",
        "unbound-clause",
        // Pinned Ascent panics while expanding this malformed aggregate;
        // Scheme rejects the missing dependency during admission.
        "proc macro panicked",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(total) <-- agg total = sum(missing) in node(x);
}
"#,
    ),
    (
        "aggregate-two-relation-cycle",
        "aggregate-cycle",
        "cannot be stratified",
        r#"
use ascent::ascent;
ascent! {
    relation left(usize);
    relation right(usize);
    left(total) <-- agg total = count() in right(_);
    right(value) <-- left(value);
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
    (
        "let-shadows-atom",
        "variable-shadowing",
        "shadows another variable with the same name",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x), let x = *x + 1;
}
"#,
    ),
    (
        "for-shadows-atom",
        "variable-shadowing",
        "shadows another variable with the same name",
        r#"
use ascent::ascent;
ascent! {
    relation node(u32);
    relation out(u32);
    out(x) <-- node(x), for x in [*x + 1];
}
"#,
    ),
    (
        "aggregate-shadows-atom",
        "variable-shadowing",
        "shadows another variable with the same name",
        r#"
use ascent::ascent;
ascent! {
    relation node(usize);
    relation out(usize);
    out(x) <-- node(x), agg x = ascent::aggregators::count() in node(_);
}
"#,
    ),
];

fn compile(source: &str, project: &Path, locked: bool) -> Output {
    fs::write(project.join("tests/probe.rs"), source).expect("write Ascent macro probe");
    // Cargo owns the dependency layout and proc-macro search paths.
    let mut command = Command::new(env::var_os("CARGO").unwrap_or_else(|| "cargo".into()));
    command
        .args(["check", "--offline", "--test", "probe"])
        .arg("--manifest-path")
        .arg(project.join("Cargo.toml"))
        .arg("--target-dir")
        .arg(project.join("target"))
        .env("CARGO_BUILD_BUILD_DIR", project.join("target"))
        .current_dir(project)
        .stdin(Stdio::null());
    if locked {
        command.arg("--locked");
    }
    command.output().expect("collect Cargo macro diagnostic")
}

fn macro_probe_project() -> PathBuf {
    let probes = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../.cache/ascent/macro-probes");
    fs::create_dir_all(&probes).expect("create macro probe cache");
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("macro probe clock")
        .as_nanos();
    let project = probes.join(format!("{}-{nonce}", std::process::id()));
    fs::create_dir(&project).expect("create private macro probe project");
    fs::create_dir(project.join("tests")).expect("create macro probe target");
    fs::write(
        project.join("Cargo.toml"),
        r#"[package]
name = "ascent-invalid-program-probe"
version = "0.0.0"
edition = "2024"

[dev-dependencies]
ascent = "=0.8.0"

[workspace]
"#,
    )
    .expect("declare pinned macro probe dependency");
    // Seed the complete pinned dependency graph. Cargo adapts its root package
    // once for VALID, then every rejection probe uses that locked graph.
    fs::write(project.join("Cargo.lock"), include_str!("../../Cargo.lock"))
        .expect("seed macro probe lockfile");
    project
}

#[test]
fn pinned_macro_admission_matches_reference_diagnostics() {
    let project = macro_probe_project();
    let valid = compile(VALID, &project, false);
    assert!(
        valid.status.success(),
        "a valid pinned Ascent macro must compile before rejection probes: {}\n{}",
        valid.status,
        String::from_utf8_lossy(&valid.stderr)
    );
    for (name, _, diagnostic, source) in INVALID {
        let result = compile(source, &project, true);
        let stderr = String::from_utf8(result.stderr).expect("Rust diagnostic is UTF-8");
        if matches!(name, "duplicate-relation" | "lattice-projection-feedback") {
            // Ascent 0.8.0 accepts duplicate declarations and feedback from
            // a lattice value through an ordinary relation. Scheme rejects
            // both before evaluation: the former has ambiguous public schema;
            // the latter needs a strict stratum to preserve joined values.
            assert!(result.status.success(), "{name}: {stderr}");
        } else {
            assert!(!result.status.success(), "{name} unexpectedly compiled");
            assert!(stderr.contains(diagnostic), "{name}: {stderr}");
        }
    }
}

#[test]
fn invalid_program_admission_matches_or_records_rust_differences() {
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
    for (row, (name, category, _, _)) in scheme.iter().zip(INVALID) {
        assert_eq!(*row, format!("{name}\t{category}"));
    }
}
