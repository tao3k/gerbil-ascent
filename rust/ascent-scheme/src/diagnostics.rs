//! Opt-in timing only; never changes authority, deadlines or request contents.
use gerbil_ascent::Result;
use std::{io::Write, sync::OnceLock, time::Instant};

pub(crate) fn enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var_os("ASCENT_PROCESS_TRACE").is_some())
}

pub(crate) struct Trace {
    enabled: bool,
    owner: u64,
}
impl Trace {
    pub(crate) fn new(owner: u64) -> Self {
        Self {
            enabled: enabled(),
            owner,
        }
    }
    pub(crate) fn measure<T>(
        &self,
        phase: &str,
        operation: impl FnOnce() -> Result<T>,
    ) -> Result<T> {
        let started = self.enabled.then(Instant::now);
        let result = operation();
        if let Some(started) = started {
            crate::diagnostics::emit(format!(
                "ASCENT-PROOF-PHASE pid={} owner={} phase={} elapsed_us={} success={}",
                std::process::id(),
                self.owner,
                phase,
                started.elapsed().as_micros(),
                result.is_ok()
            ));
        }
        result
    }
}

// The frozen bridge already exports these owner-local qualification counters.
unsafe extern "C" {
    fn gerbil_scheme_rust_objects_usage(gc: *mut f64, os: *mut u64) -> i32;
}
fn usage(_owner: &gerbil_scheme::GerbilRuntime) -> Option<([f64; 4], [u64; 4])> {
    let mut gc = [0.0; 4];
    let mut os = [0; 4];
    // SAFETY: a live, non-Send runtime is borrowed on its sole VM owner thread;
    // the frozen ABI writes exactly four disjoint entries into each array.
    let status = unsafe { gerbil_scheme_rust_objects_usage(gc.as_mut_ptr(), os.as_mut_ptr()) };
    (status == 0).then_some((gc, os))
}

pub(crate) struct Request<'a> {
    owner: &'a gerbil_scheme::GerbilRuntime,
    before: Option<([f64; 4], [u64; 4])>,
    started: Instant,
    operation: String,
}
impl<'a> Request<'a> {
    pub(crate) fn start(
        owner: &'a gerbil_scheme::GerbilRuntime,
        request: &gerbil_ascent::Data,
    ) -> Option<Self> {
        enabled().then(|| Self {
            owner,
            before: usage(owner),
            started: Instant::now(),
            operation: request
                .get("operation")
                .and_then(|v| v.text().ok())
                .unwrap_or("-")
                .to_owned(),
        })
    }
}
impl Drop for Request<'_> {
    fn drop(&mut self) {
        if let Some(((before_gc, before_os), (gc, os))) = self.before.zip(usage(self.owner)) {
            crate::diagnostics::emit(format!(
                "ASCENT-VM-PHASE pid={} operation={} elapsed_us={} cpu_us={} gc_count={} gc_cpu_us={} gc_wall_us={} voluntary_switches={} involuntary_switches={} heap_capacity={} rss_high_water={}",
                std::process::id(),
                self.operation,
                self.started.elapsed().as_micros(),
                os[0].saturating_sub(before_os[0]) / 1000,
                gc[0] - before_gc[0],
                (gc[1] - before_gc[1]) * 1e6,
                (gc[2] - before_gc[2]) * 1e6,
                os[2].saturating_sub(before_os[2]),
                os[3].saturating_sub(before_os[3]),
                gc[3],
                os[1]
            ));
        } else {
            crate::diagnostics::emit(format!(
                "ASCENT-VM-PHASE pid={} operation={} usage=unavailable",
                std::process::id(),
                self.operation
            ));
        }
    }
}

// One small write prevents Rust's fragmented formatting from interleaving fields
// with the other VM processes sharing the qualification stderr pipe.
pub(crate) fn emit(mut line: String) {
    line.push('\n');
    let _ = std::io::stderr().write_all(line.as_bytes());
}
