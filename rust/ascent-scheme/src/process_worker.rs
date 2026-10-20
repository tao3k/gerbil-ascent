//! Exec child entry; the upstream owner and all GC roots stay on this thread.
use crate::{
    Runtime,
    process_checkpoint::Checkpoints,
    process_wire::{Connection, Frame},
};
use gerbil_ascent::{Data, Result};
use std::{cell::RefCell, os::unix::net::UnixStream, path::Path, rc::Rc, time::Instant};
struct Remote {
    id: i64,
    checkpoints: Option<Rc<Checkpoints>>,
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
            return None;
        }
        if let Some(checkpoints) = &remote.checkpoints {
            return Some(
                match checkpoints.request(id, work, || remote.socket.borrow().peer_closed()) {
                    Ok(code) => code,
                    Err(error) => {
                        eprintln!("ASCENT-CHECKPOINT-TRANSPORT-ERROR {error}");
                        5
                    }
                },
            );
        }
        let mut socket = remote.socket.borrow_mut();
        Some(
            match socket
                .send(&Frame::Checkpoint { id, work, facts })
                .and_then(|()| socket.receive())
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
    let checkpoints = Rc::new(
        Checkpoints::open(&path.as_ref().with_extension("control"))
            .map_err(|e| crate::failure(&e.to_string()))?,
    );
    let socket = Rc::new(RefCell::new(Connection::new(
        UnixStream::connect(path).map_err(|e| crate::failure(&e.to_string()))?,
    )));
    let runtime = initialize(&socket, domain)?;
    loop {
        let request = match socket.borrow_mut().receive() {
            Ok(Frame::Request(request)) => request,
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            _ => return Err(crate::failure("invalid process owner request")),
        };
        execute(&runtime, &socket, &checkpoints, &request)?;
    }
    crate::service::trace_retirement(std::process::id(), "vm-cleanup-begin");
    drop(runtime);
    crate::service::trace_retirement(std::process::id(), "vm-cleanup-end");
    Ok(())
}

fn initialize(socket: &Rc<RefCell<Connection>>, domain: u64) -> Result<Runtime> {
    let runtime = Runtime::initialize()?;
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
    socket
        .borrow_mut()
        .send(&Frame::Ready {
            protocol: 2,
            pid: std::process::id(),
            processors,
            domain,
            identity: crate::build_identity(),
        })
        .map_err(|e| crate::failure(&e.to_string()))?;
    Ok(runtime)
}

fn execute(
    runtime: &Runtime,
    socket: &Rc<RefCell<Connection>>,
    checkpoints: &Rc<Checkpoints>,
    request: &Data,
) -> Result<()> {
    // Kernel checkpoints are frequent. Expansion, loading and arbitrary
    // callbacks keep the sleeping socket exchange, so idle owner threads
    // never burn a core while the VM performs unrelated preparation.
    let shared_checkpoints = cfg!(target_os = "linux")
        && request.get("executionControl").is_some()
        && matches!(
            request.get("operation").and_then(|v| v.text().ok()),
            Some("source-run" | "source-replace")
        );
    if let Some(id) = request.get("executionControl") {
        let id = i64::try_from(id.index()?).map_err(|_| gerbil_ascent::Error::Closed)?;
        REMOTE.with(|remote| {
            *remote.borrow_mut() = Some(Remote {
                id,
                checkpoints: shared_checkpoints.then(|| Rc::clone(checkpoints)),
                socket: Rc::clone(socket),
            });
        });
    }
    if shared_checkpoints {
        let id = request.field("executionControl")?.index()?;
        checkpoints.begin(i64::try_from(id).map_err(|_| gerbil_ascent::Error::Closed)?);
    }
    socket
        .borrow_mut()
        .send(&Frame::Entered { shared_checkpoints })
        .map_err(|e| crate::failure(&e.to_string()))?;
    let start = Instant::now();
    let value = runtime.call(request);
    let elapsed_ns = u64::try_from(start.elapsed().as_nanos()).unwrap_or(u64::MAX);
    REMOTE.with(|remote| *remote.borrow_mut() = None);
    if shared_checkpoints {
        checkpoints.complete();
    }
    socket
        .borrow_mut()
        .send(&Frame::Reply { value, elapsed_ns })
        .map_err(|e| crate::failure(&e.to_string()))?;
    Ok(())
}
