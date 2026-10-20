//! Exact ordered request/reply, independent mappings and early-peer failure.
use super::Checkpoints;
#[test]
fn mapped_checkpoints_preserve_every_signed_transition_and_response() {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("control");
    let parent = Checkpoints::create(&path).unwrap();
    let child = Checkpoints::open(&path).unwrap();
    std::fs::remove_file(path).unwrap();
    let responder = std::thread::spawn(move || {
        let mut sequence = Vec::new();
        parent
            .serve(
                |id, work| {
                    sequence.push((id, work));
                    i32::try_from(work).unwrap()
                },
                || Ok(false),
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
