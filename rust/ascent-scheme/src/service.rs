//! ASCENT calls from concurrent hosts. The upstream runtime stays on its owner.
use crate::{Runtime, failure};
use gerbil_ascent::{Data, Result};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU32, Ordering};
use tokio::sync::{mpsc, oneshot};

struct Call {
    request: Data,
    reply: oneshot::Sender<Result<Data>>,
}
static SERVICE: OnceLock<Result<mpsc::Sender<Call>>> = OnceLock::new();
static PROCESS: AtomicU32 = AtomicU32::new(0);

/// Submit an ASCENT business call to the process's one native Scheme owner.
/// Uses the upstream demonstrated bounded Tokio admission/receive-many pattern;
/// this is not a generic VM scheduler or a claim of multiple physical VMs.
/// # Errors
/// Preserves initialization and Scheme operation errors, or reports a closed owner.
pub fn call(request: Data) -> Result<Data> {
    let pid = std::process::id();
    let original = PROCESS
        .compare_exchange(0, pid, Ordering::AcqRel, Ordering::Acquire)
        .unwrap_or_else(|v| v);
    if original != 0 && original != pid {
        return Err(failure("inherited Scheme runtime cannot enter after fork"));
    }
    let sender = SERVICE.get_or_init(start).as_ref().map_err(Clone::clone)?;
    let (reply, response) = oneshot::channel();
    sender
        .blocking_send(Call { request, reply })
        .map_err(|_| failure("Scheme owner closed"))?;
    response
        .blocking_recv()
        .map_err(|_| failure("Scheme owner terminated"))?
}
fn start() -> Result<mpsc::Sender<Call>> {
    let (sender, mut incoming) = mpsc::channel::<Call>(64);
    let (ready, initialized) = oneshot::channel();
    std::thread::Builder::new()
        .name("ascent-scheme".into())
        .spawn(move || {
            let runtime = match Runtime::initialize() {
                Ok(runtime) => runtime,
                Err(error) => {
                    let _ = ready.send(Err(error));
                    return;
                }
            };
            if ready.send(Ok(())).is_err() {
                return;
            }
            let mut pending = Vec::with_capacity(incoming.max_capacity());
            let limit = incoming.max_capacity();
            while incoming.blocking_recv_many(&mut pending, limit) > 0 {
                for call in pending.drain(..) {
                    let _ = call.reply.send(runtime.call(&call.request));
                }
            }
            // GerbilRuntime and all roots are destroyed on their original thread.
        })
        .map_err(|error| failure(&error.to_string()))?;
    initialized
        .blocking_recv()
        .map_err(|_| failure("Scheme owner initialization terminated"))??;
    Ok(sender)
}
