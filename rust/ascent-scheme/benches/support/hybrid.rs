//! Matched native Scheme frontend, VM and owned-data Rayon execution.
use crate::Runtime;
use gerbil_ascent::{Cancellation, Data, Engine, Limits, Row, Value};
use std::{collections::BTreeMap, fmt::Write, time::Instant};

/// Run the matched diagnostic from command-line arguments, validating all tuples.
///
/// # Panics
/// Panics on invalid arguments, incomplete execution or any result mismatch.
pub fn run() {
    execute(&arguments());
}

fn arguments() -> Vec<String> {
    let mut args = std::env::args()
        .skip(1)
        .filter(|arg| arg != "--bench")
        .collect::<Vec<_>>();
    if args.is_empty() {
        let workers = std::thread::available_parallelism().map_or(1, std::num::NonZero::get);
        args = ["1", "16", "16", "rayon", &workers.to_string(), "7"]
            .into_iter()
            .map(str::to_owned)
            .collect();
    }
    assert_eq!(args.len(), 6, "K G W vm|rayon threads samples");
    args
}

fn execute(args: &[String]) {
    let number = |i: usize| args[i].parse::<usize>().unwrap();
    let (k, g, w, threads, samples) = (number(0), number(1), number(2), number(4), number(5));
    assert!(k > 0 && g > 0 && w > 1 && threads > 0 && samples > 0);
    let mode = &args[3];
    assert!(mode == "vm" || mode == "rayon");
    assert!(mode != "vm" || threads == 1, "one owner thread per VM");
    let source = program_source(k);
    let startup = Instant::now();
    let runtime = Runtime::initialize().unwrap();
    let (rows, expected, packet_rows) = workload(g, w);
    let engine = Engine::new(threads).unwrap();
    let (queries, mut session, mut fields) = prepare(&runtime, &engine, &source, k, mode);
    eprintln!(
        "HYBRID frontend_vm=1 owner_threads=1 kernel_vm_entry={} rayon_threads={} startup_ns={}",
        mode == "vm",
        if mode == "rayon" { threads } else { 0 },
        startup.elapsed().as_nanos()
    );
    for sample in 0..=samples {
        let begin = Instant::now();
        let replaced;
        let solved;
        let exported;
        let mut actual;
        if let Some(session) = &mut session {
            session
                .replace_sources((0..k).map(|i| (format!("edge{i}"), rows.clone())).collect())
                .unwrap();
            replaced = Instant::now();
            let snapshot = session
                .run(&Limits::default(), &Cancellation::default())
                .unwrap();
            solved = Instant::now();
            actual = snapshot_rows(&snapshot.relations, &queries);
            exported = Instant::now();
        } else {
            let mut request = fields.clone();
            request.insert("operation".into(), Data::from("source-replace"));
            request.insert(
                "sources".into(),
                Data::List(
                    (0..k)
                        .map(|i| {
                            Data::object([
                                ("relation", Data::from(format!("edge{i}"))),
                                ("rows", packet_rows.clone()),
                            ])
                        })
                        .collect(),
                ),
            );
            let cancel = Cancellation::default();
            let control = crate::control::Control::new(&Limits::default(), &cancel).unwrap();
            request.insert("executionControl".into(), control.id());
            runtime.call(&Data::Map(request)).unwrap();
            replaced = Instant::now();
            let mut request = fields.clone();
            request.insert("operation".into(), Data::from("source-run"));
            request.insert(
                "queries".into(),
                Data::List(queries.iter().cloned().map(Data::from).collect()),
            );
            let control = crate::control::Control::new(&Limits::default(), &cancel).unwrap();
            request.insert("executionControl".into(), control.id());
            let result = runtime.call(&Data::Map(request)).unwrap();
            solved = Instant::now();
            assert_eq!(result.field("complete").unwrap(), &Data::Bool(true));
            actual = scheme_rows(&result, &queries);
            let mut release = fields.clone();
            release.insert("operation".into(), Data::from("owned-result"));
            release.insert("action".into(), Data::from("release"));
            release.insert(
                "result".into(),
                result.field("resultHandle").unwrap().clone(),
            );
            runtime.call(&Data::Map(release)).unwrap();
            exported = Instant::now();
        }
        verify_rows(&mut actual, &expected);
        if sample > 0 {
            println!(
                "{k}\t{g}\t{w}\t{mode}\t{threads}\t{}\t{}\t{}\t{}\t{}\t{}",
                sample - 1,
                replaced.duration_since(begin).as_nanos(),
                solved.duration_since(replaced).as_nanos(),
                exported.duration_since(solved).as_nanos(),
                exported.duration_since(begin).as_nanos(),
                k * expected.len()
            );
        }
    }
    if mode == "vm" {
        fields.insert("operation".into(), Data::from("close"));
        runtime.call(&Data::Map(fields)).unwrap();
    }
}

fn workload(g: usize, w: usize) -> (Vec<Row>, Vec<Row>, Data) {
    let rows: Vec<Row> = (0..g)
        .flat_map(|group| {
            (0..w - 1).map(move |i| {
                vec![
                    Value::from(i64::try_from(group * w + i).unwrap()),
                    Value::from(i64::try_from(group * w + i + 1).unwrap()),
                ]
                .into()
            })
        })
        .collect();
    let mut expected: Vec<Row> = (0..g)
        .flat_map(|group| {
            (0..w).flat_map(move |i| {
                (i + 1..w).map(move |j| {
                    vec![
                        Value::from(i64::try_from(group * w + i).unwrap()),
                        Value::from(i64::try_from(group * w + j).unwrap()),
                    ]
                    .into()
                })
            })
        })
        .collect();
    expected.sort();
    let packet_rows = Data::List(
        (0..g)
            .flat_map(|group| {
                (0..w - 1).map(move |i| {
                    Data::List(vec![
                        Data::from(group * w + i),
                        Data::from(group * w + i + 1),
                    ])
                })
            })
            .collect(),
    );
    (rows, expected, packet_rows)
}

fn prepare(
    runtime: &Runtime,
    engine: &Engine,
    source: &str,
    k: usize,
    mode: &str,
) -> (
    Vec<String>,
    Option<gerbil_ascent::Session>,
    BTreeMap<String, Data>,
) {
    let mut fields = BTreeMap::new();
    let session;
    let queries;
    if mode == "rayon" {
        let dag = runtime.load_dag(source, "make", vec![]).unwrap();
        queries = dag
            .queries
            .into_iter()
            .filter(|q| q.starts_with("reach"))
            .collect::<Vec<_>>();
        assert_eq!(queries.len(), k);
        session = Some(engine.open(dag.program).unwrap());
    } else {
        let opened = runtime
            .call(&Data::object([
                ("operation", Data::from("open-program")),
                ("source", Data::from(source)),
                ("constructor", Data::from("make")),
                ("arguments", Data::List(vec![])),
                ("trusted", Data::Bool(true)),
            ]))
            .unwrap();
        fields.insert("handle".into(), opened.field("handle").unwrap().clone());
        queries = (0..k).map(|i| format!("reach{i}")).collect();
        session = None;
    }
    (queries, session, fields)
}

fn program_source(k: usize) -> String {
    let mut source = "(define-program (make) (sources".to_string();
    for i in 0..k {
        write!(source, " edge{i}").unwrap();
    }
    source.push_str(") (outputs");
    for i in 0..k {
        write!(source, " reach{i}").unwrap();
    }
    source.push(')');
    for i in 0..k {
        write!(source, " (relation edge{i} ((a exact-integer?) (b exact-integer?))) (relation reach{i} ((a exact-integer?) (b exact-integer?))) ((reach{i} a b) <-- (edge{i} a b)) ((reach{i} a c) <-- (reach{i} a b) (edge{i} b c))").unwrap();
    }
    source.push(')');
    source
}

fn snapshot_rows(relations: &BTreeMap<String, Vec<Row>>, queries: &[String]) -> Vec<Vec<Row>> {
    queries
        .iter()
        .map(|query| relations[query].clone())
        .collect()
}
fn scheme_rows(result: &Data, queries: &[String]) -> Vec<Vec<Row>> {
    queries
        .iter()
        .map(|query| {
            result
                .field("relations")
                .unwrap()
                .field(query)
                .unwrap()
                .list()
                .unwrap()
                .iter()
                .map(scheme_row)
                .collect()
        })
        .collect()
}
fn scheme_row(row: &Data) -> Row {
    row.list()
        .unwrap()
        .iter()
        .map(|v| match v {
            Data::Integer(v) => Value::Integer(v.clone()),
            _ => panic!("integer row"),
        })
        .collect::<Vec<_>>()
        .into()
}
fn verify_rows(actual: &mut [Vec<Row>], expected: &[Row]) {
    for rows in actual {
        rows.sort();
        assert_eq!(rows, expected);
    }
}

/// Every controlled process call uses the shared admission state; no per-checkpoint RPC.
#[must_use]
pub fn kernel_checkpoint_transport() -> &'static str {
    "shared-local-control"
}
