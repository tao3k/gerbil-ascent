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
struct Entry {
    cancellation: Cancellation,
    deadline: Instant,
    work: usize,
    max_work: usize,
    accepted: bool,
    suspended: bool,
}
struct Scope {
    id: i64,
    entry: Mutex<Entry>,
}
static ENTRIES: OnceLock<Mutex<BTreeMap<i64, Weak<Scope>>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
#[derive(Clone)]
pub(crate) struct Control(Arc<Scope>);
impl Control {
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
            .fetch_update(Ordering::AcqRel, Ordering::Acquire, |v| {
                (v < i64::MAX as u64).then_some(v + 1)
            })
            .map_err(|_| crate::failure("execution request identity exhausted"))?;
        let id = i64::try_from(id)
            .map_err(|_| crate::failure("execution request identity exhausted"))?;
        let scope = Arc::new(Scope {
            id,
            entry: Mutex::new(Entry {
                cancellation: cancellation.clone(),
                deadline,
                work: 0,
                max_work: limits.max_states,
                accepted: false,
                suspended: false,
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
        reason(interruption(&entry))
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
    if entry.accepted {
        0
    } else if entry.cancellation.is_canceled() {
        1
    } else if Instant::now() >= entry.deadline {
        2
    } else {
        0
    }
}
fn checkpoint(id: i64, work: i64) -> i32 {
    let Some(scope) = scope(id) else {
        return 5;
    };
    let Ok(mut entry) = scope.entry.lock() else {
        return 5;
    };
    if work == -2 {
        entry.suspended = true;
        return 0;
    }
    if work == -3 {
        entry.suspended = false;
        return 0;
    }
    if entry.suspended {
        return 0;
    }
    let interrupted = interruption(&entry);
    if interrupted != 0 {
        return interrupted;
    }
    if entry.accepted {
        return 0;
    }
    if work == -1 {
        entry.accepted = true;
        return 0;
    }
    let Ok(work) = usize::try_from(work) else {
        return 3;
    };
    let Some(work) = entry.work.checked_add(work) else {
        return 3;
    };
    if work > entry.max_work {
        return 3;
    }
    entry.work = work;
    0
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
pub(crate) extern "C" fn ascent_hybrid_checkpoint(id: i64, work: i64, _facts: i64) -> i32 {
    checkpoint(id, work)
}
