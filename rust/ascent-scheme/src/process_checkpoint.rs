//! One synchronous checkpoint exchange without a socket wakeup per callback.
//! The parent still executes the original controller for every checkpoint.
use std::{
    fs::{File, OpenOptions},
    io,
    os::fd::AsRawFd,
    path::Path,
    ptr::NonNull,
    sync::atomic::{AtomicI32, AtomicI64, AtomicU32, Ordering},
};
#[cfg(target_os = "macos")]
#[path = "process_checkpoint_darwin.rs"]
mod darwin;
pub(crate) fn shared_transport() -> Option<&'static str> {
    #[cfg(target_os = "linux")]
    let (available, name) = (true, "shared-futex");
    #[cfg(target_os = "macos")]
    let (available, name) = (darwin::available(), "shared-darwin-wait");
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let (available, name) = (false, "");
    available.then_some(name)
}
const IDLE: u32 = 0;
const REQUEST: u32 = 1;
const DECISION: u32 = 2;
const COMPLETE: u32 = 3;
// BEGIN GENERATED CHECKPOINT FLAGS
const PARENT: u32 = 1;
const CHILD: u32 = 2;
// END GENERATED CHECKPOINT FLAGS
#[repr(C, align(64))]
struct Slot {
    phase: AtomicU32,
    sleeping: AtomicU32,
    generation: AtomicI64,
    code: AtomicI32,
    id: AtomicI64,
    work: AtomicI64,
}
pub(crate) struct Checkpoints(NonNull<Slot>);
// SAFETY: all shared fields are native lock-free atomics on the supported
// 64-bit Unix targets. The mapping stays alive while an accessor owns &self.
unsafe impl Send for Checkpoints {}
unsafe impl Sync for Checkpoints {}
impl Checkpoints {
    pub(crate) fn create(path: &Path) -> io::Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .open(path)?;
        file.set_len(u64::try_from(size_of::<Slot>()).map_err(io::Error::other)?)?;
        let slot = Self::map(&file)?;
        // SAFETY: the private file has not been shared or opened by the child;
        // mmap provides page alignment and enough writable storage for Slot.
        unsafe {
            slot.0.as_ptr().write(Slot {
                phase: AtomicU32::new(IDLE),
                sleeping: AtomicU32::new(0),
                generation: AtomicI64::new(0),
                code: AtomicI32::new(0),
                id: AtomicI64::new(0),
                work: AtomicI64::new(0),
            });
        }
        Ok(slot)
    }
    pub(crate) fn open(path: &Path) -> io::Result<Self> {
        let file = OpenOptions::new().read(true).write(true).open(path)?;
        if file.metadata()?.len() != u64::try_from(size_of::<Slot>()).map_err(io::Error::other)? {
            return Err(io::Error::other("invalid checkpoint mapping length"));
        }
        Self::map(&file)
    }
    fn map(file: &File) -> io::Result<Self> {
        // SAFETY: fd owns an initialized, length-checked private file. MAP_SHARED
        // keeps the backing storage alive after close/unlink. No Rust references
        // exist before successful mapping; only atomics are accessed thereafter.
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
            return Err(io::Error::last_os_error());
        }
        NonNull::new(ptr.cast())
            .map(Self)
            .ok_or_else(|| io::Error::other("null checkpoint mapping"))
    }
    fn slot(&self) -> &Slot {
        // SAFETY: construction validates the initialized mapping; Drop cannot
        // unmap it while a borrow is alive. Other processes only use atomics.
        unsafe { self.0.as_ref() }
    }
    pub(crate) fn begin(&self, generation: i64) {
        self.slot().phase.store(IDLE, Ordering::Release);
        // The parent must acquire this new request identity before looking at
        // phase. Otherwise COMPLETE from the previous ABI call can be mistaken
        // for completion of this call (the phase values alone have an ABA gap).
        self.slot().generation.store(generation, Ordering::Release);
        wake(&self.slot().phase);
    }
    pub(crate) fn complete(&self) {
        self.slot().phase.store(COMPLETE, Ordering::Release);
        wake(&self.slot().phase);
    }
    pub(crate) fn request(
        &self,
        id: i64,
        work: i64,
        mut closed: impl FnMut() -> io::Result<bool>,
    ) -> io::Result<i32> {
        let slot = self.slot();
        slot.id.store(id, Ordering::Relaxed);
        slot.work.store(work, Ordering::Relaxed);
        publish(slot, REQUEST, PARENT);
        let mut waiting = Wait::default();
        loop {
            let phase = slot.phase.load(Ordering::Acquire);
            if phase == DECISION {
                let code = slot.code.load(Ordering::Relaxed);
                slot.phase.store(IDLE, Ordering::Release);
                return Ok(code);
            }
            waiting.poll(&mut closed, slot, phase, CHILD)?;
        }
    }
    pub(crate) fn serve(
        &self,
        generation: i64,
        mut decide: impl FnMut(i64, i64) -> i32,
        mut closed: impl FnMut() -> io::Result<bool>,
    ) -> io::Result<()> {
        let slot = self.slot();
        let mut waiting = Wait::default();
        loop {
            if slot.generation.load(Ordering::Acquire) != generation {
                let phase = slot.phase.load(Ordering::Acquire);
                if slot.generation.load(Ordering::Acquire) != generation {
                    waiting.poll(&mut closed, slot, phase, PARENT)?;
                }
                continue;
            }
            match slot.phase.load(Ordering::Acquire) {
                REQUEST => {
                    let code = decide(
                        slot.id.load(Ordering::Relaxed),
                        slot.work.load(Ordering::Relaxed),
                    );
                    slot.code.store(code, Ordering::Relaxed);
                    publish(slot, DECISION, CHILD);
                    #[cfg(any(target_os = "linux", target_os = "macos"))]
                    {
                        waiting = Wait::default();
                    }
                }
                COMPLETE => return Ok(()),
                phase => waiting.poll(&mut closed, slot, phase, PARENT)?,
            }
        }
    }
}
impl Drop for Checkpoints {
    fn drop(&mut self) {
        // SAFETY: this is exactly the address/length from mmap, all local borrows
        // ended; the other process owns its independent mapping lifetime.
        unsafe {
            libc::munmap(self.0.as_ptr().cast(), size_of::<Slot>());
        }
    }
}
#[derive(Default)]
struct Wait(u32);
impl Wait {
    fn poll(
        &mut self,
        closed: &mut impl FnMut() -> io::Result<bool>,
        slot: &Slot,
        observed: u32,
        waiter: u32,
    ) -> io::Result<()> {
        self.0 = self.0.wrapping_add(1);
        #[cfg(any(target_os = "linux", target_os = "macos"))]
        {
            if self.0 >= 32 {
                if closed()? {
                    return Err(io::Error::new(
                        io::ErrorKind::BrokenPipe,
                        "checkpoint peer exited",
                    ));
                }
                return registered_wait(slot, observed, waiter);
            }
            std::hint::spin_loop();
        }
        #[cfg(not(any(target_os = "linux", target_os = "macos")))]
        {
            let _ = (slot, observed, waiter);
            if self.0.is_multiple_of(1024) && closed()? {
                return Err(io::Error::new(
                    io::ErrorKind::BrokenPipe,
                    "checkpoint peer exited",
                ));
            }
            if self.0.is_multiple_of(32) {
                std::thread::yield_now();
            } else {
                std::hint::spin_loop();
            }
        }
        Ok(())
    }
}

// FUTEX_PRIVATE_FLAG would be incorrect: the two processes map the same backing
// file at independent virtual addresses. The kernel keys this wait by shared
// backing storage. The atomic comparison prevents a lost wake between observing
// a phase and sleeping; EINTR/spurious wakeups always recheck the protocol.
#[cfg(target_os = "linux")]
fn wait(phase: &AtomicU32, observed: u32) -> io::Result<()> {
    let timeout = libc::timespec {
        tv_sec: 0,
        tv_nsec: 1_000_000,
    };
    // SAFETY: phase is a valid aligned atomic in a live shared mapping. The
    // kernel only reads it; the borrowed relative timespec lives through syscall.
    let status = unsafe {
        libc::syscall(
            libc::SYS_futex,
            phase.as_ptr(),
            libc::FUTEX_WAIT,
            observed,
            &raw const timeout,
        )
    };
    if status >= 0 {
        return Ok(());
    }
    let error = io::Error::last_os_error();
    match error.raw_os_error() {
        Some(libc::EAGAIN | libc::EINTR | libc::ETIMEDOUT) => Ok(()),
        _ => Err(error),
    }
}
#[cfg(target_os = "macos")]
fn wait(phase: &AtomicU32, observed: u32) -> io::Result<()> {
    darwin::wait(phase, observed)
}
// BEGIN GENERATED CHECKPOINT WAIT
#[cfg(any(target_os = "linux", target_os = "macos"))]
fn registered_wait(slot: &Slot, observed: u32, waiter: u32) -> io::Result<()> {
    // Register before rechecking phase; publication and registration use one
    // sequentially consistent order across both atomics.
    slot.sleeping.fetch_or(waiter, Ordering::SeqCst);
    let result = if slot.phase.load(Ordering::SeqCst) == observed {
        wait(&slot.phase, observed)
    } else {
        Ok(())
    };
    slot.sleeping.fetch_and(!waiter, Ordering::SeqCst);
    result
}
// END GENERATED CHECKPOINT WAIT
// BEGIN GENERATED CHECKPOINT PUBLISH
fn publish(slot: &Slot, phase: u32, peer: u32) {
    slot.phase.store(phase, Ordering::SeqCst);
    if slot.sleeping.load(Ordering::SeqCst) & peer != 0 {
        wake(&slot.phase);
    }
}
// END GENERATED CHECKPOINT PUBLISH
fn wake(phase: &AtomicU32) {
    #[cfg(target_os = "linux")]
    // SAFETY: phase is borrowed from the live shared mapping; WAKE does not
    // access any payload. Wake is a scheduling hint, not an execution decision;
    // even a missed hint is bounded by wait's peer-liveness interval.
    unsafe {
        libc::syscall(libc::SYS_futex, phase.as_ptr(), libc::FUTEX_WAKE, 1);
    }
    #[cfg(target_os = "macos")]
    darwin::wake(phase);
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let _ = phase;
}

#[cfg(test)]
#[path = "../tests/unit/process_checkpoint.rs"]
mod tests;
