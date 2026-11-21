//! Upstream Ascent on the two native Gerbil million-row gates.
use std::hint::black_box;
use std::time::{Duration, Instant};

type Row = (usize, usize);
const REQUESTS: usize = 1_000;

macro_rules! programs {
    ($engine:ident, $recursive:ident, $projection:ident) => {
        ascent::$engine! {
            struct $recursive;
            relation edge(usize, usize);
            relation reach(usize, usize);
            reach(x, y) <-- edge(x, y);
            reach(x, z) <-- reach(x, y), edge(y, z);
        }

        ascent::$engine! {
            struct $projection;
            relation edge(usize, usize);
            relation reach(usize, usize);
            reach(x, y) <-- edge(x, y);
        }
    };
}

programs!(ascent, Recursive, Projection);
programs!(ascent_par, ParallelRecursive, ParallelProjection);

struct Workload {
    groups: usize,
    width: usize,
    recursive: bool,
}

impl Workload {
    fn cut(&self, offset: usize) -> Vec<Row> {
        (0..self.groups)
            .flat_map(|group| {
                (0..self.width - 1).map(move |column| {
                    let left = offset + group * self.width + column;
                    (left, left + 1)
                })
            })
            .collect()
    }

    fn output_size(&self) -> usize {
        let inputs = self.groups * (self.width - 1);
        if self.recursive {
            inputs * self.width / 2
        } else {
            inputs
        }
    }

    fn verify(&self, rows: &[Row], offset: usize) {
        assert_eq!(rows.len(), self.output_size());
        let mut seen = vec![0u8; self.groups * self.width * self.width];
        for &(left, right) in rows {
            let left = left.checked_sub(offset).expect("left in current cut");
            let right = right.checked_sub(offset).expect("right in current cut");
            assert!(left < right && right < self.groups * self.width);
            assert_eq!(left / self.width, right / self.width);
            assert!(self.recursive || right == left + 1);
            let cell = &mut seen[left * self.width + right % self.width];
            assert_eq!(*cell, 0);
            *cell = 1;
        }
        black_box(seen);
    }
}

fn report(phase: &str, mut values: Vec<Duration>) {
    values.sort_unstable();
    let n = values.len();
    let to_ms = |duration: Duration| duration.as_secs_f64() * 1_000.0;
    println!(
        "MILLION {phase} {n} {:.6} {:.6} {:.6} {:.6}",
        to_ms(values.iter().sum()),
        to_ms(values[(n - 1) / 2]),
        to_ms(values[(95 * n).div_ceil(100) - 1]),
        to_ms(values[n - 1]),
    );
}

fn measure<Program: Default>(
    workload: Workload,
    set_source: impl Fn(&mut Program, &[Row]),
    solve: impl Fn(&mut Program),
    export: impl Fn(&Program) -> Vec<Row>,
) {
    let span = workload.groups * workload.width;
    let cuts = [workload.cut(0), workload.cut(span)];
    let mut phases = [(); 6].map(|()| Vec::with_capacity(REQUESTS));
    println!("INPUT {} OUTPUT {}", cuts[0].len(), workload.output_size());

    let start = Instant::now();
    let request = |cut: usize| {
        let start = Instant::now();
        let mut program = Program::default();
        set_source(&mut program, &cuts[cut]);
        let replaced = Instant::now();
        solve(&mut program);
        let published = Instant::now();
        let rows = export(&program);
        let delivered = Instant::now();
        workload.verify(black_box(&rows), cut * span);
        let verified = Instant::now();
        drop(rows);
        drop(program);
        let released = Instant::now();
        [
            replaced - start,
            published - replaced,
            delivered - published,
            verified - delivered,
            released - verified,
            released - start,
        ]
    };

    let _cold = request(0);
    for i in 0..REQUESTS {
        let durations = request(1 - i % 2);
        for (phase, duration) in phases.iter_mut().zip(durations) {
            phase.push(duration);
        }
        if (i + 1) % 100 == 0 {
            println!("VERIFIED_REQUESTS {}", i + 1);
        }
    }
    println!("MILLION_COLUMNS phase requests total_ms p50_ms p95_ms max_ms");
    for (phase, values) in ["replace", "solve", "export", "oracle", "release", "total"]
        .into_iter()
        .zip(phases)
    {
        report(phase, values);
    }
    println!(
        "MILLION_WALL_MS {:.6}",
        start.elapsed().as_secs_f64() * 1_000.0
    );
    println!("NATIVE_UPSTREAM_MILLION_OK");
}

pub(super) fn run(recursive: bool, parallel: bool) {
    let (groups, width) = if recursive {
        (128, 128)
    } else {
        (1_000_000, 2)
    };
    let workload = Workload {
        groups,
        width,
        recursive,
    };
    if parallel {
        println!("RAYON_THREADS {}", ascent::rayon::current_num_threads());
    }
    match (recursive, parallel) {
        (true, false) => measure::<Recursive>(
            workload,
            |program, rows| program.edge.extend_from_slice(rows),
            Recursive::run,
            |program| program.reach.clone(),
        ),
        (false, false) => measure::<Projection>(
            workload,
            |program, rows| program.edge.extend_from_slice(rows),
            Projection::run,
            |program| program.reach.clone(),
        ),
        (true, true) => measure::<ParallelRecursive>(
            workload,
            |program, rows| program.edge.extend(rows.iter().copied()),
            ParallelRecursive::run,
            |program| program.reach.iter().copied().collect(),
        ),
        (false, true) => measure::<ParallelProjection>(
            workload,
            |program, rows| program.edge.extend(rows.iter().copied()),
            ParallelProjection::run,
            |program| program.reach.iter().copied().collect(),
        ),
    }
}
