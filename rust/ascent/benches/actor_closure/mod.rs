//! Native sequential Ascent comparison for the Gerbil Actor closure workload.
mod bridge;
mod million;

use std::hint::black_box;
use std::time::Instant;

const GROUPS: i64 = 1_000;
const WIDTH: i64 = 5;
const SAMPLES: usize = 1_000;
const OUTPUT_ROWS: usize = 10_000;

type Row = (i64, i64);

ascent::ascent! {
    struct NativeAscent;
    relation edge(i64, i64);
    relation reach(i64, i64);
    reach(x, y) <-- edge(x, y);
    reach(x, z) <-- reach(x, y), edge(y, z);
}

#[derive(Clone, Copy)]
enum Change {
    FunctionalReplacement,
    BranchingReplacement,
    AppendRecompute,
    AppendRetained,
}

impl Change {
    fn label(self) -> &'static str {
        match self {
            Self::FunctionalReplacement => "functional-replacement",
            Self::BranchingReplacement => "branching-replacement",
            Self::AppendRecompute => "append-recompute",
            Self::AppendRetained => "append-retained",
        }
    }

    fn append(self) -> bool {
        matches!(self, Self::AppendRecompute | Self::AppendRetained)
    }
}

fn shortcut(group: i64, offset: i64) -> Row {
    let first = offset + group * WIDTH;
    (first, first + 2)
}

fn source(offset: i64, branching: bool) -> Vec<Row> {
    let mut rows: Vec<_> = (0..GROUPS)
        .flat_map(|group| {
            (0..WIDTH - 1).map(move |column| {
                let left = offset + group * WIDTH + column;
                (left, left + 1)
            })
        })
        .collect();
    if branching {
        rows.extend((0..GROUPS).map(|group| shortcut(group, offset)));
    }
    rows
}

fn verify(rows: &[Row], offset: i64) {
    assert_eq!(rows.len(), OUTPUT_ROWS);
    let cells = usize::try_from(GROUPS * WIDTH * WIDTH).unwrap();
    let mut seen = vec![0_u8; cells];
    for &(left, right) in rows {
        let left = left - offset;
        let right = right - offset;
        assert!(0 <= left && left < right && right < GROUPS * WIDTH);
        assert_eq!(left / WIDTH, right / WIDTH);
        let position = usize::try_from(left * WIDTH + right % WIDTH).unwrap();
        assert_eq!(seen[position], 0);
        seen[position] = 1;
    }
    black_box(seen);
}

fn measure(change: Change) {
    let prep = Instant::now();
    let branching = matches!(change, Change::BranchingReplacement);
    let mut first = source(0, branching);
    let initial_sources = first.len();
    let second = (!change.append()).then(|| source(GROUPS * WIDTH, branching));
    let mut oracle = NativeAscent::default();
    oracle.edge.clone_from(&first);
    oracle.run();
    verify(&oracle.reach, 0);
    println!("PREP\t{}\t{}", change.label(), prep.elapsed().as_nanos());

    let mut samples = Vec::with_capacity(SAMPLES);
    let window = Instant::now();
    for index in 0..SAMPLES {
        let offset = if second.is_some() && index.is_multiple_of(2) {
            GROUPS * WIDTH
        } else {
            0
        };
        let start = Instant::now();
        let expected_sources = match change {
            Change::FunctionalReplacement | Change::BranchingReplacement => {
                let cut = if offset == 0 {
                    &first
                } else {
                    second.as_ref().unwrap()
                };
                oracle = NativeAscent::default();
                oracle.edge.clone_from(cut);
                cut.len()
            }
            Change::AppendRecompute => {
                first.push(shortcut(i64::try_from(index).unwrap(), 0));
                oracle = NativeAscent::default();
                oracle.edge.clone_from(&first);
                initial_sources + index + 1
            }
            Change::AppendRetained => {
                oracle.edge.push(shortcut(i64::try_from(index).unwrap(), 0));
                initial_sources + index + 1
            }
        };
        let updated = Instant::now();
        oracle.run();
        let ready = Instant::now();
        // Give the caller a detached mutable result, while the evaluator
        // retains its own rows just as the Scheme Actor retains its cut.
        let output = oracle.reach.clone();
        let delivered = Instant::now();
        assert_eq!(oracle.edge.len(), expected_sources);
        verify(&output, offset);
        let verified = Instant::now();
        samples.push([
            updated.duration_since(start).as_nanos(),
            ready.duration_since(updated).as_nanos(),
            delivered.duration_since(ready).as_nanos(),
            verified.duration_since(delivered).as_nanos(),
            delivered.duration_since(start).as_nanos(),
            verified.duration_since(start).as_nanos(),
        ]);
    }
    let elapsed = window.elapsed().as_nanos();
    for sample in samples {
        println!(
            "SAMPLE\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            change.label(),
            sample[0],
            sample[1],
            sample[2],
            sample[3],
            sample[4],
            sample[5]
        );
    }
    println!("WINDOW\t{}\t{}\t{}", change.label(), SAMPLES, elapsed);
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("--bridge-bound") => return bridge::run(true),
        Some("--bridge-origin") => return bridge::run(false),
        Some("--million-recursive") => return million::run(true, false),
        Some("--million-projection") => return million::run(false, false),
        Some("--million-recursive-rayon") => return million::run(true, true),
        Some("--million-projection-rayon") => return million::run(false, true),
        _ => {}
    }
    println!(
        "COLUMNS\tshape\tupdate_ns\tsolve_ns\tdelivery_ns\toracle_ns\tdelivered_ns\tverified_ns"
    );
    if std::env::args().any(|arg| arg == "--retained") {
        measure(Change::AppendRetained);
        return;
    }
    for change in [
        Change::FunctionalReplacement,
        Change::BranchingReplacement,
        Change::AppendRecompute,
    ] {
        measure(change);
    }
}
