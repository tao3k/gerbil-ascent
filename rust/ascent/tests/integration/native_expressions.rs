use gerbil_ascent::{Cancellation, Engine, Limits, Program, Row, Value};
use std::{
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};
fn source(head: &str, body: &str) -> String {
    format!(
        "(ascent (relation input ((x integer?))) (relation output ((x integer?))) ((output {head}) <-- {body}))"
    )
}
#[test]
fn original_scheme_guards_bindings_and_aggregates_match_the_rust_backend() {
    let huge = "340282366920938463463374607431768211456";
    let input = vec!["-1", "0", "2", "5", huge];
    let mut cases = vec![
        (
            source("X", "(input X) (if (X) (and (>= X 0) (<= (+ X 1) 3)))"),
            input.clone(),
        ),
        (
            source("X", "(input X) (if (X) (or #t (even? \"invalid\")))"),
            input.clone(),
        ),
        (source("Y", "(input X) (let Y (X) (+ X 1))"), input.clone()),
        (
            source(
                "Y",
                "(input X) (bind Y (X) (lambda (renamed) (* renamed renamed)))",
            ),
            input.clone(),
        ),
        (
            source(
                "X",
                "(input X) (guard (X) (lambda (renamed) (even? renamed)))",
            ),
            input.clone(),
        ),
    ];
    cases.push(("(ascent (relation fixed ((x integer?)) '((1) (1) (2))) (relation input ((x integer?))) (relation output ((x integer?))) ((output X) <-- (fixed X)) (fact (output 7)))".into(), vec![]));
    for (operator, inputs) in [("sum", "V"), ("count", "")] {
        cases.push((format!("(ascent (relation fixed ((k integer?) (v integer?)) '((1 2) (2 2))) (relation input ((x integer?))) (relation output ((x integer?))) ((output T) <-- (aggregate T gerbil-ascent-{operator} ({inputs}) (fixed K V))))"),vec![]));
    }
    for operator in ["count", "sum", "min", "max"] {
        let inputs = if operator == "count" { "" } else { "X" };
        let text = source(
            "T",
            &format!("(aggregate T gerbil-ascent-{operator} ({inputs}) (input X))"),
        );
        cases.push((text.clone(), input.clone()));
        cases.push((text, vec![]));
    }
    let mut child = oracle_command().spawn().expect("native Scheme oracle");
    let mut stdin = child.stdin.take().unwrap();
    for (source, input) in &cases {
        let escaped = source.replace('\\', "\\\\").replace('"', "\\\"");
        write!(stdin, "(\"{escaped}\" (").unwrap();
        for number in input {
            write!(stdin, "({number})").unwrap();
        }
        writeln!(stdin, "))").unwrap();
    }
    drop(stdin);
    let output = child.wait_with_output().unwrap();
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stdout)
    );
    let text = String::from_utf8(output.stdout).unwrap();
    let observed: Vec<Vec<Row>> = text
        .split("--\n")
        .take(cases.len())
        .map(|block| {
            let mut rows: Vec<Row> = block
                .lines()
                .map(|line| vec![Value::from(line.parse::<num_bigint::BigInt>().unwrap())].into())
                .collect();
            rows.sort();
            rows
        })
        .collect();
    assert_eq!(observed.len(), cases.len());
    for &workers in if cfg!(feature = "rayon") {
        &[1, 4, 8, 12][..]
    } else {
        &[1][..]
    } {
        let engine = Engine::new(workers).unwrap();
        for ((source, input), expected) in cases.iter().zip(&observed) {
            let mut session = engine
                .open(Program::read_sources(&[source]).unwrap())
                .unwrap();
            session
                .replace(
                    "input",
                    input
                        .iter()
                        .map(|n| vec![Value::from(n.parse::<num_bigint::BigInt>().unwrap())].into())
                        .collect(),
                )
                .unwrap();
            let snapshot = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            assert_eq!(
                &snapshot.relations["output"], expected,
                "{source}; workers={workers}"
            );
        }
    }
}

fn oracle_command() -> Command {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let mut command = Command::new("gxi");
    command
        .arg(root.join("rust/ascent/tests/fixtures/native-expressions.ss"))
        .env("GERBIL_PATH", root.join(".gerbil"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit());
    command
}
