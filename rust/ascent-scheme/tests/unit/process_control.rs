use super::Shared;
use crate::control_state::State;
use gerbil_ascent::{Cancellation, Error, Limits};
use std::{
    sync::{Arc, Barrier, Mutex, mpsc},
    task::Wake,
    time::{Duration, Instant},
};
fn mapping() -> (tempfile::TempDir, Arc<Shared>, Arc<Shared>) {
    let directory = tempfile::tempdir().unwrap();
    let path = directory.path().join("admission");
    let parent = Arc::new(Shared::create(&path).unwrap());
    let child = Arc::new(Shared::open(&path).unwrap());
    (directory, parent, child)
}
fn state(maximum: usize) -> State {
    State {
        work: 0,
        maximum,
        accepted: false,
        suspended: false,
    }
}
#[test]
fn separate_mappings_share_every_charge_and_fence_retired_generations() {
    let (_dir, parent, child) = mapping();
    parent
        .begin(7, state(3), Instant::now() + Duration::from_secs(30))
        .unwrap();
    assert_eq!(child.checkpoint(7, 1), 0);
    assert_eq!(child.checkpoint(7, 2), 0);
    assert_eq!(child.checkpoint(7, 1), 3);
    assert_eq!(parent.finish(7).unwrap().work, 3);
    assert_eq!(child.checkpoint(7, -1), 5);
    parent
        .begin(8, state(0), Instant::now() + Duration::from_secs(30))
        .unwrap();
    assert_eq!(child.checkpoint(7, -1), 5);
    assert_eq!(child.checkpoint(8, 1), 3);
    assert_eq!(parent.finish(8).unwrap().work, 0);
}
#[test]
fn local_publication_is_only_a_request_until_the_original_controller_accepts() {
    let (_dir, parent, child) = mapping();
    parent
        .begin(1, state(0), Instant::now() + Duration::from_secs(30))
        .unwrap();
    assert_eq!(child.checkpoint(1, -1), 4);
    assert!(!parent.snapshot(1).unwrap().accepted);
    let mut accepted = parent.snapshot(1).unwrap();
    accepted.accepted = true;
    parent.publish(1, accepted).unwrap();
    parent.cancel(1);
    assert_eq!(child.checkpoint(1, i64::MAX), 0);
    assert!(parent.finish(1).unwrap().accepted);
}
#[test]
fn suspension_and_deadline_order_are_identical_to_the_original_controller() {
    let (_dir, parent, child) = mapping();
    parent.begin(1, state(0), Instant::now()).unwrap();
    assert_eq!(child.checkpoint(1, -2), 0);
    assert_eq!(child.checkpoint(1, i64::MAX), 0);
    assert_eq!(child.checkpoint(1, -3), 0);
    assert_eq!(child.checkpoint(1, -1), 2);
    assert!(!parent.finish(1).unwrap().accepted);
}
#[test]
fn real_control_leases_preserve_the_work_budget_across_calls() {
    let (_dir, parent, child) = mapping();
    let cancel = Cancellation::default();
    let control = crate::control::Control::new(
        &Limits {
            max_states: 3,
            ..Limits::default()
        },
        &cancel,
    )
    .unwrap();
    let id = control.numeric_id();
    let lease = control.lease(parent.clone()).unwrap();
    assert_eq!(child.checkpoint(id, 2), 0);
    lease.finish().unwrap();
    let lease = control.lease(parent.clone()).unwrap();
    assert_eq!(child.checkpoint(id, 2), 3);
    assert_eq!(child.checkpoint(id, 1), 0);
    cancel.cancel();
    assert!(matches!(control.check(), Err(Error::Canceled)));
    assert_eq!(child.checkpoint(id, -1), 1);
    lease.finish().unwrap();
}
struct Block {
    entered: mpsc::Sender<()>,
    released: Mutex<mpsc::Receiver<()>>,
}
impl Wake for Block {
    fn wake(self: Arc<Self>) {
        self.entered.send(()).unwrap();
        self.released.lock().unwrap().recv().unwrap();
    }
}
fn block() -> (std::task::Waker, mpsc::Receiver<()>, mpsc::Sender<()>) {
    let (entered, waiting) = mpsc::channel();
    let (released, release) = mpsc::channel();
    (
        Arc::new(Block {
            entered,
            released: Mutex::new(release),
        })
        .into(),
        waiting,
        released,
    )
}
#[test]
fn delayed_cancel_mirroring_cannot_authorize_a_publication() {
    let (_dir, parent, child) = mapping();
    let cancel = Cancellation::default();
    let (wake, waiting, release) = block();
    let _blocker = cancel.subscribe(wake).unwrap();
    let control = crate::control::Control::new(&Limits::default(), &cancel).unwrap();
    let id = control.numeric_id();
    let lease = control.lease(parent.clone()).unwrap();
    std::thread::scope(|threads| {
        let thread = threads.spawn(|| cancel.cancel());
        waiting.recv_timeout(Duration::from_secs(5)).unwrap();
        assert!(cancel.is_canceled());
        assert_eq!(child.checkpoint(id, 0), 0); // force the real mirror gap
        assert_eq!(child.checkpoint(id, -1), 4);
        assert_eq!(control.checkpoint(-1), 1);
        assert!(!parent.snapshot(id).unwrap().accepted);
        release.send(()).unwrap();
        thread.join().unwrap();
    });
    lease.finish().unwrap();
}
#[test]
fn a_cloned_old_notification_cannot_cancel_a_reused_slot() {
    let (_dir, parent, child) = mapping();
    let old = Cancellation::default();
    let (wake, waiting, release) = block();
    let _blocker = old.subscribe(wake).unwrap();
    let control = crate::control::Control::new(&Limits::default(), &old).unwrap();
    let lease = control.lease(parent.clone()).unwrap();
    std::thread::scope(|threads| {
        let thread = threads.spawn(|| old.cancel());
        waiting.recv_timeout(Duration::from_secs(5)).unwrap();
        lease.finish().unwrap();
        let fresh =
            crate::control::Control::new(&Limits::default(), &Cancellation::default()).unwrap();
        let fresh_lease = fresh.lease(parent.clone()).unwrap();
        release.send(()).unwrap();
        thread.join().unwrap();
        assert_eq!(child.checkpoint(fresh.numeric_id(), 0), 0);
        fresh_lease.finish().unwrap();
    });
}
#[test]
fn concurrent_accept_and_cancel_have_one_consistent_original_controller_decision() {
    let (_dir, parent, child) = mapping();
    for _ in 0..200 {
        let token = Cancellation::default();
        let control = crate::control::Control::new(&Limits::default(), &token).unwrap();
        let id = control.numeric_id();
        let lease = control.lease(parent.clone()).unwrap();
        assert_eq!(child.checkpoint(id, -1), 4);
        let ready = Barrier::new(2);
        std::thread::scope(|threads| {
            let thread = threads.spawn(|| {
                ready.wait();
                token.cancel();
            });
            ready.wait();
            let code = control.checkpoint(-1);
            thread.join().unwrap();
            let accepted = parent.snapshot(id).unwrap().accepted;
            assert!(matches!((code, accepted), (0, true) | (1, false)));
            assert_eq!(control.check().is_ok(), accepted);
        });
        lease.finish().unwrap();
    }
}
