//! Request-local execution admission. Only an integer key crosses the C ABI.
use gerbil_ascent::{Cancellation, Data, Error, Limits, Result};
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex, OnceLock, Weak,
        atomic::{AtomicU64, Ordering},
    },
    time::Instant,
};
pub(crate) fn controlled_request(
    request: Data,
    timeout: std::time::Duration,
    cancellation: &Cancellation,
) -> Result<(Control, Data)> {
    let control = Control::new(
        &Limits {
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
    Ok((control, Data::Map(fields)))
}

struct Entry {
    cancellation: Cancellation,
    deadline: Instant,
    state: crate::control_state::State,
    remote: Option<Arc<crate::process_control::Shared>>,
    closed: bool,
}
struct Scope {
    id: i64,
    entry: Mutex<Entry>,
}
static ENTRIES: OnceLock<Mutex<BTreeMap<i64, Weak<Scope>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
#[cfg(all(feature = "instances", target_os = "macos"))]
thread_local! {
    static CURRENT: std::cell::RefCell<Option<(Control, Arc<AtomicU64>)>> = const { std::cell::RefCell::new(None) };
}
#[cfg(all(feature = "instances", target_os = "macos"))]
pub(crate) struct Entered {
    previous: Option<(Control, Arc<AtomicU64>)>,
    _owner: std::marker::PhantomData<std::rc::Rc<()>>,
}
#[cfg(all(feature = "instances", target_os = "macos"))]
impl Drop for Entered {
    fn drop(&mut self) {
        CURRENT.with(|current| current.replace(self.previous.take()));
    }
}
#[derive(Clone)]
pub(crate) struct Control(Arc<Scope>);
impl Control {
    pub(crate) fn lease(&self, shared: Arc<crate::process_control::Shared>) -> Result<Lease> {
        let mut entry = self.0.entry.lock().map_err(|_| Error::Closed)?;
        if entry.closed || entry.remote.is_some() {
            return Err(Error::Closed);
        }
        reason(interruption(&entry))?;
        shared.begin(self.numeric_id(), entry.state, entry.deadline)?;
        let wake = Arc::new(CancelWake {
            armed: Mutex::new(Some(self.numeric_id())),
            shared: shared.clone(),
        });
        let subscription = match entry
            .cancellation
            .subscribe(std::task::Waker::from(wake.clone()))
        {
            Ok(subscription) => subscription,
            Err(error) => {
                shared.close();
                return Err(error);
            }
        };
        entry.remote = Some(shared.clone());
        Ok(Lease {
            control: self.clone(),
            shared,
            wake,
            subscription: Some(subscription),
            finished: false,
        })
    }

    #[cfg(all(feature = "instances", target_os = "macos"))]
    pub(crate) fn enter(&self, counter: Arc<AtomicU64>) -> Entered {
        let previous = CURRENT.with(|current| current.replace(Some((self.clone(), counter))));
        Entered {
            previous,
            _owner: std::marker::PhantomData,
        }
    }
    pub(crate) fn new(limits: &Limits, cancellation: &Cancellation) -> Result<Self> {
        if cancellation.is_canceled() {
            return Err(Error::Canceled);
        }
        if limits.timeout.is_zero() {
            return Err(Error::Timeout);
        }
        let deadline = Instant::now()
            .checked_add(limits.timeout)
            .ok_or(Error::Timeout)?;
        let id = NEXT
            .try_update(Ordering::AcqRel, Ordering::Acquire, |v| {
                (v < i64::MAX as u64).then_some(v + 1)
            })
            .map_err(|_| crate::failure("execution request identity exhausted"))?;
        let id = i64::try_from(id)
            .map_err(|_| crate::failure("execution request identity exhausted"))?;
        let scope = Arc::new(Scope {
            id,
            entry: Mutex::new(Entry {
                cancellation: cancellation.clone(),
                remote: None,
                closed: false,
                deadline,
                state: crate::control_state::State {
                    work: 0,
                    maximum: limits.max_states,
                    accepted: false,
                    suspended: false,
                },
            }),
        });
        ENTRIES
            .get_or_init(Mutex::default)
            .lock()
            .map_err(|_| Error::Closed)?
            .insert(id, Arc::downgrade(&scope));
        Ok(Self(scope))
    }
    pub(crate) fn from_request(request: &Data) -> Result<Option<Self>> {
        let Some(id) = request.get("executionControl") else {
            return Ok(None);
        };
        let id = i64::try_from(id.index()?).map_err(|_| Error::Closed)?;
        scope(id).map(Self).map(Some).ok_or(Error::Closed)
    }
    pub(crate) fn checkpoint(&self, work: i64) -> i32 {
        checkpoint_scope(&self.0, work)
    }
    pub(crate) fn numeric_id(&self) -> i64 {
        self.0.id
    }
    pub(crate) fn id(&self) -> Data {
        Data::Integer(self.0.id.into())
    }
    pub(crate) fn remaining(&self) -> Result<std::time::Duration> {
        self.check()?;
        Ok(self
            .0
            .entry
            .lock()
            .map_err(|_| Error::Closed)?
            .deadline
            .saturating_duration_since(Instant::now()))
    }
    pub(crate) fn check(&self) -> Result<()> {
        let entry = self.0.entry.lock().map_err(|_| Error::Closed)?;
        let code = interruption(&entry);
        if let Some(remote) = &entry.remote {
            if code == 1 {
                remote.cancel(self.numeric_id());
            }
            if code == 2 {
                remote.expire(self.numeric_id());
            }
        }
        reason(code)
    }
}
impl Drop for Scope {
    fn drop(&mut self) {
        if let Some(entries) = ENTRIES.get()
            && let Ok(mut entries) = entries.lock()
        {
            entries.remove(&self.id);
        }
    }
}
fn scope(id: i64) -> Option<Arc<Scope>> {
    let weak = ENTRIES.get()?.lock().ok()?.get(&id)?.clone();
    weak.upgrade()
}
fn interruption(entry: &Entry) -> i32 {
    if entry.closed {
        5
    } else if entry.state.accepted {
        0
    } else if entry.cancellation.is_canceled() {
        1
    } else if Instant::now() >= entry.deadline {
        2
    } else {
        0
    }
}
pub(crate) fn checkpoint(id: i64, work: i64) -> i32 {
    #[cfg(all(feature = "instances", target_os = "macos"))]
    if let Some(code) = CURRENT.with(|current| {
        current.borrow().as_ref().map(|(control, counter)| {
            counter.fetch_add(1, Ordering::Relaxed);
            if control.numeric_id() == id {
                control.checkpoint(work)
            } else {
                5
            }
        })
    }) {
        return code;
    }
    let Some(scope) = scope(id) else {
        return 5;
    };
    checkpoint_scope(&scope, work)
}
fn checkpoint_scope(scope: &Scope, work: i64) -> i32 {
    let Ok(mut entry) = scope.entry.lock() else {
        return 5;
    };
    if entry.closed {
        return 5;
    }
    let remote = entry.remote.clone();
    if let Some(remote) = &remote {
        // The VM is waiting for this socket decision: its resource state is stable.
        let Ok(snapshot) = remote.snapshot(scope.id) else {
            return 5;
        };
        if snapshot.maximum != entry.state.maximum || snapshot.accepted != entry.state.accepted {
            return 5;
        }
        entry.state.work = snapshot.work;
        entry.state.suspended = snapshot.suspended;
    }
    let Entry {
        cancellation,
        deadline,
        state,
        remote: _,
        closed: _,
    } = &mut *entry;
    let code = state.advance(work, |accepted| {
        if accepted {
            0
        } else if cancellation.is_canceled() {
            1
        } else if Instant::now() >= *deadline {
            2
        } else {
            0
        }
    });
    if let Some(remote) = remote
        && remote.publish(scope.id, *state).is_err()
    {
        return 5;
    }
    code
}
fn reason(code: i32) -> Result<()> {
    match code {
        0 => Ok(()),
        1 => Err(Error::Canceled),
        2 => Err(Error::Timeout),
        3 => Err(Error::StateLimit),
        _ => Err(Error::Closed),
    }
}
// No VM entry, Scheme object or unwinding crosses this callback boundary.
pub(crate) extern "C" fn ascent_hybrid_checkpoint(id: i64, work: i64, facts: i64) -> i32 {
    crate::process_worker::remote_checkpoint(id, work, facts)
        .unwrap_or_else(|| checkpoint(id, work))
}

struct CancelWake {
    armed: Mutex<Option<i64>>,
    shared: Arc<crate::process_control::Shared>,
}
impl std::task::Wake for CancelWake {
    fn wake(self: Arc<Self>) {
        Self::wake_by_ref(&self);
    }
    fn wake_by_ref(self: &Arc<Self>) {
        if let Ok(armed) = self.armed.lock() {
            if let Some(id) = *armed {
                self.shared.cancel(id);
            }
        } else {
            self.shared.close();
        }
    }
}

pub(crate) struct Lease {
    control: Control,
    shared: Arc<crate::process_control::Shared>,
    wake: Arc<CancelWake>,
    subscription: Option<gerbil_ascent::CancellationSubscription>,
    finished: bool,
}
impl Lease {
    fn disarm(&mut self) {
        if let Ok(mut armed) = self.wake.armed.lock() {
            *armed = None;
        }
        self.subscription.take();
    }
    pub(crate) fn finish(mut self) -> Result<()> {
        self.disarm();
        let mut entry = self.control.0.entry.lock().map_err(|_| Error::Closed)?;
        let state = self.shared.finish(self.control.numeric_id());
        entry.remote = None;
        match state {
            Ok(state)
                if state.maximum == entry.state.maximum
                    && state.accepted == entry.state.accepted =>
            {
                entry.state = state;
            }
            Ok(_) => {
                entry.closed = true;
                return Err(Error::Closed);
            }
            Err(error) => {
                entry.closed = true;
                return Err(error);
            }
        }
        self.finished = true;
        Ok(())
    }
}
impl Drop for Lease {
    fn drop(&mut self) {
        if !self.finished {
            self.disarm();
            // Revoke failed requests without waiting on a child-owned lock.
            self.shared.close();
            if let Ok(mut entry) = self.control.0.entry.lock() {
                entry.remote = None;
                entry.closed = true;
            }
        }
    }
}
