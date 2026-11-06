//! Advisory capacity never shrinks the pool or limits request admission.
use super::Engine;
use crate::execution::work::fanout_capacity;
use std::sync::Barrier;

#[test]
fn nested_capacity_is_bounded_by_pool_and_observed_host_slots() {
    for workers in 1..=64 {
        for available in 1..=64 {
            let capacity = fanout_capacity(workers, available);
            assert!(capacity > 0 && capacity <= workers && capacity <= available);
            assert_eq!(capacity, workers.min(available));
        }
    }
    let engine = Engine::new(12).unwrap();
    let host = std::thread::available_parallelism().unwrap().get();
    assert_eq!(engine.threads(), 12);
    assert_eq!(engine.fanout_capacity(), 12.min(host));
}

#[test]
fn three_slot_advice_keeps_twelve_workers_and_concurrent_requests() {
    let mut engine = Engine::new(12).unwrap();
    engine.fanout_capacity = 3;
    let barrier = Barrier::new(13);
    std::thread::scope(|scope| {
        for _ in 0..12 {
            let (engine, barrier) = (&engine, &barrier);
            scope.spawn(move || {
                engine.pool.install(|| {
                    let _evaluation = engine.work.enter().unwrap();
                    barrier.wait();
                    barrier.wait();
                });
            });
        }
        barrier.wait();
        assert_eq!(engine.threads(), 12);
        assert_eq!(engine.pending_evaluations(), 12);
        assert!(!engine.request_fanout());
        barrier.wait();
    });
    assert_eq!(engine.pending_evaluations(), 0);
    let first = engine.work.enter().unwrap();
    let second = engine.work.enter().unwrap();
    let third = engine.work.enter().unwrap();
    assert!(!engine.request_fanout());
    drop(third);
    assert!(engine.request_fanout());
    drop((first, second));
}
