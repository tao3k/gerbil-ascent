//! Build-time controls do not enter a Gambit VM.
#[path = "../build_support/cache.rs"]
mod cache;
#[path = "../build_support/input.rs"]
mod input;
#[path = "../build_support/ledger.rs"]
mod ledger;
#[path = "../build_support/observer.rs"]
mod observer;
#[path = "../build_support/policy.rs"]
mod policy;
#[path = "support/archive_stress.rs"]
mod stress;

use gerbil_scheme_aot_build::{
    CargoDirective, CargoDirectiveKind, NativeArchiveLinkReceipt, ProgramArchiveObservation,
    ProgramArchiveObserver,
};
use std::{
    fs::{self, OpenOptions},
    path::PathBuf,
    sync::atomic::{AtomicUsize, Ordering},
    time::Duration,
};

static NEXT: AtomicUsize = AtomicUsize::new(0);

#[test]
fn concurrent_archive_publishers() {
    stress::run();
}
struct Scratch(PathBuf);
impl Scratch {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "ascent-archive-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }
    fn observer(&self) -> observer::Observer {
        fs::write(self.0.join("input.scm"), "(define value 42)").unwrap();
        let result =
            observer::Observer::new(&self.0, &self.0.join("inputs"), &self.0.join("static"), 0)
                .unwrap();
        result.observe(ProgramArchiveObservation {
            phase: "program-plan",
            state: "complete",
            operation: "validate",
            subject: None,
            elapsed: None,
        });
        result.observe_source_input(&self.0.join("input.scm"));
        result
    }
}
impl Drop for Scratch {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn event(
    subject: &'static str,
    state: &'static str,
    nanos: Option<u64>,
) -> ProgramArchiveObservation<'static> {
    ProgramArchiveObservation {
        phase: "native-object",
        state,
        operation: "compile",
        subject: Some(subject),
        elapsed: nanos.map(Duration::from_nanos),
    }
}
#[test]
fn interleaved_workers_and_hits_have_distinct_measured_costs() {
    let scratch = Scratch::new();
    let owner = scratch.observer();
    owner.observe(event("a", "start", None));
    owner.observe(event("b", "start", None));
    owner.observe(event("b", "complete", Some(20)));
    owner.observe(event("a", "complete", Some(10)));
    owner.observe(event("c", "cached", None));
    owner.finish(true).unwrap();
    let receipt: serde_json::Value =
        serde_json::from_slice(&fs::read(scratch.0.join("archive-work.json")).unwrap()).unwrap();
    assert_eq!(receipt["starts"], 2);
    assert_eq!(receipt["completed"], 2);
    assert_eq!(receipt["phases"]["native-object"]["cached"], 1);
    assert_eq!(receipt["phases"]["native-object"]["worker_nanoseconds"], 30);
    let digest = receipt["sources"][0]["sha256"].as_str().unwrap();
    assert_eq!(
        fs::read(scratch.0.join("inputs").join(digest)).unwrap(),
        b"(define value 42)"
    );
}

#[test]
fn concurrent_observers_retain_every_worker_event() {
    let scratch = Scratch::new();
    let owner = scratch.observer();
    let barrier = std::sync::Barrier::new(12);
    std::thread::scope(|scope| {
        for worker in 0..12 {
            let owner = &owner;
            let barrier = &barrier;
            scope.spawn(move || {
                barrier.wait();
                for index in 0..64 {
                    let subject = format!("worker-{worker}-object-{index}");
                    for (state, elapsed) in
                        [("start", None), ("complete", Some(Duration::from_nanos(1)))]
                    {
                        owner.observe(ProgramArchiveObservation {
                            phase: "native-object",
                            operation: "compile",
                            state,
                            subject: Some(&subject),
                            elapsed,
                        });
                        std::thread::yield_now();
                    }
                }
            });
        }
    });
    owner.finish(true).unwrap();
    let receipt: serde_json::Value =
        serde_json::from_slice(&fs::read(scratch.0.join("archive-work.json")).unwrap()).unwrap();
    assert_eq!(receipt["starts"], 768);
    assert_eq!(receipt["completed"], 768);
    assert_eq!(receipt["archive_object_compilations"], 768);
    assert_eq!(
        receipt["phases"]["native-object"]["worker_nanoseconds"],
        768
    );
}
#[test]
fn malformed_incomplete_and_failed_observations_reject() {
    let cases = [
        vec![event("a", "start", None)],
        vec![event("a", "complete", Some(1))],
        vec![event("a", "cached", Some(1))],
        vec![event("a", "complete", None)],
        vec![event("a", "unknown", None)],
        vec![event("a", "start", None), event("a", "cached", None)],
        vec![event("a", "start", None), event("a", "failed", Some(1))],
        vec![event("a", "cached", None), event("a", "cached", None)],
    ];
    for events in cases {
        let scratch = Scratch::new();
        let owner = scratch.observer();
        for event in events {
            owner.observe(event);
        }
        assert!(owner.finish(true).is_err());
    }
}
#[test]
fn changed_missing_inputs_and_builder_failure_reject() {
    for changed in 0..3 {
        let scratch = Scratch::new();
        let owner = scratch.observer();
        match changed {
            0 => fs::write(scratch.0.join("input.scm"), "changed").unwrap(),
            1 => fs::remove_file(scratch.0.join("input.scm")).unwrap(),
            _ => {}
        }
        assert!(owner.finish(changed != 2).is_err());
    }
}
#[test]
fn lease_excludes_other_publishers_and_private_archives_do_not_alias() {
    let scratch = Scratch::new();
    let cargo_out = scratch.0.join("target/debug/build/ascent-scheme-one/out");
    fs::create_dir_all(&cargo_out).unwrap();
    let owner = cache::Lease::acquire(&cargo_out).unwrap();
    let lock = OpenOptions::new()
        .read(true)
        .write(true)
        .open(owner.graph.parent().unwrap().join("build.lock"))
        .unwrap();
    assert!(matches!(
        lock.try_lock(),
        Err(std::fs::TryLockError::WouldBlock)
    ));
    fs::create_dir_all(&owner.archive).unwrap();
    let archive = owner.archive.join("libascent_hybrid.a");
    fs::write(&archive, b"first").unwrap();
    let receipt = NativeArchiveLinkReceipt {
        archive_name: "ascent_hybrid".into(),
        archive_file: archive.clone(),
        cargo_directives: vec![CargoDirective::new(
            CargoDirectiveKind::RustcLinkSearch,
            format!("native={}", owner.archive.display()),
        )],
    };
    owner.publish(&cargo_out, &receipt).unwrap();
    fs::write(&archive, b"second").unwrap();
    assert_eq!(
        fs::read(cargo_out.join("archive/libascent_hybrid.a")).unwrap(),
        b"first"
    );
    drop(owner);
    lock.try_lock().unwrap();
    lock.unlock().unwrap();
    let other_out = scratch.0.join("target/release/build/ascent-scheme-two/out");
    let other = cache::Lease::acquire(&other_out).unwrap();
    assert_eq!(other.archive, archive.parent().unwrap());
    other.publish(&other_out, &receipt).unwrap();
    assert_eq!(
        fs::read(other_out.join("archive/libascent_hybrid.a")).unwrap(),
        b"second"
    );
}

#[test]
fn generated_outputs_do_not_create_a_cargo_rebuild_feedback_loop() {
    use std::path::Path;
    let generated = Path::new("/target/ascent-program-v1");
    let owned = Path::new("/package/.gerbil/lib/static");
    for name in [
        "gerbil-ascent__program__evaluate.scm",
        "gerbil-scheme-rust__scheme__runtime.scm",
    ] {
        assert!(!input::externally_owned(
            &owned.join(name),
            generated,
            owned
        ));
    }
    assert!(!input::externally_owned(
        &generated.join("graph/program.json"),
        generated,
        owned
    ));
    assert!(input::externally_owned(
        &owned.join("clan__poo__object.scm"),
        generated,
        owned
    ));
    assert!(input::externally_owned(
        Path::new("/sdk/include/gambit.h"),
        generated,
        owned
    ));
    assert!(input::externally_owned(
        Path::new("/package/program/evaluate.ss"),
        generated,
        owned
    ));
}
