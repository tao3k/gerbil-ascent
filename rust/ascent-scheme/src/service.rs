//! Persistent exec-isolated Scheme owners. One upstream VM and thread per child.
use crate::{
    control::Control,
    process_wire::{self, Frame},
};
use gerbil_ascent::{Data, Error, Result};
use std::{
    ffi::OsString,
    os::unix::net::{UnixListener, UnixStream},
    path::PathBuf,
    process::{Child, Command, Stdio},
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicU64, AtomicUsize, Ordering},
        mpsc,
    },
    thread,
    time::{Duration, Instant},
};
static PROGRAM: OnceLock<WorkerProgram> = OnceLock::new();
static DOMAIN: AtomicU64 = AtomicU64::new(1);
/// Installed executable entry, shared by Rust and Rust-generated Python bindings.
#[derive(Clone)]
pub struct WorkerProgram {
    executable: PathBuf,
    arguments: Vec<OsString>,
}
impl WorkerProgram {
    #[must_use]
    pub fn new(executable: impl Into<PathBuf>, arguments: Vec<OsString>) -> Self {
        Self {
            executable: executable.into(),
            arguments,
        }
    }
    fn discover() -> Result<Self> {
        if let Some(program) = PROGRAM.get() {
            return Ok(program.clone());
        }
        if let Some(path) = std::env::var_os("ASCENT_SCHEME_WORKER") {
            return Ok(Self::new(path, vec![]));
        }
        let executable = std::env::current_exe().map_err(io_error)?;
        let directory = executable.parent().ok_or(Error::Closed)?;
        for candidate in [
            directory.join("ascent-scheme-worker"),
            directory
                .parent()
                .unwrap_or(directory)
                .join("ascent-scheme-worker"),
        ] {
            if candidate.is_file() {
                return Ok(Self::new(candidate, vec![]));
            }
        }
        Err(crate::failure(
            "install ascent-scheme-worker or configure the Rust/PyO3 worker program",
        ))
    }
}
/// Set the child entry before first Scheme use. Does not initialize a VM.
/// # Errors
/// Rejects conflicting configuration after a program has already been selected.
pub fn configure_worker(program: WorkerProgram) -> Result<()> {
    PROGRAM
        .set(program)
        .map_err(|_| crate::failure("worker program already configured"))
}
#[derive(Default)]
struct Activity {
    active: AtomicUsize,
    maximum: AtomicUsize,
}
#[derive(Default)]
struct Counters {
    calls: AtomicU64,
    queue_ns: AtomicU64,
    service_ns: AtomicU64,
    checkpoints: AtomicU64,
}
/// Observed process identity and actual VM processor population.
#[derive(Clone, Debug)]
pub struct ProcessReceipt {
    pub pid: u32,
    pub domain: u64,
    pub processors: u32,
}
/// Cumulative diagnostics, not a completion or provenance authority.
#[derive(Clone, Debug)]
pub struct ProcessStatistics {
    pub calls: u64,
    pub queue_ns: u64,
    pub service_ns: u64,
    pub checkpoints: u64,
    pub maximum_overlapping_calls: usize,
}
struct Call {
    request: Data,
    control: Option<Control>,
    queued: Instant,
    reply: mpsc::SyncSender<Result<Data>>,
}
struct Worker {
    parent: u32,
    sender: Option<mpsc::SyncSender<Call>>,
    child: Arc<Mutex<Child>>,
    thread: Option<thread::JoinHandle<()>>,
    done: mpsc::Receiver<()>,
}
impl Drop for Worker {
    fn drop(&mut self) {
        if self.parent != std::process::id() {
            return;
        }
        self.sender.take();
        if self.done.recv_timeout(Duration::from_secs(2)).is_err()
            && let Ok(mut child) = self.child.lock()
        {
            eprintln!(
                "ASCENT-PROCESS-FORCED-STOP pid={} reason=owner-shutdown-timeout",
                child.id()
            );
            let _ = child.kill();
        }
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}
/// An affinity lease; cloned engines retain the same process and opaque values.
#[derive(Clone)]
pub struct ProcessOwner {
    worker: Arc<Mutex<Worker>>,
    parent: u32,
    receipt: ProcessReceipt,
    counters: Arc<Counters>,
    activity: Arc<Activity>,
}
impl ProcessOwner {
    /// Call the production typed Scheme ABI on this resident owner.
    /// # Errors
    /// Preserves native errors, cancellation and control budgets. Dead workers
    /// are revoked, never silently restarted with recycled native handles.
    pub fn call(&self, request: Data) -> Result<Data> {
        if self.parent != std::process::id() {
            return Err(crate::failure(
                "inherited process owner cannot enter after fork",
            ));
        }
        let sender = self
            .worker
            .lock()
            .map_err(|_| Error::Closed)?
            .sender
            .as_ref()
            .ok_or(Error::Closed)?
            .clone();
        let control = Control::from_request(&request)?;
        let (reply, response) = mpsc::sync_channel(1);
        let mut call = Call {
            request,
            control: control.clone(),
            queued: Instant::now(),
            reply,
        };
        loop {
            if let Some(control) = &control {
                control.check()?;
            }
            match sender.try_send(call) {
                Ok(()) => break,
                Err(mpsc::TrySendError::Full(returned)) => {
                    call = returned;
                    thread::park_timeout(Duration::from_millis(1));
                }
                Err(mpsc::TrySendError::Disconnected(_)) => return Err(Error::Closed),
            }
        }
        loop {
            match response.recv_timeout(Duration::from_millis(1)) {
                Ok(value) => return value,
                Err(mpsc::RecvTimeoutError::Disconnected) => return Err(Error::Closed),
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if let Some(control) = &control {
                        control.check()?;
                    }
                }
            }
        }
    }
    /// Enter a raw business call with caller-owned cancellation and deadline.
    /// Logical fact ceilings remain in the typed request/session contract.
    /// # Errors
    /// Rejects conflicting control authority or preserves the original typed failure.
    pub fn call_cancelable(
        &self,
        request: Data,
        timeout: Duration,
        cancellation: &gerbil_ascent::Cancellation,
    ) -> Result<Data> {
        let control = Control::new(
            &gerbil_ascent::Limits {
                timeout,
                max_states: usize::MAX,
                max_facts: usize::MAX,
            },
            cancellation,
        )?;
        let Data::Map(mut fields) = request else {
            return Err(crate::failure("object required"));
        };
        if fields.contains_key("executionControl") {
            return Err(crate::failure("conflicting execution control authority"));
        }
        fields.insert("executionControl".into(), control.id());
        self.call(Data::Map(fields))
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
            maximum_overlapping_calls: self.activity.maximum.load(Ordering::Relaxed),
        }
    }
}
/// Fixed resident process VM population; no per-query spawn and no shared GC heap.
pub struct ProcessPool {
    owners: Vec<ProcessOwner>,
}
impl ProcessPool {
    /// Start the installed worker program; VM setup uses gerbil-scheme-rust.
    /// # Errors
    /// Rejects zero owners, missing programs and incomplete child initialization.
    pub fn new(owners: usize) -> Result<Self> {
        Self::with_program(owners, &WorkerProgram::discover()?)
    }
    /// Start an explicit installed child entry, including the Rust/PyO3 worker.
    /// # Errors
    /// Rejects zero owners, namespace exhaustion and native/protocol startup failures.
    pub fn with_program(owners: usize, program: &WorkerProgram) -> Result<Self> {
        if owners == 0 || owners > 64 {
            return Err(crate::failure("process VM count must be in 1..=64"));
        }
        let activity = Arc::new(Activity::default());
        let mut population = Vec::new();
        for _ in 0..owners {
            population.push(start(program, activity.clone())?);
        }
        Ok(Self { owners: population })
    }
    /// Select one persistent VM; all leases must keep this affinity.
    /// # Errors
    /// Rejects indices outside the fixed population.
    pub fn owner(&self, index: usize) -> Result<ProcessOwner> {
        self.owners.get(index).cloned().ok_or(Error::Closed)
    }
    #[must_use]
    pub fn receipts(&self) -> Vec<ProcessReceipt> {
        self.owners.iter().map(ProcessOwner::receipt).collect()
    }
    /// Reset diagnostics while all callers are idle, before a measurement window.
    pub fn reset_statistics(&self) {
        for owner in &self.owners {
            for counter in [
                &owner.counters.calls,
                &owner.counters.queue_ns,
                &owner.counters.service_ns,
                &owner.counters.checkpoints,
            ] {
                counter.store(0, Ordering::Relaxed);
            }
            owner.activity.maximum.store(
                owner.activity.active.load(Ordering::Acquire),
                Ordering::Release,
            );
        }
    }
}
pub(crate) fn standalone_owner() -> Result<ProcessOwner> {
    ProcessPool::new(1)?.owner(0)
}
fn io_error(error: impl std::fmt::Display) -> Error {
    crate::failure(&format!("Scheme process transport: {error}"))
}
fn nanos(duration: Duration) -> u64 {
    u64::try_from(duration.as_nanos()).unwrap_or(u64::MAX)
}
fn accept_worker(
    listener: &UnixListener,
    child: &mut Child,
    domain: u64,
) -> Result<(UnixStream, ProcessReceipt)> {
    let deadline = Instant::now() + Duration::from_secs(30);
    loop {
        match listener.accept() {
            Ok((mut socket, _)) => {
                // Darwin accepts inherit O_NONBLOCK from the listener.
                // Deadline-based blocking reads require clearing it explicitly.
                socket.set_nonblocking(false).map_err(io_error)?;
                socket
                    .set_read_timeout(Some(Duration::from_secs(30)))
                    .map_err(io_error)?;
                let ready = process_wire::receive(&mut socket).map_err(io_error)?;
                match ready {
                    Frame::Ready {
                        protocol: 1,
                        pid,
                        processors: 1,
                        domain: found,
                        identity,
                    } if pid == child.id()
                        && found == domain
                        && identity == crate::build_identity() =>
                    {
                        socket.set_read_timeout(None).map_err(io_error)?;
                        return Ok((
                            socket,
                            ProcessReceipt {
                                pid,
                                processors: 1,
                                domain,
                            },
                        ));
                    }
                    _ => return Err(crate::failure("process owner handshake mismatch")),
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                if child.try_wait().map_err(io_error)?.is_some() || Instant::now() >= deadline {
                    return Err(crate::failure(
                        "Scheme process initialization failed or timed out",
                    ));
                }
                thread::sleep(Duration::from_millis(1));
            }
            Err(error) => return Err(io_error(error)),
        }
    }
}
fn start(program: &WorkerProgram, activity: Arc<Activity>) -> Result<ProcessOwner> {
    let domain = DOMAIN
        .try_update(Ordering::AcqRel, Ordering::Acquire, |v| {
            (v < u64::from(u32::MAX)).then_some(v + 1)
        })
        .map_err(|_| crate::failure("process owner domains exhausted"))?;
    let directory = tempfile::Builder::new()
        .prefix("ascent-owner-")
        .tempdir()
        .map_err(io_error)?;
    let socket_path = directory.path().join("owner.sock");
    let listener = UnixListener::bind(&socket_path).map_err(io_error)?;
    listener.set_nonblocking(true).map_err(io_error)?;
    let mut child = Command::new(&program.executable)
        .args(&program.arguments)
        .arg(&socket_path)
        .arg(domain.to_string())
        .stdin(Stdio::null())
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
        .map_err(io_error)?;
    let accepted = accept_worker(&listener, &mut child, domain);
    let (socket, receipt) = match accepted {
        Ok(value) => value,
        Err(error) => {
            let _ = child.kill();
            let _ = child.wait();
            return Err(error);
        }
    };
    drop(directory);
    let child = Arc::new(Mutex::new(child));
    let (sender, incoming) = mpsc::sync_channel::<Call>(64);
    let (finished, done) = mpsc::channel();
    let counters = Arc::new(Counters::default());
    let child_owner = child.clone();
    let work_counters = counters.clone();
    let work_activity = activity.clone();
    let thread = thread::Builder::new()
        .name(format!("ascent-process-{}", receipt.pid))
        .spawn(move || {
            run(socket, incoming, &work_counters, &work_activity);
            loop {
                let stopped = child_owner
                    .lock()
                    .map_or(true, |mut child| !matches!(child.try_wait(), Ok(None)));
                if stopped {
                    break;
                }
                thread::sleep(Duration::from_millis(1));
            }
            let _ = finished.send(());
        });
    let thread = match thread {
        Ok(thread) => thread,
        Err(error) => {
            if let Ok(mut child) = child.lock() {
                let _ = child.kill();
                let _ = child.wait();
            }
            return Err(io_error(error));
        }
    };
    Ok(ProcessOwner {
        parent: std::process::id(),
        receipt,
        counters,
        activity,
        worker: Arc::new(Mutex::new(Worker {
            parent: std::process::id(),
            sender: Some(sender),
            child,
            thread: Some(thread),
            done,
        })),
    })
}
fn receive_native_reply(
    socket: &mut UnixStream,
    control: Option<&Control>,
    counters: &Counters,
    activity: &Activity,
    entered: &mut bool,
) -> Result<Result<Data>> {
    loop {
        match process_wire::receive(socket).map_err(io_error)? {
            Frame::Entered if !*entered => {
                *entered = true;
                let active = activity.active.fetch_add(1, Ordering::AcqRel) + 1;
                activity.maximum.fetch_max(active, Ordering::AcqRel);
            }
            Frame::Checkpoint { id, work, facts: _ } if *entered => {
                let expected = control.map(Control::numeric_id);
                let code = if expected == Some(id) {
                    crate::control::checkpoint(id, work)
                } else {
                    5
                };
                counters.checkpoints.fetch_add(1, Ordering::Relaxed);
                process_wire::send(socket, &Frame::Decision(code)).map_err(io_error)?;
            }
            Frame::Reply { value, elapsed_ns } if *entered => {
                counters.calls.fetch_add(1, Ordering::Relaxed);
                counters.service_ns.fetch_add(elapsed_ns, Ordering::Relaxed);
                return Ok(value);
            }
            _ => return Err(crate::failure("process owner protocol mismatch")),
        }
    }
}
fn run(
    mut socket: UnixStream,
    incoming: mpsc::Receiver<Call>,
    counters: &Counters,
    activity: &Activity,
) {
    for call in incoming {
        let admitted = call.control.as_ref().map_or(Ok(()), Control::check);
        if let Err(error) = admitted {
            let _ = call.reply.send(Err(error));
            continue;
        }
        counters
            .queue_ns
            .fetch_add(nanos(call.queued.elapsed()), Ordering::Relaxed);
        let cleanup_request = Data::Map(
            ["operation", "owner", "handle"]
                .into_iter()
                .filter_map(|key| {
                    call.request
                        .get(key)
                        .map(|value| (key.to_owned(), value.clone()))
                })
                .collect(),
        );
        let mut entered = false;
        let result = (|| {
            process_wire::send(&mut socket, &Frame::Request(call.request)).map_err(io_error)?;
            receive_native_reply(
                &mut socket,
                call.control.as_ref(),
                counters,
                activity,
                &mut entered,
            )
        })();
        if entered {
            activity.active.fetch_sub(1, Ordering::AcqRel);
        }
        match result {
            Ok(value) => {
                if let Err(mpsc::SendError(Ok(value))) = call.reply.send(value) {
                    release_abandoned(&mut socket, &cleanup_request, &value);
                }
            }
            Err(error) => {
                let _ = call.reply.send(Err(error));
                break;
            }
        }
    }
    let _ = socket.shutdown(std::net::Shutdown::Both);
}
fn release_abandoned(socket: &mut UnixStream, request: &Data, value: &Data) {
    if let Some(cleanup) = abandoned_request(request, value)
        && process_wire::send(socket, &Frame::Request(cleanup)).is_ok()
    {
        while let Ok(frame) = process_wire::receive(socket) {
            if matches!(frame, Frame::Reply { .. }) {
                break;
            }
        }
    }
}

fn abandoned_request(request: &Data, value: &Data) -> Option<Data> {
    let operation = request
        .get("operation")
        .and_then(|v| v.text().ok())
        .unwrap_or("");
    match operation {
        "dsl-open" | "module-open" | "module-source-open" | "components-open" => {
            value.get("owner").map(|owner| {
                Data::object([
                    ("operation", Data::from("module-close")),
                    ("owner", owner.clone()),
                ])
            })
        }
        "open" | "open-evidence" | "value-evidence" | "open-sources" | "open-rule-sources" => {
            value.get("handle").map(|handle| {
                Data::object([
                    ("operation", Data::from("close")),
                    ("handle", handle.clone()),
                ])
            })
        }
        "module-call" | "module-apply" => {
            request
                .get("owner")
                .zip(value.get("valueHandle"))
                .map(|(owner, handle)| {
                    Data::object([
                        ("operation", Data::from("module-value")),
                        ("owner", owner.clone()),
                        ("value", handle.clone()),
                        ("action", Data::from("release")),
                    ])
                })
        }
        "source-run" => {
            request
                .get("handle")
                .zip(value.get("resultHandle"))
                .map(|(owner, handle)| {
                    Data::object([
                        ("operation", Data::from("owned-result")),
                        ("handle", owner.clone()),
                        ("result", handle.clone()),
                        ("action", Data::from("release")),
                    ])
                })
        }
        "owned-result" => request
            .get("handle")
            .zip(value.get("explanationHandle"))
            .map(|(owner, handle)| {
                Data::object([
                    ("operation", Data::from("owned-result")),
                    ("handle", owner.clone()),
                    ("result", handle.clone()),
                    ("action", Data::from("release")),
                ])
            }),
        _ => None,
    }
}
