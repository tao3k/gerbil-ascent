//! Public Darwin compare-and-wait; availability preserves the socket fallback.
use std::{
    io,
    sync::{OnceLock, atomic::AtomicU32},
};
type Wait = unsafe extern "C" fn(*mut libc::c_void, u64, usize, u32, u32, u64) -> libc::c_int;
type Wake = unsafe extern "C" fn(*mut libc::c_void, usize, u32) -> libc::c_int;
struct Api {
    wait: Wait,
    wake: Wake,
}
fn api() -> Option<&'static Api> {
    static API: OnceLock<Option<Api>> = OnceLock::new();
    API.get_or_init(|| {
        // SAFETY: these NUL-terminated names designate the public libSystem
        // APIs in os/os_sync_wait_on_address.h. libSystem remains loaded.
        let (wait, wake) = unsafe {
            (
                libc::dlsym(
                    libc::RTLD_DEFAULT,
                    c"os_sync_wait_on_address_with_timeout".as_ptr(),
                ),
                libc::dlsym(libc::RTLD_DEFAULT, c"os_sync_wake_by_address_any".as_ptr()),
            )
        };
        if wait.is_null() || wake.is_null() {
            return None;
        }
        // SAFETY: both symbols were found and the function signatures match
        // Apple's public declarations, including u32 flags and os_clockid_t.
        Some(unsafe {
            Api {
                wait: std::mem::transmute::<*mut libc::c_void, Wait>(wait),
                wake: std::mem::transmute::<*mut libc::c_void, Wake>(wake),
            }
        })
    })
    .as_ref()
}
pub(super) fn available() -> bool {
    api().is_some()
}
pub(super) fn wait(phase: &AtomicU32, observed: u32) -> io::Result<()> {
    let Some(api) = api() else {
        // Only direct protocol diagnostics use this path. Production selects
        // its sleeping socket transport when public APIs are unavailable.
        std::thread::yield_now();
        return Ok(());
    };
    // SAFETY: phase is an aligned, live shared AtomicU32 for the entire call.
    // The OS atomically compares four bytes before sleeping; the SHARED flag
    // keys different process mappings by backing storage, not virtual address.
    let status = unsafe {
        (api.wait)(
            phase.as_ptr().cast(),
            u64::from(observed),
            size_of::<u32>(),
            libc::OS_SYNC_WAIT_ON_ADDRESS_SHARED,
            libc::OS_CLOCK_MACH_ABSOLUTE_TIME,
            1_000_000,
        )
    };
    let result = if status >= 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    };
    finish_wait(phase, observed, result, || {
        std::thread::sleep(std::time::Duration::from_millis(1));
    })
}
// This completes a wait attempt, never a controller decision. The caller
// rechecks its phase and peer before waiting again. The shared AtomicU32 is
// borrowed from our live, length-checked mapping; it is not an arbitrary address.
// Apple's API documents EFAULT and ENOMEM as possible transient failures for a
// valid address. Backoff retains the existing one-millisecond polling interval.
// BEGIN GENERATED WAIT RESULT
fn wait_immediate(code: Option<i32>) -> bool {
    matches!(code, Some(libc::EAGAIN | libc::EINTR | libc::ETIMEDOUT))
}
fn wait_pressure(code: Option<i32>) -> bool {
    matches!(code, Some(libc::EFAULT | libc::ENOMEM))
}
fn wait_backoff(pressure: bool, changed: bool) -> bool {
    pressure && !changed
}
#[cfg(test)]
const WAIT_ERROR_IDS: &[(i32, i32)] = &[
    (libc::EAGAIN, 35),
    (libc::EINTR, 4),
    (libc::ETIMEDOUT, 60),
    (libc::EFAULT, 14),
    (libc::ENOMEM, 12),
];
// END GENERATED WAIT RESULT
fn finish_wait(
    phase: &AtomicU32,
    observed: u32,
    result: io::Result<()>,
    backoff: impl FnOnce(),
) -> io::Result<()> {
    match result {
        Ok(()) => Ok(()),
        Err(error) => {
            let code = error.raw_os_error();
            if wait_immediate(code) {
                Ok(())
            } else if wait_pressure(code) {
                if wait_backoff(
                    true,
                    phase.load(std::sync::atomic::Ordering::Acquire) != observed,
                ) {
                    backoff();
                }
                Ok(())
            } else {
                Err(error)
            }
        }
    }
}
pub(super) fn wake(phase: &AtomicU32) {
    if let Some(api) = api() {
        // SAFETY: the live mapping remains borrowed and uses the same aligned
        // address, size and SHARED flag as wait. Wake is only a hint; the
        // one-millisecond wait bound still rechecks phase and peer liveness.
        unsafe {
            (api.wake)(
                phase.as_ptr().cast(),
                size_of::<u32>(),
                libc::OS_SYNC_WAKE_BY_ADDRESS_SHARED,
            );
        }
    }
}

#[cfg(test)]
#[path = "../tests/unit/process_checkpoint_darwin.rs"]
mod tests;
