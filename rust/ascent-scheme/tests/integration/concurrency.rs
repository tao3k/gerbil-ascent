//! Shared-VM requests remain concurrent within one process, below its unchanged quota.
use ascent_scheme::Engine;
use gerbil_ascent::{GraphItem, ObjectInput};
use std::sync::Barrier;

#[test]
fn twelve_callers_share_one_vm_owner_without_losing_results() {
    let engine = Engine::new(4).unwrap();
    let barrier = Barrier::new(12);
    std::thread::scope(|scope| {
        for caller in 0..12 {
            let engine = &engine;
            let barrier = &barrier;
            scope.spawn(move || {
                barrier.wait();
                let module = engine.load_definitions("(def (answer n) (+ n 1))").unwrap();
                for round in 0..16 {
                    let number = caller * 16 + round;
                    let value = module
                        .call("answer", &[ObjectInput::Integer(number.into())], None)
                        .unwrap();
                    assert_eq!(
                        value.graph().unwrap().root,
                        GraphItem::Number((number + 1).to_string())
                    );
                }
            });
        }
    });
}
