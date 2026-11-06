//! Public Darwin wait outcomes remain scheduling hints, never decisions.
use super::finish_wait;
use std::{
    cell::Cell,
    io,
    sync::atomic::{AtomicU32, Ordering},
};

#[test]
fn transient_wait_errors_recheck_the_live_phase_without_granting_a_decision() {
    for code in [libc::EFAULT, libc::ENOMEM] {
        let phase = AtomicU32::new(1);
        let backoffs = Cell::new(0);
        finish_wait(&phase, 1, Err(io::Error::from_raw_os_error(code)), || {
            backoffs.set(backoffs.get() + 1);
        })
        .unwrap();
        assert_eq!(backoffs.get(), 1);
        assert_eq!(phase.load(Ordering::Acquire), 1);
        phase.store(2, Ordering::Release);
        finish_wait(&phase, 1, Err(io::Error::from_raw_os_error(code)), || {
            backoffs.set(backoffs.get() + 1);
        })
        .unwrap();
        assert_eq!(backoffs.get(), 1, "changed phases must not wait again");
        assert_eq!(phase.load(Ordering::Acquire), 2);
    }
}

#[test]
fn ordinary_wake_outcomes_do_not_backoff_or_change_the_phase() {
    let phase = AtomicU32::new(1);
    for code in [libc::EAGAIN, libc::EINTR, libc::ETIMEDOUT] {
        finish_wait(&phase, 1, Err(io::Error::from_raw_os_error(code)), || {
            panic!("ordinary wake must return to the phase loop immediately");
        })
        .unwrap();
        assert_eq!(phase.load(Ordering::Acquire), 1);
    }
    finish_wait(&phase, 1, Ok(()), || panic!("success must not backoff")).unwrap();
}

#[test]
fn invalid_wait_configuration_and_unknown_errors_still_fail_closed() {
    let phase = AtomicU32::new(1);
    for code in [libc::EINVAL, libc::EIO, libc::EBADF] {
        let error = finish_wait(&phase, 1, Err(io::Error::from_raw_os_error(code)), || {
            panic!("fatal error must not retry");
        })
        .unwrap_err();
        assert_eq!(error.raw_os_error(), Some(code));
        assert_eq!(phase.load(Ordering::Acquire), 1);
    }
    assert!(
        finish_wait(&phase, 1, Err(io::Error::other("no native errno")), || {
            panic!("untyped error must not retry");
        })
        .is_err()
    );
}

#[test]
fn error_classes_match_the_frozen_platform_abi() {
    for (native, modeled) in super::WAIT_ERROR_IDS {
        assert_eq!(native, modeled);
    }
}
