//! Exec child entry; the upstream owner and all GC roots stay on this thread.
use crate::{
    Runtime,
    ffi::ascent_hybrid_process_wait,
    process_control::Shared,
    process_wire::{self, Connection, Frame, ResidentIo},
};
use gerbil_ascent::{Data, Result};
use gerbil_scheme::{GerbilRuntime, RootedSchemeObject, SchemeScalar};
use std::{
    cell::RefCell,
    io::{self, Read, Write},
    os::{fd::RawFd, unix::net::UnixStream},
    path::Path,
    rc::Rc,
    time::Instant,
};

struct ProcessWait<'owner> {
    runtime: &'owner GerbilRuntime,
    device: RootedSchemeObject<'owner>,
    input: RootedSchemeObject<'owner>,
    output: RootedSchemeObject<'owner>,
    close: RootedSchemeObject<'owner>,
}

impl<'owner> ProcessWait<'owner> {
    fn open(runtime: &'owner GerbilRuntime, fd: RawFd) -> Result<Self> {
        let scalar = |value| runtime.scalar_object(value).map_err(crate::scheme_error);
        let input = scalar(SchemeScalar::Boolean(false))?;
        let output = scalar(SchemeScalar::Boolean(true))?;
        let close = runtime.void_object().map_err(crate::scheme_error)?;
        let descriptor = scalar(SchemeScalar::Fixnum(fd as isize))?;
        // SAFETY: this export belongs to the initialized graph. It duplicates
        // the descriptor and transfers an owner-local procedure root.
        let open = unsafe { runtime.bind_object_export(ascent_hybrid_process_wait) }
            .map_err(crate::scheme_error)?;
        let device = open
            .call(&descriptor)
            .into_result()
            .map_err(crate::scheme_error)?;
        Ok(Self {
            runtime,
            device,
            input,
            output,
            close,
        })
    }

    fn wait(&self, output: bool) -> io::Result<()> {
        let direction = if output { &self.output } else { &self.input };
        self.runtime
            .call_rooted(&self.device, direction)
            .map(drop)
            .map_err(io::Error::other)
    }

    fn close(self) -> Result<()> {
        self.runtime
            .call_rooted(&self.device, &self.close)
            .map(drop)
            .map_err(|error| crate::failure(&error.to_string()))
    }
}

struct Remote {
    id: i64,
    admission: Rc<Shared>,
    socket: Rc<RefCell<Connection>>,
}
thread_local! {
    static REMOTE: RefCell<Option<Remote>> = const { RefCell::new(None) };
}
pub(crate) fn remote_checkpoint(id: i64, work: i64, facts: i64) -> Option<i32> {
    REMOTE.with(|remote| {
        let mut remote = remote.borrow_mut();
        let remote = remote.as_mut()?;
        if id != remote.id {
            return Some(5);
        }
        if !matches!(remote.socket.borrow().peer_closed(), Ok(false)) {
            return Some(5);
        }
        let code = remote.admission.checkpoint(id, work);
        if code != 4 {
            return Some(code);
        }
        let descriptor = remote.socket.borrow().descriptor();
        let mut transport = ResidentIo {
            socket: &remote.socket,
            wait: |output| process_wire::wait_for_checkpoint_io(descriptor, output),
        };
        Some(
            match process_wire::send(&mut transport, &Frame::Checkpoint { id, work, facts })
                .and_then(|()| process_wire::receive(&mut transport))
            {
                Ok(Frame::Decision(code)) => code,
                _ => 5,
            },
        )
    })
}
/// Serve the private owner socket. Intended for the installed worker executable
/// and the Rust/PyO3 worker entry, not an additional evaluator.
/// # Errors
/// Propagates protocol, lifecycle, domain or native processor population errors.
pub fn serve(path: impl AsRef<Path>, domain: u64) -> Result<()> {
    let admission = Rc::new(
        Shared::open(&path.as_ref().with_extension("budget"))
            .map_err(|e| crate::failure(&e.to_string()))?,
    );
    let stream = UnixStream::connect(path).map_err(|e| crate::failure(&e.to_string()))?;
    stream
        .set_nonblocking(true)
        .map_err(|e| crate::failure(&e.to_string()))?;
    let socket = Rc::new(RefCell::new(Connection::new(stream)));
    let runtime = Runtime::initialize()?;
    let served = serve_runtime(&runtime, &socket, &admission, domain);
    crate::service::trace_retirement(std::process::id(), "vm-cleanup-begin");
    drop(runtime);
    crate::service::trace_retirement(std::process::id(), "vm-cleanup-end");
    served
}

fn serve_runtime(
    runtime: &Runtime,
    socket: &Rc<RefCell<Connection>>,
    admission: &Rc<Shared>,
    domain: u64,
) -> Result<()> {
    let descriptor = socket.borrow().descriptor();
    let wait = ProcessWait::open(&runtime.runtime, descriptor)?;
    let mut transport = ResidentIo {
        socket,
        wait: |output| wait.wait(output),
    };
    let served = serve_calls(runtime, socket, admission, domain, &mut transport);
    served.and(wait.close())
}

fn serve_calls(
    runtime: &Runtime,
    socket: &Rc<RefCell<Connection>>,
    admission: &Rc<Shared>,
    domain: u64,
    transport: &mut (impl Read + Write),
) -> Result<()> {
    send_ready(runtime, transport, domain)?;
    loop {
        let request = match process_wire::receive(transport) {
            Ok(Frame::Request(request)) => request,
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(()),
            _ => return Err(crate::failure("invalid process owner request")),
        };
        execute(runtime, socket, admission, &request, transport)?;
    }
}

fn send_ready(runtime: &Runtime, transport: &mut impl Write, domain: u64) -> Result<()> {
    runtime.call(&Data::object([
        ("operation", Data::from("process-domain")),
        ("domain", Data::from(domain)),
    ]))?;
    let processors = runtime
        .runtime
        .active_processors()
        .map_err(crate::scheme_error)?;
    if processors != 1 {
        return Err(crate::failure(
            "one active processor required per process VM",
        ));
    }
    process_wire::send(
        transport,
        &Frame::Ready {
            protocol: 3,
            pid: std::process::id(),
            processors,
            domain,
            identity: crate::build_identity(),
        },
    )
    .map_err(|e| crate::failure(&e.to_string()))
}

fn execute(
    runtime: &Runtime,
    socket: &Rc<RefCell<Connection>>,
    admission: &Rc<Shared>,
    request: &Data,
    transport: &mut impl Write,
) -> Result<()> {
    let id = request
        .get("executionControl")
        .map(|id| i64::try_from(id.index()?).map_err(|_| gerbil_ascent::Error::Closed))
        .transpose()?;
    process_wire::send(transport, &Frame::Entered).map_err(|e| crate::failure(&e.to_string()))?;
    // The child executes every original admission transition against the
    // same shared state observed by the caller. No per-checkpoint roundtrip.
    if let Some(id) = id {
        REMOTE.with(|remote| {
            *remote.borrow_mut() = Some(Remote {
                id,
                admission: Rc::clone(admission),
                socket: Rc::clone(socket),
            });
        });
    }
    let start = Instant::now();
    let value = runtime.call(request);
    let elapsed_ns = u64::try_from(start.elapsed().as_nanos()).unwrap_or(u64::MAX);
    REMOTE.with(|remote| *remote.borrow_mut() = None);
    process_wire::send(transport, &Frame::Reply { value, elapsed_ns })
        .map_err(|e| crate::failure(&e.to_string()))?;
    Ok(())
}
