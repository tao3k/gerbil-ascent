//! ASCENT calls from concurrent hosts. The upstream runtime stays on its owner.
use crate::{Runtime, failure};
use gerbil_ascent::{Data, Result};
use std::sync::OnceLock;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::mpsc as replies;
use std::time::Duration;
use tokio::sync::{mpsc, oneshot};

struct Call {
    request: Data,
    reply: replies::SyncSender<Result<Data>>,
    control: Option<crate::control::Control>,
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
    let control = crate::control::Control::from_request(&request)?;
    let (reply, response) = replies::sync_channel(1);
    let mut call = Call {
        request,
        reply,
        control: control.clone(),
    };
    loop {
        if let Some(control) = &control {
            control.check()?;
        }
        match sender.try_send(call) {
            Ok(()) => break,
            Err(mpsc::error::TrySendError::Full(returned)) => {
                call = returned;
                std::thread::park_timeout(Duration::from_millis(1));
            }
            Err(mpsc::error::TrySendError::Closed(_)) => {
                return Err(failure("Scheme owner closed"));
            }
        }
    }
    loop {
        // Replies wake this wait immediately. Cancellation polling adds no
        // artificial millisecond delay to the normal fast path.
        match response.recv_timeout(Duration::from_millis(1)) {
            Ok(value) => return value,
            Err(replies::RecvTimeoutError::Disconnected) => {
                return Err(failure("Scheme owner terminated"));
            }
            Err(replies::RecvTimeoutError::Timeout) => {
                if let Some(control) = &control {
                    control.check()?;
                }
            }
        }
    }
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
                    let admitted = call
                        .control
                        .as_ref()
                        .map_or(Ok(()), crate::control::Control::check);
                    let result = admitted.and_then(|()| runtime.call(&call.request));
                    if let Err(replies::TrySendError::Disconnected(Ok(value))) =
                        call.reply.try_send(result)
                    {
                        release_abandoned(&runtime, &call.request, &value);
                    }
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

// Unwinding or a disconnected host cannot consume a retained native owner slot.
fn release_abandoned(runtime: &Runtime, request: &Data, value: &Data) {
    let operation = request
        .get("operation")
        .and_then(|v| v.text().ok())
        .unwrap_or("");
    let cleanup =
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
            "module-call" | "module-apply" => request
                .get("owner")
                .zip(value.get("valueHandle"))
                .map(|(owner, handle)| {
                    Data::object([
                        ("operation", Data::from("module-value")),
                        ("owner", owner.clone()),
                        ("value", handle.clone()),
                        ("action", Data::from("release")),
                    ])
                }),
            "source-run" => {
                request
                    .get("handle")
                    .zip(value.get("resultHandle"))
                    .map(|(owner, handle)| {
                        Data::object([
                            ("operation", Data::from("native-result")),
                            ("handle", owner.clone()),
                            ("result", handle.clone()),
                            ("action", Data::from("release")),
                        ])
                    })
            }
            "native-result" => request
                .get("handle")
                .zip(value.get("explanationHandle"))
                .map(|(owner, handle)| {
                    Data::object([
                        ("operation", Data::from("native-result")),
                        ("handle", owner.clone()),
                        ("result", handle.clone()),
                        ("action", Data::from("release")),
                    ])
                }),
            _ => None,
        };
    if let Some(request) = cleanup {
        let _ = runtime.call(&request);
    }
}
