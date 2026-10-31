use super::State;
// Frozen pre-refactor semantics; no calls to the production transition.
fn reference(state: &mut State, work: i64, interrupted: i32) -> i32 {
    if work == -2 {
        state.suspended = true;
        return 0;
    }
    if work == -3 {
        state.suspended = false;
        return 0;
    }
    if state.suspended {
        return 0;
    }
    if !state.accepted && interrupted != 0 {
        return interrupted;
    }
    if state.accepted {
        return 0;
    }
    if work == -1 {
        state.accepted = true;
        return 0;
    }
    if work < 0 {
        return 3;
    }
    let total = (state.work as u128) + u128::try_from(work).unwrap();
    if total > (state.maximum as u128) || total > (usize::MAX as u128) {
        return 3;
    }
    state.work = usize::try_from(total).unwrap();
    0
}
#[test]
fn every_signed_transition_matches_the_frozen_controller_with_all_flags_and_boundaries() {
    for current in [0, 1, 2, usize::MAX - 1, usize::MAX] {
        for maximum in [0, 1, 2, usize::MAX - 1, usize::MAX] {
            for accepted in [false, true] {
                for suspended in [false, true] {
                    for interruption in [0, 1, 2] {
                        for work in [i64::MIN, -4, -3, -2, -1, 0, 1, 2, i64::MAX] {
                            let mut actual = State {
                                work: current,
                                maximum,
                                accepted,
                                suspended,
                            };
                            let mut expected = actual;
                            let code = actual
                                .advance(work, |accepted| if accepted { 0 } else { interruption });
                            assert_eq!(
                                (code, actual),
                                (reference(&mut expected, work, interruption), expected)
                            );
                        }
                    }
                }
            }
        }
    }
}
#[test]
fn suspension_and_acceptance_do_not_evaluate_unused_interruptions() {
    let mut state = State {
        work: 0,
        maximum: 2,
        accepted: false,
        suspended: false,
    };
    for work in [-2, i64::MAX, -3] {
        assert_eq!(
            state.advance(work, |_| panic!(
                "suspended work must not consult cancellation or the clock"
            )),
            0
        );
    }
    assert_eq!(state.advance(-1, |_| 0), 0);
    assert_eq!(
        state.advance(i64::MAX, |accepted| {
            assert!(accepted);
            0
        }),
        0
    );
}
