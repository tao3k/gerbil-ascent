//! Saturated, fixed-work production API throughput; all native rows checked in Rust.
use ascent_scheme::{Engine, ProcessPool, RuleSession, WorkerProgram};
use gerbil_ascent::{
    Cancellation, Data, FactLimits, Limits, ObjectInput, Row, SourceSession, Value,
};
use sha2::{Digest, Sha256};
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Barrier,
        atomic::{AtomicUsize, Ordering},
    },
    time::Instant,
};
const SOURCE: &str = "(define-program (make) (sources edge) (outputs reach) (relation edge ((a exact-integer?) (b exact-integer?))) (relation reach ((a exact-integer?) (b exact-integer?))) ((reach a b) <-- (edge a b)) ((reach a c) <-- (reach a b) (edge b c)))";
enum Session {
    Scheme(RuleSession),
    Rayon(Box<SourceSession>),
}
struct Observation {
    task: usize,
    latency_ns: u128,
    completion_ns: u128,
    replace_ns: u128,
    run_export_ns: u128,
    digest: String,
}
fn integer(value: &Value) -> usize {
    match value {
        Value::Integer(v) => usize::try_from(v).unwrap(),
        _ => panic!("integer cell required"),
    }
}
fn expected(groups: usize, width: usize, offset: usize) -> Vec<(usize, usize)> {
    (0..groups)
        .flat_map(|g| {
            (0..width).flat_map(move |a| {
                ((a + 1)..width).map(move |b| (offset + g * width + a, offset + g * width + b))
            })
        })
        .collect()
}
fn edges(groups: usize, width: usize, offset: usize) -> Vec<(usize, usize)> {
    (0..groups)
        .flat_map(|g| {
            (0..width - 1).map(move |a| (offset + g * width + a, offset + g * width + a + 1))
        })
        .collect()
}
fn execute(session: &mut Session, task: usize, groups: usize, width: usize) -> Observation {
    // Every request changes source values. Reused complete results cannot fake throughput.
    let start = Instant::now();
    let offset = (task + 1) * groups * width;
    let input = edges(groups, width, offset);
    let limits = Limits::default();
    let cancel = Cancellation::default();
    let replaced;
    let mut answer: Vec<(usize, usize)>;
    match session {
        Session::Scheme(session) => {
            session
                .replace(
                    BTreeMap::from([(
                        "edge".into(),
                        input
                            .iter()
                            .map(|(a, b)| {
                                vec![
                                    ObjectInput::Integer((*a).into()),
                                    ObjectInput::Integer((*b).into()),
                                ]
                            })
                            .collect(),
                    )]),
                    &limits,
                    &cancel,
                )
                .unwrap();
            replaced = start.elapsed().as_nanos();
            let result = session.run(None, &limits, &cancel).unwrap();
            assert_eq!(result.field("complete").unwrap(), &Data::Bool(true));
            answer = result
                .field("relations")
                .unwrap()
                .field("reach")
                .unwrap()
                .list()
                .unwrap()
                .iter()
                .map(|row| {
                    let row = row.list().unwrap();
                    (row[0].index().unwrap(), row[1].index().unwrap())
                })
                .collect();
            session
                .result(
                    u64::try_from(result.field("resultHandle").unwrap().index().unwrap()).unwrap(),
                )
                .unwrap()
                .close();
        }
        Session::Rayon(session) => {
            let rows: Vec<Row> = input
                .iter()
                .map(|(a, b)| vec![Value::Integer((*a).into()), Value::Integer((*b).into())].into())
                .collect();
            session
                .replace(BTreeMap::from([("edge".into(), rows)]), &limits, &cancel)
                .unwrap();
            replaced = start.elapsed().as_nanos();
            let result = session.run(None, &limits, &cancel).unwrap();
            assert!(result.complete);
            answer = result.relations["reach"]
                .iter()
                .map(|row| (integer(&row[0]), integer(&row[1])))
                .collect();
            session.result(result.result_handle).unwrap().close();
        }
    }
    let observed = start.elapsed().as_nanos();
    answer.sort_unstable();
    assert_eq!(
        answer,
        expected(groups, width, offset),
        "independent complete transitive closure"
    );
    let mut hash = Sha256::new();
    for (a, b) in answer {
        hash.update(a.to_le_bytes());
        hash.update(b.to_le_bytes());
    }
    Observation {
        task,
        latency_ns: start.elapsed().as_nanos(),
        completion_ns: 0,
        replace_ns: replaced,
        run_export_ns: observed - replaced,
        digest: format!("{:x}", hash.finalize()),
    }
}
fn run_sample(
    sessions: &mut [Session],
    pool: &ProcessPool,
    tasks: usize,
    groups: usize,
    width: usize,
    sample: usize,
) -> (Vec<Observation>, std::time::Duration) {
    let clients = sessions.len();
    let next = Arc::new(AtomicUsize::new(0));
    let ready = Arc::new(Barrier::new(clients + 1));
    let start = Arc::new(Barrier::new(clients + 1));
    let epoch = Arc::new(std::sync::OnceLock::<Instant>::new());
    std::thread::scope(|scope| {
        let mut handles = Vec::new();
        for session in sessions {
            let next = next.clone();
            let ready = ready.clone();
            let start = start.clone();
            let epoch = epoch.clone();
            handles.push(scope.spawn(move || {
                ready.wait();
                start.wait();
                let mut rows = Vec::new();
                loop {
                    let task = next.fetch_add(1, Ordering::Relaxed);
                    if task >= tasks {
                        break;
                    }
                    let mut observation = execute(session, sample * tasks + task, groups, width);
                    observation.completion_ns = epoch.get().unwrap().elapsed().as_nanos();
                    rows.push(observation);
                }
                rows
            }));
        }
        ready.wait();
        pool.reset_statistics();
        epoch.set(Instant::now()).unwrap();
        let begin = *epoch.get().unwrap();
        start.wait();
        let rows: Vec<_> = handles
            .into_iter()
            .flat_map(|h| h.join().unwrap())
            .collect();
        let elapsed = begin.elapsed();
        assert_eq!(rows.len(), tasks);
        (rows, elapsed)
    })
}
fn report_sample(
    rows: &[Observation],
    pool: &ProcessPool,
    elapsed: std::time::Duration,
    header: &str,
) {
    let tasks = rows.len();
    let owners = pool.receipts().len();
    let mut latencies: Vec<_> = rows.iter().map(|r| r.latency_ns).collect();
    latencies.sort_unstable();
    let mut ordered: Vec<_> = rows.iter().collect();
    ordered.sort_by_key(|r| r.task);
    let mut digest = Sha256::new();
    for row in &ordered {
        digest.update(row.digest.as_bytes());
    }
    let stats: Vec<_> = (0..owners)
        .map(|i| pool.owner(i).unwrap().statistics())
        .collect();
    eprintln!(
        "PROCESS-SAMPLE {header} tasks={tasks} wall_ns={} throughput_per_s={:.6} p50_ns={} p95_ns={} max_overlapping_vm_calls={} native_calls={} queue_ns={} service_ns={} checkpoints={} shared_checkpoints={} answer_sha={:x}",
        elapsed.as_nanos(),
        f64::from(u32::try_from(tasks).unwrap()) / elapsed.as_secs_f64(),
        latencies[(tasks - 1) / 2],
        latencies[((tasks * 95).div_ceil(100) - 1).min(tasks - 1)],
        stats
            .iter()
            .map(|s| s.maximum_overlapping_calls)
            .max()
            .unwrap(),
        stats.iter().map(|s| s.calls).sum::<u64>(),
        stats.iter().map(|s| s.queue_ns).sum::<u64>(),
        stats.iter().map(|s| s.service_ns).sum::<u64>(),
        stats.iter().map(|s| s.checkpoints).sum::<u64>(),
        stats.iter().map(|s| s.shared_checkpoints).sum::<u64>(),
        digest.finalize()
    );
}
// Continuous overload qualification is separate from equal-work speedup.
// Retain only twelve summaries, never one record per completed soak request.
fn run_soak(
    sessions: &mut [Session],
    pool: &ProcessPool,
    groups: usize,
    width: usize,
    first_task: usize,
    duration: std::time::Duration,
    header: &str,
) {
    let clients = sessions.len();
    let ready = Arc::new(Barrier::new(clients + 1));
    let start = Arc::new(Barrier::new(clients + 1));
    let epoch = Arc::new(std::sync::OnceLock::<Instant>::new());
    let next = Arc::new(AtomicUsize::new(first_task));
    let (count, latency, maximum, histogram, minimum, elapsed) = std::thread::scope(|scope| {
        let mut handles = Vec::new();
        for session in sessions {
            let ready = ready.clone();
            let start = start.clone();
            let epoch = epoch.clone();
            let next = next.clone();
            handles.push(scope.spawn(move || {
                ready.wait();
                start.wait();
                let mut count = 0_u64;
                let mut latency = 0_u128;
                let mut maximum = (0_u128, 0_u128, 0_u128, 0_usize);
                let mut histogram = vec![0_u64; 65_536];
                while epoch.get().unwrap().elapsed() < duration {
                    let task = next.fetch_add(1, Ordering::Relaxed);
                    let row = execute(session, task, groups, width);
                    count += 1;
                    latency += row.latency_ns;
                    if row.latency_ns > maximum.0 {
                        maximum = (row.latency_ns, row.replace_ns, row.run_export_ns, row.task);
                    }
                    let bucket = usize::try_from((row.latency_ns / 100_000).min(65_535)).unwrap();
                    histogram[bucket] += 1;
                }
                (count, latency, maximum, histogram)
            }));
        }
        ready.wait();
        pool.reset_statistics();
        epoch.set(Instant::now()).unwrap();
        start.wait();
        let mut total = (
            0_u64,
            0_u128,
            (0_u128, 0_u128, 0_u128, 0_usize),
            vec![0_u64; 65_536],
        );
        let mut minimum = u64::MAX;
        for handle in handles {
            let (count, latency, maximum, histogram) = handle.join().unwrap();
            total.0 += count;
            total.1 += latency;
            if maximum.0 > total.2.0 {
                total.2 = maximum;
            }
            minimum = minimum.min(count);
            for (sum, count) in total.3.iter_mut().zip(histogram) {
                *sum += count;
            }
        }
        (
            total.0,
            total.1,
            total.2,
            total.3,
            minimum,
            epoch.get().unwrap().elapsed(),
        )
    });
    report_soak(
        pool,
        duration,
        header,
        SoakSample {
            count,
            latency,
            maximum,
            histogram,
            minimum,
            elapsed,
        },
    );
}
struct SoakSample {
    count: u64,
    latency: u128,
    maximum: (u128, u128, u128, usize),
    histogram: Vec<u64>,
    minimum: u64,
    elapsed: std::time::Duration,
}
fn report_soak(
    pool: &ProcessPool,
    duration: std::time::Duration,
    header: &str,
    sample: SoakSample,
) {
    let SoakSample {
        count,
        latency,
        maximum,
        histogram,
        minimum,
        elapsed,
    } = sample;
    let (maximum, replace_ns, run_export_ns, task) = maximum;
    let validation_ns = maximum
        .checked_sub(replace_ns)
        .and_then(|remaining| remaining.checked_sub(run_export_ns))
        .expect("nonoverlapping phases of the same longest request");
    assert!(count > 0 && minimum > 0 && elapsed >= duration);
    assert_eq!(histogram.iter().sum::<u64>(), count);
    let p50 = percentile_bounds(&histogram, count, 50, maximum);
    let p95 = percentile_bounds(&histogram, count, 95, maximum);
    let stats: Vec<_> = (0..pool.receipts().len())
        .map(|i| pool.owner(i).unwrap().statistics())
        .collect();
    eprintln!(
        "PROCESS-SOAK {header} requested_ns={} wall_ns={} completed_requests={count} checked_requests={count} minimum_client_requests={minimum} throughput_per_s={:.6} mean_ns={} max_ns={maximum} p50_lower_ns={} p50_upper_ns={} p95_lower_ns={} p95_upper_ns={} histogram_resolution_ns=100000 histogram_buckets=65536 max_overlapping_vm_calls={} native_calls={} checkpoints={} shared_checkpoints={} slowest_schema=same-request-v1",
        duration.as_nanos(),
        elapsed.as_nanos(),
        f64::from(u32::try_from(count).unwrap()) / elapsed.as_secs_f64(),
        latency / u128::from(count),
        p50.0,
        p50.1,
        p95.0,
        p95.1,
        stats
            .iter()
            .map(|s| s.maximum_overlapping_calls)
            .max()
            .unwrap(),
        stats.iter().map(|s| s.calls).sum::<u64>(),
        stats.iter().map(|s| s.checkpoints).sum::<u64>(),
        stats.iter().map(|s| s.shared_checkpoints).sum::<u64>()
    );
    // Emitted after measurement. Keep the independent oracle and all original
    // latency/histogram fields; this is one request, not unrelated phase maxima.
    eprintln!(
        "PROCESS-SLOWEST {header} task={task} total_ns={maximum} replace_ns={replace_ns} run_export_ns={run_export_ns} validation_ns={validation_ns}"
    );
}
// Exact bucket counts bound each quantile. The overflow bucket's upper bound
// is the observed maximum; it is never reported as a precise percentile.
fn percentile_bounds(
    histogram: &[u64],
    count: u64,
    percentile: u64,
    maximum: u128,
) -> (u128, u128) {
    let rank = (u128::from(count) * u128::from(percentile)).div_ceil(100);
    let mut seen = 0_u128;
    for (index, count) in histogram.iter().enumerate() {
        seen += u128::from(*count);
        if seen >= rank {
            let lower = u128::try_from(index).unwrap() * 100_000;
            let upper = if index + 1 == histogram.len() {
                maximum
            } else {
                lower + 100_000
            };
            return (lower, upper);
        }
    }
    panic!("soak histogram does not account for every completed request");
}
fn arguments() -> (Vec<String>, [usize; 6]) {
    let args: Vec<_> = std::env::args()
        .skip(1)
        .filter(|a| a != "--bench")
        .collect();
    assert!(
        args.len() == 8 || args.len() == 9,
        "worker-executable vm|rayon owners rayon-threads tasks groups width samples [soak-seconds]"
    );
    let mode = &args[1];
    assert!(mode == "vm" || mode == "rayon");
    let number = |i: usize| args[i].parse::<usize>().unwrap();
    let parsed = [
        number(2),
        number(3),
        number(4),
        number(5),
        number(6),
        number(7),
    ];
    let [owners, threads, tasks, groups, width, samples] = parsed;
    assert!(owners > 0 && threads > 0 && tasks >= owners && groups > 0 && width > 1 && samples > 0);
    assert!(mode != "vm" || threads == 1);
    (args, parsed)
}
fn work_distribution() -> (String, gerbil_ascent::WorkDistribution) {
    let distribution_name =
        std::env::var("ASCENT_WORK_DISTRIBUTION").unwrap_or_else(|_| "adaptive".into());
    let distribution = match distribution_name.as_str() {
        "across-requests" => gerbil_ascent::WorkDistribution::AcrossRequests,
        "within-request" => gerbil_ascent::WorkDistribution::WithinRequest,
        "adaptive" => gerbil_ascent::WorkDistribution::Adaptive,
        value => panic!("unknown work distribution: {value}"),
    };
    (distribution_name, distribution)
}
fn main() {
    let (args, [owners, threads, tasks, groups, width, samples]) = arguments();
    let mode = &args[1];
    let startup = Instant::now();
    let pool = ProcessPool::with_program(owners, &WorkerProgram::new(&args[0], vec![])).unwrap();
    for receipt in pool.receipts() {
        eprintln!(
            "PROCESS-OWNER pid={} processors={} domain={}",
            receipt.pid, receipt.processors, receipt.domain
        );
    }
    // All Rayon clients share this one caller-owned Rust thread pool.
    let (distribution_name, distribution) = work_distribution();
    eprintln!("RAYON-WORK-DISTRIBUTION {distribution:?}");
    let engine = Engine::new(threads)
        .unwrap()
        .with_work_distribution(distribution);
    assert_eq!(
        engine.threads(),
        threads,
        "actual caller-owned Rayon pool size"
    );
    let clients = 12;
    assert!(tasks >= clients);
    let mut sessions = Vec::new();
    let mut retained = Vec::new();
    for client in 0..clients {
        let scoped = if mode == "vm" {
            Engine::new(1).unwrap()
        } else {
            engine.clone()
        }
        .on_process(pool.owner(client % owners).unwrap());
        let module = scoped.load_definitions(SOURCE).unwrap();
        let value = module.call("make", &[], None).unwrap();
        let session = if mode == "vm" {
            Session::Scheme(value.open_session(FactLimits::default()).unwrap())
        } else {
            let mut session = value.project_session(FactLimits::default()).unwrap();
            session
                .run(
                    None,
                    &SourceSession::default_limits(),
                    &Cancellation::default(),
                )
                .unwrap();
            Session::Rayon(Box::new(session))
        };
        sessions.push(session);
        retained.push((scoped, module, value));
    }
    for (i, session) in sessions.iter_mut().enumerate() {
        execute(session, samples * tasks + i, groups, width);
    }
    let checkpoint_transport = compiled_checkpoint_transport();
    eprintln!(
        "PROCESS-READY mode={mode} vms={owners} rust_threads={threads} clients={clients} checkpoint_transport={checkpoint_transport} work_distribution={distribution_name} startup_ns={}",
        startup.elapsed().as_nanos()
    );
    println!("sample\ttask\tlatency_ns\tcompletion_ns\treplace_ns\trun_export_ns\tanswer_sha");
    for sample in 0..samples {
        let (observations, elapsed) =
            run_sample(&mut sessions, &pool, tasks, groups, width, sample);
        report_sample(
            &observations,
            &pool,
            elapsed,
            &format!(
                "sample={sample} mode={mode} vms={owners} rust_threads={threads} clients={clients}"
            ),
        );
        for row in observations {
            println!(
                "{sample}\t{}\t{}\t{}\t{}\t{}\t{}",
                row.task,
                row.latency_ns,
                row.completion_ns,
                row.replace_ns,
                row.run_export_ns,
                row.digest
            );
        }
    }
    if let Some(seconds) = args.get(8) {
        let duration = std::time::Duration::from_secs(seconds.parse().unwrap());
        assert!(!duration.is_zero());
        run_soak(
            &mut sessions,
            &pool,
            groups,
            width,
            samples * tasks + clients,
            duration,
            &format!("mode={mode} vms={owners} rust_threads={threads} clients={clients}"),
        );
    }
    close_sessions(sessions, retained);
    drop(engine);
    drop(pool);
}

fn close_sessions(
    sessions: Vec<Session>,
    retained: Vec<(Engine, ascent_scheme::Module, ascent_scheme::ModuleValue)>,
) {
    for session in sessions {
        match session {
            Session::Scheme(s) => s.close(),
            Session::Rayon(mut s) => s.close(),
        }
    }
    for (scoped, module, value) in retained {
        value.close();
        module.close();
        scoped.shutdown();
    }
}

fn compiled_checkpoint_transport() -> &'static str {
    ascent_scheme::benchmark::kernel_checkpoint_transport()
}
