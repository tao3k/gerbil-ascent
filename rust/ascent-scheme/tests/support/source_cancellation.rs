//! Interrupt the real source controller after it has entered native execution.
use ascent_scheme::{Engine, ProcessOwner};
use gerbil_ascent::{Cancellation, Error, FactLimits, Limits, ObjectInput};
use std::{
    collections::BTreeMap,
    time::{Duration, Instant},
};

pub fn verify(engine: &Engine, owner: &ProcessOwner) {
    let module = engine.load_definitions("(define-program (make) (sources edge) (outputs reach) (relation edge ((a exact-integer?) (b exact-integer?))) (relation reach ((a exact-integer?) (b exact-integer?))) ((reach a b) <-- (edge a b)) ((reach a c) <-- (reach a b) (edge b c)))").unwrap();
    let value = module.call("make", &[], None).unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    let edges = (0..128)
        .map(|i| {
            vec![
                ObjectInput::Integer(i.into()),
                ObjectInput::Integer((i + 1).into()),
            ]
        })
        .collect();
    let input = BTreeMap::from([("edge".to_owned(), edges)]);
    let cancel = Cancellation::default();
    let before = owner.statistics().checkpoints;
    std::thread::scope(|scope| {
        let signal = cancel.clone();
        scope.spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(2);
            while owner.statistics().checkpoints <= before + 2 {
                assert!(
                    Instant::now() < deadline,
                    "source execution never reached its controller"
                );
                std::thread::yield_now();
            }
            signal.cancel();
        });
        assert_eq!(
            session.replace(input, &Limits::default(), &cancel),
            Err(Error::Canceled)
        );
    });
    let recovered = BTreeMap::from([(
        "edge".to_owned(),
        vec![vec![
            ObjectInput::Integer(0.into()),
            ObjectInput::Integer(1.into()),
        ]],
    )]);
    session
        .replace(recovered, &Limits::default(), &Cancellation::default())
        .unwrap();
    session
        .run(None, &Limits::default(), &Cancellation::default())
        .unwrap();
    session.close();
    value.close();
    module.close();
}
