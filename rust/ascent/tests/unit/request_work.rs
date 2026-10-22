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
