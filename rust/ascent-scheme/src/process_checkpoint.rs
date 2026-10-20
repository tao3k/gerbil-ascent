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
const IDLE: u32 = 0;
const REQUEST: u32 = 1;
const DECISION: u32 = 2;
const COMPLETE: u32 = 3;
#[repr(C, align(64))]
struct Slot {
    phase: AtomicU32,
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
    }
    pub(crate) fn complete(&self) {
        self.slot().phase.store(COMPLETE, Ordering::Release);
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
        slot.phase.store(REQUEST, Ordering::Release);
        let mut waiting = Wait::default();
        loop {
            if slot.phase.load(Ordering::Acquire) == DECISION {
                let code = slot.code.load(Ordering::Relaxed);
                slot.phase.store(IDLE, Ordering::Release);
                return Ok(code);
            }
            waiting.poll(&mut closed)?;
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
                waiting.poll(&mut closed)?;
                continue;
            }
            match slot.phase.load(Ordering::Acquire) {
                REQUEST => {
                    let code = decide(
                        slot.id.load(Ordering::Relaxed),
                        slot.work.load(Ordering::Relaxed),
                    );
                    slot.code.store(code, Ordering::Relaxed);
                    slot.phase.store(DECISION, Ordering::Release);
                }
                COMPLETE => return Ok(()),
                _ => waiting.poll(&mut closed)?,
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
    fn poll(&mut self, closed: &mut impl FnMut() -> io::Result<bool>) -> io::Result<()> {
        self.0 = self.0.wrapping_add(1);
        if self.0.is_multiple_of(1024) && closed()? {
            return Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "checkpoint peer exited",
            ));
        }
        // No sleeping VM or idle-owner polling: this exchange exists only while
        // a native request is executing. Yield lets oversubscribed owners run.
        if self.0.is_multiple_of(32) {
            std::thread::yield_now();
        } else {
            std::hint::spin_loop();
        }
        Ok(())
    }
}
#[cfg(test)]
#[path = "../tests/unit/process_checkpoint.rs"]
mod tests;
