//! Compare the actual metadata and full projection RPCs over source generations.
use super::id;
use crate::{Engine, control::Control};
use gerbil_ascent::{Cancellation, FactLimits, Limits, ObjectInput};
use std::collections::BTreeMap;

#[test]
fn status_and_projection_report_the_same_live_source_generation() {
    let engine = Engine::new(12).unwrap();
    let module = engine.load_definitions("(define-program (make) (sources input) (outputs out) (relation input ((x exact-integer?))) (relation out ((x exact-integer?))) ((out x) <-- (input x)))").unwrap();
    let value = module.call("make", &[], None).unwrap();
    let session = value.open_session(FactLimits::default()).unwrap();
    let cancel = Cancellation::default();
    let limits = Limits::default();
    session.run(None, &limits, &cancel).unwrap();
    for generation in 0..3 {
        let control = Control::new(&limits, &cancel).unwrap();
        let metadata = session.current_status(&control).unwrap();
        let projection = session.current_projection(&control).unwrap();
        assert_eq!(id(&metadata, "sourceGeneration").unwrap(), generation);
        assert_eq!(id(&projection, "sourceGeneration").unwrap(), generation);
        if generation < 2 {
            session
                .replace(
                    BTreeMap::from([(
                        "input".into(),
                        vec![vec![ObjectInput::Integer(generation.into())]],
                    )]),
                    &limits,
                    &cancel,
                )
                .unwrap();
        }
    }
}
