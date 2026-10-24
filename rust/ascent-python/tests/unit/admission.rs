//! Owner admission preserves cancellation and the original end-to-end deadline.
use super::{admission_deadline, lock_before};
use gerbil_ascent as engine;
use std::{
    sync::{Mutex, mpsc},
    time::Duration,
};

#[test]
fn canceled_waiter_returns_while_the_owner_still_holds_the_lock() {
    let mutex = Mutex::new(());
    let owner = mutex.lock().unwrap();
    let cancellation = engine::Cancellation::default();
    let (send, receive) = mpsc::channel();
    let started = std::sync::Barrier::new(2);
    let result = std::thread::scope(|scope| {
        scope.spawn(|| {
            started.wait();
            send.send(
                lock_before(
                    &mutex,
                    admission_deadline(Duration::from_secs(5)).unwrap(),
                    &cancellation,
                )
                .map(|_| ()),
            )
            .unwrap();
        });
        started.wait();
        std::thread::sleep(Duration::from_millis(20));
        cancellation.cancel();
        let result = receive.recv_timeout(Duration::from_secs(1));
        drop(owner);
        result
    });
    assert!(matches!(result.unwrap(), Err(engine::Error::Canceled)));
}

#[test]
fn waiting_time_exhausts_the_operation_deadline_without_releasing_the_owner() {
    let mutex = Mutex::new(());
    let owner = mutex.lock().unwrap();
    let cancellation = engine::Cancellation::default();
    let (send, receive) = mpsc::channel();
    let result = std::thread::scope(|scope| {
        scope.spawn(|| {
            send.send(
                lock_before(
                    &mutex,
                    admission_deadline(Duration::from_millis(20)).unwrap(),
                    &cancellation,
                )
                .map(|_| ()),
            )
            .unwrap();
        });
        let result = receive.recv_timeout(Duration::from_secs(1));
        drop(owner);
        result
    });
    assert!(matches!(result.unwrap(), Err(engine::Error::Timeout)));
}

#[test]
fn expired_deadline_rejects_even_an_uncontended_cached_session() {
    assert!(matches!(
        lock_before(
            &std::sync::Mutex::new(()),
            std::time::Instant::now(),
            &engine::Cancellation::default()
        ),
        Err(engine::Error::Timeout)
    ));
}
