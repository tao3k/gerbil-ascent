//! One process with independent, single-thread VM owners supplied by the upstream bridge.
use super::{InstancePackage, lifecycle, values};
use crate::{Control, ProcessReceipt, ProcessStatistics};
use gerbil_ascent::{Cancellation, Data, Error, Limits, Result};
use gerbil_scheme::instances::{InstanceDispatcher, InstanceError, NativeSession};
use std::{
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    },
    time::{Duration, Instant},
};

pub(super) fn bridge_error(error: InstanceError) -> Error {
    match error {
        InstanceError::Closed => Error::Closed,
        InstanceError::Timeout => Error::Timeout,
        InstanceError::Cancelled => Error::Canceled,
        other => crate::failure(&other.to_string()),
    }
}
struct Pool {
    runtime: Mutex<gerbil_scheme::instances::InstancePool>,
    dispatcher: InstanceDispatcher,
    active: AtomicUsize,
    maximum: AtomicUsize,
    source_library: std::path::PathBuf,
}
#[derive(Default)]
struct Counters {
    closed: AtomicBool,
    calls: AtomicU64,
    queue_ns: AtomicU64,
    service_ns: AtomicU64,
    checkpoints: Arc<AtomicU64>,
}
/// An affinity lease into one independent VM. No root or VM pointer crosses a thread.
#[derive(Clone)]
pub struct InstanceOwner {
    pool: Arc<Pool>,
    index: usize,
    receipt: ProcessReceipt,
    counters: Arc<Counters>,
    retired: Arc<Mutex<Vec<Data>>>,
    parent: u32,
}
/// Explicit alternative to a process-per-VM pool. Never selected as a fallback.
pub struct InstancePool {
    owners: Vec<InstanceOwner>,
}
impl InstancePool {
    /// Load the library-built image and initialize each upstream owner with one processor.
    /// # Errors
    /// Rejects unsupported native setup, invalid counts and incomplete single-thread initialization.
    pub fn new(owners: usize) -> Result<Self> {
        Self::from_package(owners, env!("ASCENT_INSTANCE_PACKAGE"))
    }
    /// Open an installed package matching this library's compiled resource manifest.
    /// # Errors
    /// Rejects missing, changed or aliased assets before any native VM admission.
    pub fn from_package(owners: usize, root: impl AsRef<std::path::Path>) -> Result<Self> {
        if owners == 0 || owners > 64 {
            return Err(crate::failure("instance VM count must be in 1..=64"));
        }
        let (runtime, source_library) = lifecycle::start(owners, root.as_ref())?;
        Self::from_runtime(owners, runtime, source_library)
    }
    /// Start independent VMs from caller-owned resources, with fresh verification.
    /// # Errors
    /// Rejects invalid counts, changed snapshot bytes and incomplete VM startup.
    pub fn from_snapshot(owners: usize, package: &InstancePackage) -> Result<Self> {
        if owners == 0 || owners > 64 {
            return Err(crate::failure("instance VM count must be in 1..=64"));
        }
        let (runtime, source_library) = lifecycle::start_snapshot(owners, package)?;
        Self::from_runtime(owners, runtime, source_library)
    }
    fn from_runtime(
        owners: usize,
        runtime: gerbil_scheme::instances::InstancePool,
        source_library: std::path::PathBuf,
    ) -> Result<Self> {
        let dispatcher = runtime.dispatcher();
        let pool = Arc::new(Pool {
            runtime: Mutex::new(runtime),
            dispatcher,
            active: AtomicUsize::new(0),
            maximum: AtomicUsize::new(0),
            source_library,
        });
        let mut population = Vec::with_capacity(owners);
        for index in 0..owners {
            let domain = crate::service::reserve_domain()?;
            let owner = InstanceOwner {
                pool: pool.clone(),
                index,
                receipt: ProcessReceipt {
                    pid: std::process::id(),
                    domain,
                    processors: 1,
                },
                counters: Arc::default(),
                retired: Arc::default(),
                parent: std::process::id(),
            };
            lifecycle::bind(
                &owner.pool.dispatcher,
                owner.index,
                &owner.pool.source_library,
            )?;
            owner.call(Data::object([
                ("operation", Data::from("process-domain")),
                ("domain", Data::from(domain)),
            ]))?;
            population.push(owner);
        }
        Ok(Self { owners: population })
    }
    /// Select a fixed owner; all opaque application handles retain this affinity.
    /// # Errors
    /// Rejects indices outside the fixed population.
    pub fn owner(&self, index: usize) -> Result<InstanceOwner> {
        self.owners.get(index).cloned().ok_or(Error::Closed)
    }
    #[must_use]
    pub fn receipts(&self) -> Vec<ProcessReceipt> {
        self.owners.iter().map(InstanceOwner::receipt).collect()
    }
    /// Reset only observational counters while callers are idle.
    pub fn reset_statistics(&self) {
        for owner in &self.owners {
            for value in [
                &owner.counters.calls,
                &owner.counters.queue_ns,
                &owner.counters.service_ns,
                &owner.counters.checkpoints,
            ] {
                value.store(0, Ordering::Relaxed);
            }
        }
        if let Some(owner) = self.owners.first() {
            owner
                .pool
                .maximum
                .store(owner.pool.active.load(Ordering::Acquire), Ordering::Release);
        }
    }
    /// Close admission and observe native quiescence; pending owners remain live.
    /// # Errors
    /// Reports poisoned lifecycle state; never reports a pending VM as destroyed.
    pub fn shutdown(&self, timeout: Duration) -> Result<gerbil_scheme::instances::ShutdownReceipt> {
        self.owners[0]
            .pool
            .runtime
            .lock()
            .map_err(|_| Error::Closed)
            .map(|mut p| p.shutdown(timeout))
    }
}
struct Delivery {
    counters: Arc<Counters>,
    result: Option<Result<Data>>,
    request: Arc<Data>,
    retired: Arc<Mutex<Vec<Data>>>,
}
impl Delivery {
    fn take(mut self) -> Result<Data> {
        self.result.take().ok_or(Error::Closed)?
    }
}
impl Drop for Delivery {
    fn drop(&mut self) {
        // Upstream validates root balance before publishing. If that publication
        // is abandoned, schedule application-handle retirement on the same VM.
        // Every subsequent call drains retirements before admission/evaluation;
        // final pool cleanup releases the entire Scheme registry if no call follows.
        if let Some(Ok(value)) = self.result.take()
            && let Some(cleanup) = crate::service::abandoned_request(&self.request, &value)
        {
            if let Ok(mut retired) = self.retired.lock() {
                retired.push(cleanup);
            } else {
                self.counters.closed.store(true, Ordering::Release);
            }
        }
    }
}
struct Active(Arc<Pool>);
impl Drop for Active {
    fn drop(&mut self) {
        self.0.active.fetch_sub(1, Ordering::AcqRel);
    }
}
impl InstanceOwner {
    /// Enter a business call with the original caller cancellation and deadline.
    /// Logical fact ceilings remain in the typed request/session contract.
    /// # Errors
    /// Rejects conflicting control authority and preserves original typed failures.
    pub fn call_cancelable(
        &self,
        request: Data,
        timeout: Duration,
        cancellation: &Cancellation,
    ) -> Result<Data> {
        let (_control, request) = crate::controlled_request(request, timeout, cancellation)?;
        self.call(request)
    }
    /// Call the same production Scheme ABI on the selected upstream owner.
    /// # Errors
    /// Preserves cancellation/deadline/work/fact errors and rejects inherited owners after fork.
    pub fn call(&self, request: Data) -> Result<Data> {
        if self.counters.closed.load(Ordering::Acquire) {
            return Err(Error::Closed);
        }
        if self.parent != std::process::id() {
            return Err(crate::failure(
                "inherited instance owner cannot enter after fork",
            ));
        }
        let supplied_control = Control::from_request(&request)?;
        let Data::Map(mut request) = request else {
            return Err(crate::failure("object required"));
        };
        let control = if let Some(control) = supplied_control {
            control
        } else {
            let control = Control::new(
                &Limits {
                    max_states: usize::MAX,
                    max_facts: usize::MAX,
                    ..Limits::default()
                },
                &Cancellation::default(),
            )?;
            request.insert("executionControl".into(), control.id());
            control
        };
        let request = Arc::new(Data::Map(request));
        let queued = Instant::now();
        let ticket = loop {
            control.check()?;
            let owner = self.clone();
            let request = request.clone();
            let control = control.clone();
            match self
                .pool
                .dispatcher
                .submit_native_on(self.index, move |vm| {
                    owner.execute(vm, request, &control, queued)
                }) {
                Ok(ticket) => break ticket,
                Err(InstanceError::QueueFull) => {
                    std::thread::park_timeout(Duration::from_millis(1));
                }
                Err(error) => return Err(bridge_error(error)),
            }
        };
        loop {
            match ticket.wait(Duration::from_millis(1)) {
                Ok(value) => return value.take(),
                Err(InstanceError::Timeout) => control.check()?,
                Err(error) => return Err(bridge_error(error)),
            }
        }
    }
    fn execute(
        &self,
        vm: &NativeSession<'_>,
        request: Arc<Data>,
        control: &Control,
        queued: Instant,
    ) -> std::result::Result<Delivery, InstanceError> {
        if self.counters.closed.load(Ordering::Acquire) {
            return Err(InstanceError::Closed);
        }
        let pending = std::mem::take(&mut *self.retired.lock().map_err(|_| InstanceError::Closed)?);
        for cleanup in pending {
            if let Err(error) = values::call(vm, &cleanup) {
                // Lost retirement receipts forbid further admission to this owner.
                self.counters.closed.store(true, Ordering::Release);
                return Err(InstanceError::Scheme(error.to_string()));
            }
        }
        let admitted = control.check();
        self.counters
            .queue_ns
            .fetch_add(nanos(queued.elapsed()), Ordering::Relaxed);
        let started = Instant::now();
        let active = self.pool.active.fetch_add(1, Ordering::AcqRel) + 1;
        self.pool.maximum.fetch_max(active, Ordering::Relaxed);
        let _active = Active(self.pool.clone());
        let result = admitted.and_then(|()| {
            let _control = control.enter(self.counters.checkpoints.clone());
            values::call(vm, &request)
        });
        self.counters.calls.fetch_add(1, Ordering::Relaxed);
        self.counters
            .service_ns
            .fetch_add(nanos(started.elapsed()), Ordering::Relaxed);
        Ok(Delivery {
            counters: self.counters.clone(),
            result: Some(result),
            request,
            retired: self.retired.clone(),
        })
    }
    #[must_use]
    pub fn receipt(&self) -> ProcessReceipt {
        self.receipt.clone()
    }
    #[must_use]
    pub fn statistics(&self) -> ProcessStatistics {
        ProcessStatistics {
            calls: self.counters.calls.load(Ordering::Relaxed),
            queue_ns: self.counters.queue_ns.load(Ordering::Relaxed),
            service_ns: self.counters.service_ns.load(Ordering::Relaxed),
            checkpoints: self.counters.checkpoints.load(Ordering::Relaxed),
            shared_checkpoints: 0,
            maximum_overlapping_calls: self.pool.maximum.load(Ordering::Relaxed),
        }
    }
}
fn nanos(value: Duration) -> u64 {
    u64::try_from(value.as_nanos()).unwrap_or(u64::MAX)
}
