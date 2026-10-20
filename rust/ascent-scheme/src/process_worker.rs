//! Exec child entry; the upstream owner and all GC roots stay on this thread.
use crate::{
    Runtime,
    process_wire::{self, Frame},
};
use gerbil_ascent::{Data, Result};
use std::{cell::RefCell, os::unix::net::UnixStream, path::Path, time::Instant};
thread_local! {
    static REMOTE: RefCell<Option<(i64, UnixStream)>> = const { RefCell::new(None) };
}
pub(crate) fn remote_checkpoint(id: i64, work: i64, facts: i64) -> Option<i32> {
    REMOTE.with(|remote| {
        let mut remote = remote.borrow_mut();
        let (expected, stream) = remote.as_mut()?;
        if id != *expected {
            return None;
        }
        let code = process_wire::send(stream, &Frame::Checkpoint { id, work, facts })
            .and_then(|()| process_wire::receive(stream));
        Some(match code {
            Ok(Frame::Decision(code)) => code,
            _ => 5,
        })
    })
}
/// Serve the private owner socket. Intended for the installed worker executable
/// and the Rust/PyO3 worker entry, not an additional evaluator.
/// # Errors
/// Propagates protocol, lifecycle, domain or native processor population errors.
pub fn serve(path: impl AsRef<Path>, domain: u64) -> Result<()> {
    let mut socket = UnixStream::connect(path).map_err(|e| crate::failure(&e.to_string()))?;
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
    process_wire::send(
        &mut socket,
        &Frame::Ready {
            protocol: 1,
            pid: std::process::id(),
            processors,
            domain,
            identity: crate::build_identity(),
        },
    )
    .map_err(|e| crate::failure(&e.to_string()))?;
    loop {
        let request = match process_wire::receive(&mut socket) {
            Ok(Frame::Request(request)) => request,
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            _ => return Err(crate::failure("invalid process owner request")),
        };
        if let Some(id) = request.get("executionControl") {
            let id = i64::try_from(id.index()?).map_err(|_| gerbil_ascent::Error::Closed)?;
            let control = socket
                .try_clone()
                .map_err(|e| crate::failure(&e.to_string()))?;
            REMOTE.with(|remote| *remote.borrow_mut() = Some((id, control)));
        }
        process_wire::send(&mut socket, &Frame::Entered)
            .map_err(|e| crate::failure(&e.to_string()))?;
        let start = Instant::now();
        let value = runtime.call(&request);
        let elapsed_ns = u64::try_from(start.elapsed().as_nanos()).unwrap_or(u64::MAX);
        REMOTE.with(|remote| *remote.borrow_mut() = None);
        process_wire::send(&mut socket, &Frame::Reply { value, elapsed_ns })
            .map_err(|e| crate::failure(&e.to_string()))?;
    }
    Ok(())
}
