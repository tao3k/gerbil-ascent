//! Exact ordered request/reply, independent mappings and early-peer failure.
use super::Checkpoints;
#[test]
fn mapped_checkpoints_preserve_every_signed_transition_and_response() {
    for spins in [32, 1024] {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("control");
        let parent = Checkpoints::create(&path).unwrap();
        let child = Checkpoints::open(&path).unwrap();
        std::fs::remove_file(path).unwrap();
        child.begin(19);
        let responder = std::thread::spawn(move || {
            let mut sequence = Vec::new();
            parent
                .serve(
                    19,
                    |id, work| {
                        sequence.push((id, work));
                        i32::try_from(work).unwrap()
                    },
                    || Ok(false),
                    || spins,
                )
                .unwrap();
            sequence
        });
        for work in [-2, 0, -3, 1, 0, -1, 3, -2, 4, -3] {
            assert_eq!(
                child.request(19, work, || Ok(false)).unwrap(),
                i32::try_from(work).unwrap()
            );
        }
        child.complete();
        assert_eq!(
            responder.join().unwrap(),
            [-2, 0, -3, 1, 0, -1, 3, -2, 4, -3].map(|work| (19, work))
        );
    }
}
#[test]
fn mapped_checkpoints_fail_closed_when_the_peer_disappears() {
    let directory = tempfile::tempdir().unwrap();
    let mapped = Checkpoints::create(&directory.path().join("control")).unwrap();
    assert!(mapped.request(1, 1, || Ok(true)).is_err());
}

#[test]
fn bound_controller_keeps_original_accept_suspend_work_and_cancel_decisions() {
    use crate::control::{Control, checkpoint};
    use gerbil_ascent::{Cancellation, Limits};
    let cancel = Cancellation::default();
    let limits = Limits {
        max_states: 2,
        ..Limits::default()
    };
    for sequence in [vec![-2, 999, -3, 1, 0, 2], vec![1, -1, 999, -4, 0]] {
        let bound = Control::new(&limits, &cancel).unwrap();
        let original = Control::new(&limits, &cancel).unwrap();
        for work in sequence {
            assert_eq!(
                bound.checkpoint(work),
                checkpoint(original.numeric_id(), work)
            );
        }
    }
    let bound = Control::new(&limits, &cancel).unwrap();
    let original = Control::new(&limits, &cancel).unwrap();
    cancel.cancel();
    for work in [-2, 999, -3, 0, -1] {
        assert_eq!(
            bound.checkpoint(work),
            checkpoint(original.numeric_id(), work)
        );
    }
}

#[test]
fn previous_completion_cannot_finish_the_next_request_generation() {
    use std::{sync::mpsc, time::Duration};
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("control");
    let parent = Checkpoints::create(&path).unwrap();
    let child = Checkpoints::open(&path).unwrap();
    child.begin(19);
    child.complete();
    let (finished, done) = mpsc::channel();
    let responder = std::thread::spawn(move || {
        parent
            .serve(
                20,
                |id, work| {
                    assert_eq!((id, work), (20, -1));
                    0
                },
                || Ok(false),
                || 32,
            )
            .unwrap();
        finished.send(()).unwrap();
    });
    assert!(done.recv_timeout(Duration::from_millis(50)).is_err());
    child.begin(20);
    assert_eq!(child.request(20, -1, || Ok(false)).unwrap(), 0);
    child.complete();
    done.recv_timeout(Duration::from_secs(2)).unwrap();
    responder.join().unwrap();
}

#[test]
fn invalid_control_extents_are_rejected_before_shared_wait() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("invalid-control");
    let expected = u64::try_from(std::mem::size_of::<super::Slot>()).unwrap();
    for size in [0, 1, expected - 1, expected + 1, 4096] {
        let file = std::fs::File::create(&path).unwrap();
        file.set_len(size).unwrap();
        assert!(Checkpoints::open(&path).is_err(), "invalid extent {size}");
    }
}

#[test]
fn registered_notifications_preserve_contended_signed_generations() {
    use std::{sync::Barrier, time::Duration};
    assert_eq!((super::PARENT, super::CHILD), (1, 2));
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("contended-control");
    let parent = Checkpoints::create(&path).unwrap();
    let child = Checkpoints::open(&path).unwrap();
    let retired = Barrier::new(2);
    std::thread::scope(|threads| {
        let retired = &retired;
        threads.spawn(move || {
            for generation in 1..=64 {
                let mut seen = Vec::new();
                parent
                    .serve(
                        generation,
                        |id, work| {
                            assert_eq!(id, generation);
                            seen.push(work);
                            std::thread::sleep(Duration::from_micros(250));
                            i32::try_from(work).unwrap()
                        },
                        || Ok(false),
                        || if generation % 2 == 0 { 32 } else { 1024 },
                    )
                    .unwrap();
                assert_eq!(seen, [-2, 0, -3, 1, -1, 5]);
                retired.wait();
            }
        });
        for generation in 1..=64 {
            child.begin(generation);
            for work in [-2, 0, -3, 1, -1, 5] {
                assert_eq!(
                    child.request(generation, work, || Ok(false)).unwrap(),
                    i32::try_from(work).unwrap()
                );
                std::thread::sleep(Duration::from_micros(250));
            }
            child.complete();
            retired.wait();
        }
    });
}

#[test]
fn solo_wait_policy_keeps_original_budget_under_owner_or_cpu_pressure() {
    for (cpus, active, expected) in [
        (1, 1, 32),
        (2, 1, 32),
        (3, 0, 32),
        (3, 1, 1024),
        (3, 2, 32),
        (3, 12, 32),
        (12, 1, 1024),
        (12, 12, 32),
    ] {
        assert_eq!(super::parent_spin_budget(cpus, active), expected);
    }
}

#[test]
fn solo_parent_wait_fails_closed_without_issuing_a_decision() {
    let directory = tempfile::tempdir().unwrap();
    let parent = Checkpoints::create(&directory.path().join("closed-parent")).unwrap();
    assert!(
        parent
            .serve(
                1,
                |_, _| panic!("no request was published"),
                || Ok(true),
                || 1024,
            )
            .is_err()
    );
}
