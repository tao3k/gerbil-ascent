use gerbil_ascent::{
    Atom, Cancellation, Clause, Engine, Limits, Program, Relation, Rule, Term, Type, Value,
};
use std::{
    collections::BTreeSet,
    io::Write,
    path::PathBuf,
    process::{Command, Stdio},
};

#[test]
fn current_scheme_evaluator_and_rayon_agree_on_cyclic_and_acyclic_inputs() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..");
    let cases = [
        vec![],
        vec![[1, 2]],
        vec![[1, 2], [2, 3], [3, 1]],
        vec![[1, 2], [1, 3], [2, 4], [3, 4]],
        vec![[i64::MIN, 0], [0, i64::MAX]],
        vec![[0, 0], [0, 0], [1, 1]],
    ];
    let mut child = Command::new("gxi")
        .arg(root.join("rust/ascent/tests/fixtures/closure.ss"))
        .env("GERBIL_PATH", root.join(".gerbil"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .expect("Scheme oracle");
    let mut input = child.stdin.take().unwrap();
    for edges in &cases {
        write!(input, "(").unwrap();
        for [a, b] in edges {
            write!(input, "({a} {b})").unwrap();
        }
        writeln!(input, ")").unwrap();
    }
    drop(input);
    let output = child.wait_with_output().unwrap();
    assert!(output.status.success());
    let output = String::from_utf8(output.stdout).unwrap();
    let observed: Vec<BTreeSet<(i64, i64)>> = output
        .split("--\n")
        .take(cases.len())
        .map(|block| {
            block
                .lines()
                .map(|line| {
                    let (a, b) = line.split_once('\t').unwrap();
                    (a.parse().unwrap(), b.parse().unwrap())
                })
                .collect()
        })
        .collect();
    assert_eq!(observed.len(), cases.len());
    let atom = |name: &str, ids: &[u32]| {
        Atom::new(name, ids.iter().copied().map(Term::Variable).collect())
    };
    let program = Program {
        relation_limit: None,
        fact_limits: gerbil_ascent::FactLimits::default(),
        relations: vec![
            Relation::new("edge", vec![Type::Integer; 2], true),
            Relation::new("reach", vec![Type::Integer; 2], false),
        ],
        rules: vec![
            Rule {
                head: atom("reach", &[0, 1]),
                body: vec![Clause::positive(atom("edge", &[0, 1]))],
            },
            Rule {
                head: atom("reach", &[0, 2]),
                body: vec![
                    Clause::positive(atom("reach", &[0, 1])),
                    Clause::positive(atom("edge", &[1, 2])),
                ],
            },
        ],
    };
    for &workers in if cfg!(feature = "rayon") {
        &[1, 4][..]
    } else {
        &[1][..]
    } {
        let engine = Engine::new(workers).unwrap();
        for (edges, expected) in cases.iter().zip(&observed) {
            let mut session = engine.open(program.clone()).unwrap();
            session
                .replace(
                    "edge",
                    edges
                        .iter()
                        .map(|[a, b]| vec![Value::from(*a), Value::from(*b)].into())
                        .collect(),
                )
                .unwrap();
            let result = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            let pairs: BTreeSet<_> = result.relations["reach"]
                .iter()
                .map(|row| match (&row[0], &row[1]) {
                    (Value::Integer(a), Value::Integer(b)) => {
                        (i64::try_from(a).unwrap(), i64::try_from(b).unwrap())
                    }
                    _ => panic!("integer relation"),
                })
                .collect();
            assert_eq!(&pairs, expected);
        }
    }
}
