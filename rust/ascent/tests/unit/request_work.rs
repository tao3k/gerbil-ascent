use super::{Work, WorkDistribution};

#[test]
fn shared_population_controls_only_advisory_fanout() {
    let work = Work::default();
    let clone = work.clone();
    let first = work.enter().unwrap();
    assert_eq!(clone.pending(), 1);
    assert!(clone.fanout(3, true));
    let second = clone.enter().unwrap();
    let third = work.enter().unwrap();
    assert!(!clone.fanout(3, true));
    let within = Work {
        distribution: WorkDistribution::WithinRequest,
        ..clone.clone()
    };
    let across = Work {
        distribution: WorkDistribution::AcrossRequests,
        ..clone.clone()
    };
    assert!(within.fanout(3, true));
    assert!(!within.fanout(3, false));
    assert!(!across.fanout(3, true));
    drop(second);
    assert!(clone.fanout(3, true));
    drop((first, third));
    assert_eq!(clone.pending(), 0);
}

#[test]
fn concurrent_entries_hold_the_exact_population_until_retirement() {
    let work = Work::default();
    let barrier = std::sync::Barrier::new(13);
    std::thread::scope(|scope| {
        for _ in 0..12 {
            let work = &work;
            let barrier = &barrier;
            scope.spawn(move || {
                let evaluation = work.enter();
                barrier.wait();
                barrier.wait();
                assert!(evaluation.is_ok());
            });
        }
        barrier.wait();
        let observed = work.pending();
        barrier.wait();
        assert_eq!(observed, 12);
    });
    assert_eq!(work.pending(), 0);
}

#[test]
fn exhausted_population_is_never_wrapped_or_published() {
    let work = Work::default();
    work.pending
        .store(usize::MAX, std::sync::atomic::Ordering::Release);
    assert!(matches!(work.enter(), Err(crate::Error::InvalidProgram(_))));
    assert_eq!(work.pending(), usize::MAX);
}
