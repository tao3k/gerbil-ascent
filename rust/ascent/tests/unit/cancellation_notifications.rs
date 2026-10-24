use super::{CancellationSubscription, GROUPS};
use crate::Cancellation;
use std::{
    sync::{
        Arc, Barrier, Mutex,
        atomic::{AtomicU64, Ordering},
    },
    task::Wake,
};
#[derive(Default)]
struct Count(AtomicU64);
impl Wake for Count {
    fn wake(self: Arc<Self>) {
        self.0.fetch_add(1, Ordering::AcqRel);
    }
    fn wake_by_ref(self: &Arc<Self>) {
        self.0.fetch_add(1, Ordering::AcqRel);
    }
}
#[test]
fn ordinary_atomic_cancellation_and_clones_are_unchanged() {
    let token = Cancellation::default();
    let clone = token.clone();
    assert!(!clone.is_canceled());
    token.cancel();
    assert!(clone.is_canceled());
    clone.cancel();
    assert!(token.is_canceled());
}
#[test]
fn cancelled_registration_is_signalled_before_return() {
    let token = Cancellation::default();
    token.cancel();
    let count = Arc::new(Count::default());
    let _registration = token.subscribe(count.clone().into()).unwrap();
    assert_eq!(count.0.load(Ordering::Acquire), 1);
}
#[test]
fn cancel_signals_registered_observers_before_return() {
    let token = Cancellation::default();
    let counts = [Arc::new(Count::default()), Arc::new(Count::default())];
    let _registrations: Vec<_> = counts
        .iter()
        .map(|c| token.subscribe(c.clone().into()).unwrap())
        .collect();
    token.cancel();
    assert!(counts.iter().all(|c| c.0.load(Ordering::Acquire) != 0));
}
#[test]
fn dropping_one_registration_preserves_other_and_releases_its_entry() {
    let token = Cancellation::default();
    let a = Arc::new(Count::default());
    let b = Arc::new(Count::default());
    let first = token.subscribe(a.clone().into()).unwrap();
    let second = token.subscribe(b.clone().into()).unwrap();
    drop(first);
    token.cancel();
    assert_eq!(a.0.load(Ordering::Acquire), 0);
    assert_eq!(b.0.load(Ordering::Acquire), 1);
    let key = second.key;
    drop(second);
    assert!(!GROUPS.get().unwrap().lock().unwrap().contains_key(&key));
}
#[test]
fn unrelated_tokens_never_receive_each_others_notifications() {
    let a = Cancellation::default();
    let b = Cancellation::default();
    let x = Arc::new(Count::default());
    let y = Arc::new(Count::default());
    let _first = a.subscribe(x.clone().into()).unwrap();
    let _second = b.subscribe(y.clone().into()).unwrap();
    a.cancel();
    assert_eq!(x.0.load(Ordering::Acquire), 1);
    assert_eq!(y.0.load(Ordering::Acquire), 0);
    assert!(!b.is_canceled());
}
#[test]
fn registration_cannot_miss_a_racing_cancel() {
    for _ in 0..200 {
        let token = Cancellation::default();
        let count = Arc::new(Count::default());
        let ready = Barrier::new(2);
        std::thread::scope(|threads| {
            let cancel = threads.spawn(|| {
                ready.wait();
                token.cancel();
            });
            ready.wait();
            let _registration = token.subscribe(count.clone().into()).unwrap();
            cancel.join().unwrap();
            assert!(count.0.load(Ordering::Acquire) != 0);
        });
    }
}
#[test]
fn notification_can_unregister_without_holding_the_registry_lock() {
    #[derive(Default)]
    struct Unregister(Mutex<Option<CancellationSubscription>>);
    impl Wake for Unregister {
        fn wake(self: Arc<Self>) {
            drop(self.0.lock().unwrap().take());
        }
    }
    let token = Cancellation::default();
    let wake = Arc::new(Unregister::default());
    *wake.0.lock().unwrap() = Some(token.subscribe(wake.clone().into()).unwrap());
    token.cancel();
    assert!(wake.0.lock().unwrap().is_none());
}
