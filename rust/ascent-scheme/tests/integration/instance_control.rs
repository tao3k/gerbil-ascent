//! Exercise the original controller while a second VM retires in the same process.
#![cfg(target_os = "macos")]
use ascent_scheme::InstancePool;
use gerbil_ascent::{Cancellation, Data, Error};
use std::time::{Duration, Instant};
#[test]
fn a_retiring_independent_vm_cannot_disable_another_owners_deadline() {
    check_deadline(true, true);
}
#[test]
fn a_single_owner_interrupts_a_non_yielding_scheme_call() {
    check_deadline(false, false);
}
#[test]
fn a_second_live_vm_preserves_the_first_owners_deadline() {
    check_deadline(true, false);
}
fn check_deadline(create_other: bool, retire_other: bool) {
    let pool = InstancePool::new(1).unwrap();
    let owner = pool.owner(0).unwrap();
    let module = owner
        .call(Data::object([
            ("operation", Data::from("dsl-open")),
            ("trusted", Data::Bool(true)),
            ("source", Data::from("(def (burn) (let loop () (loop)))")),
        ]))
        .unwrap();
    let other = create_other.then(|| InstancePool::new(1).unwrap());
    let before = owner.statistics().checkpoints;
    std::thread::scope(|scope| {
        let owner = &owner;
        let module = &module;
        let call = scope.spawn(move || {
            owner.call_cancelable(
                Data::object([
                    ("operation", Data::from("module-call")),
                    ("owner", module.field("owner").unwrap().clone()),
                    ("export", Data::from("burn")),
                    ("arguments", Data::List(vec![])),
                ]),
                Duration::from_millis(250),
                &Cancellation::default(),
            )
        });
        let entered = Instant::now() + Duration::from_secs(1);
        while owner.statistics().checkpoints <= before {
            assert!(
                Instant::now() < entered,
                "owner never entered controlled execution"
            );
            std::thread::yield_now();
        }
        if retire_other {
            let retirement = other
                .as_ref()
                .unwrap()
                .shutdown(Duration::from_secs(1))
                .unwrap();
            eprintln!("INSTANCE-RETIREMENT {retirement:?}");
        }
        assert_eq!(call.join().unwrap(), Err(Error::Timeout));
    });
    owner
        .call_cancelable(
            Data::object([("operation", Data::from("describe"))]),
            Duration::from_secs(2),
            &Cancellation::default(),
        )
        .expect("the original VM must regain its owner after the bounded call");
}
