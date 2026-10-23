//! Child-local resource checks with caller-owned publication authority.
use crate::control_state::State;
use gerbil_ascent::{Error, Result};
use std::{
    fs::{File, OpenOptions},
    os::fd::AsRawFd,
    path::Path,
    ptr::NonNull,
    sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, Ordering},
    time::Instant,
};
#[repr(C, align(64))]
struct Slot {
    closed: AtomicBool,
    canceled: AtomicBool,
    id: AtomicI64,
    work: AtomicU64,
    maximum: AtomicU64,
    deadline: AtomicU64,
    flags: AtomicU32,
    checkpoints: AtomicU64,
}
pub(crate) struct Shared(NonNull<Slot>);
// SAFETY: initialized, private, length-checked shared lock-free atomics. The
// child owns work/suspension; the parent publishes acceptance only while that
// child waits for the original controller's publication reply. No VM lock is shared.
unsafe impl Send for Shared {}
unsafe impl Sync for Shared {}
impl Shared {
    pub(crate) fn create(path: &Path) -> std::io::Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(path)?;
        file.set_len(size_of::<Slot>() as u64)?;
        let mapping = Self::map(&file)?;
        // SAFETY: this new private file has not been published to the child.
        unsafe {
            mapping.0.as_ptr().write(Slot {
                closed: AtomicBool::new(true),
                canceled: AtomicBool::new(false),
                id: AtomicI64::new(0),
                work: AtomicU64::new(0),
                maximum: AtomicU64::new(0),
                deadline: AtomicU64::new(0),
                flags: AtomicU32::new(0),
                checkpoints: AtomicU64::new(0),
            });
        }
        Ok(mapping)
    }
    pub(crate) fn open(path: &Path) -> std::io::Result<Self> {
        let file = OpenOptions::new().read(true).write(true).open(path)?;
        if file.metadata()?.len() != size_of::<Slot>() as u64 {
            return Err(std::io::Error::other("invalid admission mapping length"));
        }
        Self::map(&file)
    }
    fn map(file: &File) -> std::io::Result<Self> {
        // SAFETY: live length-checked backing file; mmap owns its pages after close/unlink.
        let ptr = unsafe {
            libc::mmap(
                std::ptr::null_mut(),
                size_of::<Slot>(),
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                file.as_raw_fd(),
                0,
            )
        };
        if ptr == libc::MAP_FAILED {
            return Err(std::io::Error::last_os_error());
        }
        NonNull::new(ptr.cast())
            .map(Self)
            .ok_or_else(|| std::io::Error::other("null admission mapping"))
    }
    fn slot(&self) -> &Slot {
        // SAFETY: the initialized mapping stays alive for this borrow.
        unsafe { self.0.as_ref() }
    }
    pub(crate) fn begin(&self, id: i64, state: State, deadline: Instant) -> Result<()> {
        let clock = clock_ns()?;
        // Read the common monotonic clock before Instant: conversion cannot extend the limit.
        let remaining = deadline.saturating_duration_since(Instant::now());
        let deadline = clock
            .checked_add(u64::try_from(remaining.as_nanos()).map_err(|_| Error::Timeout)?)
            .ok_or(Error::Timeout)?;
        let s = self.slot();
        if !s.closed.load(Ordering::Acquire) {
            return Err(Error::Closed);
        }
        s.id.store(id, Ordering::Relaxed);
        self.store_state(state);
        s.deadline.store(deadline, Ordering::Relaxed);
        s.canceled.store(false, Ordering::Relaxed);
        s.checkpoints.store(0, Ordering::Relaxed);
        s.closed.store(false, Ordering::Release);
        Ok(())
    }
    fn store_state(&self, state: State) {
        let s = self.slot();
        s.work.store(state.work as u64, Ordering::Relaxed);
        s.maximum.store(state.maximum as u64, Ordering::Relaxed);
        s.flags.store(
            u32::from(state.accepted) | (u32::from(state.suspended) << 1),
            Ordering::Release,
        );
    }
    pub(crate) fn cancel(&self, id: i64) {
        if self.slot().id.load(Ordering::Acquire) == id {
            self.slot().canceled.store(true, Ordering::Release);
        }
    }
    pub(crate) fn expire(&self, id: i64) {
        if self.slot().id.load(Ordering::Acquire) == id {
            self.slot().deadline.store(0, Ordering::Release);
        }
    }
    pub(crate) fn snapshot(&self, id: i64) -> Result<State> {
        let s = self.slot();
        if s.closed.load(Ordering::Acquire) || s.id.load(Ordering::Relaxed) != id {
            return Err(Error::Closed);
        }
        let flags = s.flags.load(Ordering::Acquire);
        Ok(State {
            work: usize::try_from(s.work.load(Ordering::Relaxed)).map_err(|_| Error::Closed)?,
            maximum: usize::try_from(s.maximum.load(Ordering::Relaxed))
                .map_err(|_| Error::Closed)?,
            accepted: flags & 1 != 0,
            suspended: flags & 2 != 0,
        })
    }
    fn interruption(&self, accepted: bool) -> i32 {
        let s = self.slot();
        if accepted {
            0
        } else if s.canceled.load(Ordering::Acquire) {
            1
        } else {
            match clock_ns() {
                Ok(now) if now < s.deadline.load(Ordering::Acquire) => 0,
                Ok(_) => 2,
                Err(_) => 5,
            }
        }
    }
    pub(crate) fn checkpoint(&self, id: i64, work: i64) -> i32 {
        let Ok(mut state) = self.snapshot(id) else {
            return 5;
        };
        self.slot().checkpoints.fetch_add(1, Ordering::Relaxed);
        let accepted = state.accepted;
        let code = state.advance(work, |accepted| self.interruption(accepted));
        if !accepted && state.accepted {
            // 4 stays inside Rust. The caller must run its original controller
            // before Scheme can observe successful publication. A delayed cancel
            // wakeup is therefore never sufficient authority to commit.
            return 4;
        }
        self.store_state(state);
        code
    }
    pub(crate) fn publish(&self, id: i64, state: State) -> Result<()> {
        self.snapshot(id)?;
        self.store_state(state);
        Ok(())
    }
    pub(crate) fn finish(&self, id: i64) -> Result<State> {
        let state = self.snapshot(id)?;
        self.close();
        Ok(state)
    }
    pub(crate) fn close(&self) {
        self.slot().closed.store(true, Ordering::Release);
    }
    pub(crate) fn checkpoints(&self) -> u64 {
        self.slot().checkpoints.load(Ordering::Acquire)
    }
}
impl Drop for Shared {
    fn drop(&mut self) {
        // SAFETY: no accessor outlives this process's mapping owner.
        unsafe {
            libc::munmap(self.0.as_ptr().cast(), size_of::<Slot>());
        }
    }
}
fn clock_ns() -> Result<u64> {
    #[cfg(target_os = "macos")]
    const CLOCK: libc::clockid_t = libc::CLOCK_UPTIME_RAW;
    #[cfg(not(target_os = "macos"))]
    const CLOCK: libc::clockid_t = libc::CLOCK_MONOTONIC;
    let mut time = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    // SAFETY: one writable output; this is the platform Instant monotonic clock.
    if unsafe { libc::clock_gettime(CLOCK, &raw mut time) } != 0 {
        return Err(Error::Closed);
    }
    u64::try_from(time.tv_sec)
        .ok()
        .and_then(|s| s.checked_mul(1_000_000_000))
        .and_then(|s| {
            u64::try_from(time.tv_nsec)
                .ok()
                .and_then(|n| s.checked_add(n))
        })
        .ok_or(Error::Closed)
}
#[cfg(test)]
#[path = "../tests/unit/process_control.rs"]
mod tests;
