//! Upstream Rust Ascent for the same serial two-rule closure and bridge edits.
use std::hint::black_box;
use std::mem;
use std::time::{Duration, Instant};

const GROUPS: i64 = 26;
const WIDTH: i64 = 64;
const VERTICES: i64 = GROUPS * WIDTH;
const BRIDGE: i64 = (GROUPS / 2) * WIDTH - 1;
const ORIGIN: i64 = 64;
const HIT: (i64, i64) = (ORIGIN, VERTICES - 1);
const MISS: (i64, i64) = (ORIGIN, 0);
const HOT_REQUESTS: usize = 1000;
const EDITS: usize = 32;

type Row = (i64, i64);

ascent::ascent! {
    struct NativeClosure;
    relation edge(i64, i64);
    relation reach(i64, i64);
    reach(x, y) <-- edge(x, y);
    reach(x, z) <-- reach(x, y), edge(y, z);
}

fn input(removed: bool) -> Vec<Row> {
    let mut edges = Vec::new();
    for left in 0..VERTICES {
        let group = left / WIDTH;
        for right in group * WIDTH..(group + 1) * WIDTH {
            if left != right {
                edges.push((left, right));
            }
        }
        if (left + 1) % WIDTH == 0 && left + 1 < VERTICES && !(removed && left == BRIDGE) {
            edges.push((left, left + 1));
        }
    }
    edges
}

fn verify(rows: &[Row], removed: bool) {
    let mut observed = rows.iter().copied();
    for left in 0..VERTICES {
        let group = left / WIDTH;
        let limit = if removed && left <= BRIDGE {
            BRIDGE + 1
        } else {
            VERTICES
        };
        for right in group * WIDTH..limit {
            assert_eq!(observed.next(), Some((left, right)));
        }
    }
    assert_eq!(observed.next(), None);
}

struct Publication {
    ordered: Vec<Row>,
    replace: Duration,
    solve: Duration,
    sorted: Duration,
    publish: Duration,
}

fn publish(input: &[Row]) -> Publication {
    let begin = Instant::now();
    let mut solver = NativeClosure::default();
    solver.edge.extend_from_slice(input);
    let replaced = Instant::now();
    solver.run();
    let solved = Instant::now();
    let mut ordered = mem::take(&mut solver.reach);
    ordered.sort_unstable();
    let ready = Instant::now();
    Publication {
        ordered,
        replace: replaced - begin,
        solve: solved - replaced,
        sorted: ready - solved,
        publish: ready - replaced,
    }
}

fn double_bound(rows: &[Row], key: Row, expected: bool) {
    let row = rows.binary_search(&black_box(key)).ok().map(|i| rows[i]);
    assert_eq!(black_box(row), expected.then_some(key));
}

fn one_origin(rows: &[Row], removed: bool) {
    let origin = black_box(ORIGIN);
    let lower = rows.partition_point(|&(left, _)| left < origin);
    let upper = rows.partition_point(|&(left, _)| left <= origin);
    let limit = if removed { BRIDGE + 1 } else { VERTICES };
    let mut next = origin;
    for &(left, right) in &rows[lower..upper] {
        assert_eq!((left, right), (origin, next));
        next += 1;
    }
    assert_eq!(black_box(next), limit);
}

fn time(operation: impl FnOnce()) -> Duration {
    let start = Instant::now();
    operation();
    start.elapsed()
}

fn report(name: &str, mut values: Vec<Duration>) {
    values.sort_unstable();
    let count = values.len();
    let p95 = (95 * count + 99) / 100 - 1;
    println!(
        "TIMING {name} {count} {:.9} {:.9}",
        values[p95].as_secs_f64() * 1000.0,
        values[count - 1].as_secs_f64() * 1000.0,
    );
}

struct Samples {
    replace: Vec<Duration>,
    solve: Vec<Duration>,
    sorted: Vec<Duration>,
    publish: Vec<Duration>,
    bound: Vec<Duration>,
    origin: Vec<Duration>,
}

impl Samples {
    fn new() -> Self {
        Self {
            replace: Vec::with_capacity(EDITS),
            solve: Vec::with_capacity(EDITS),
            sorted: Vec::with_capacity(EDITS),
            publish: Vec::with_capacity(EDITS),
            bound: Vec::with_capacity(EDITS),
            origin: Vec::with_capacity(EDITS),
        }
    }

    fn add(&mut self, result: Publication, removed: bool, bound_first: bool) {
        let bound = || double_bound(&result.ordered, HIT, !removed);
        let origin = || one_origin(&result.ordered, removed);
        if bound_first {
            self.bound.push(time(bound));
        } else {
            self.origin.push(time(origin));
        }
        verify(&result.ordered, removed);
        self.replace.push(result.replace);
        self.solve.push(result.solve);
        self.sorted.push(result.sorted);
        self.publish.push(result.publish);
    }

    fn report(self, edit: &str, bound_first: bool) {
        report(&format!("{edit}-replace"), self.replace);
        report(&format!("{edit}-ascent-solve"), self.solve);
        report(&format!("{edit}-read-index-sort"), self.sorted);
        report(&format!("{edit}-publish"), self.publish);
        if bound_first {
            report(&format!("{edit}-first-bound"), self.bound);
        } else {
            report(&format!("{edit}-first-origin"), self.origin);
        }
    }
}

pub(super) fn run(bound_first: bool) {
    let intact = input(false);
    let split = input(true);
    assert_eq!(intact.len(), 104_857);
    assert_eq!(split.len(), 104_856);
    let initial = publish(&intact);
    assert_eq!(initial.ordered.len(), 1_437_696);
    report("first-publish", vec![initial.publish]);
    println!("FIRST_SOLVE_NANOS {}", initial.solve.as_nanos());
    if bound_first {
        for (label, key, expected) in [("same-hit", HIT, true), ("same-miss", MISS, false)] {
            report(
                label,
                (0..HOT_REQUESTS)
                    .map(|_| time(|| double_bound(&initial.ordered, key, expected)))
                    .collect(),
            );
        }
    }
    verify(&initial.ordered, false);
    let mut removal = Samples::new();
    let mut restoration = Samples::new();
    for completed in 1..=EDITS {
        removal.add(publish(&split), true, bound_first);
        restoration.add(publish(&intact), false, bound_first);
        println!("VERIFIED_EDIT_PAIR {completed}");
    }
    removal.report("removed", bound_first);
    restoration.report("restored", bound_first);
    if bound_first {
        report(
            "old-view-hit",
            (0..HOT_REQUESTS)
                .map(|_| time(|| double_bound(&initial.ordered, HIT, true)))
                .collect(),
        );
    }
    println!("NATIVE_UPSTREAM_OK");
}
