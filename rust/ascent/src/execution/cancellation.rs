//! Optional request wakeups. Ordinary cancellation still reads one atomic flag.
use crate::{Error, Result};
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex, OnceLock, Weak,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
    task::Waker,
};
struct Group {
    source: Weak<AtomicBool>,
    listeners: BTreeMap<u64, Waker>,
}
static GROUPS: OnceLock<Mutex<BTreeMap<usize, Group>>> = OnceLock::new();
static NEXT: AtomicU64 = AtomicU64::new(1);
/// Removes a wake registration. An already cloned notification needs a separate destination fence.
pub struct CancellationSubscription {
    key: usize,
    id: u64,
}
impl Drop for CancellationSubscription {
    fn drop(&mut self) {
        let removed = {
            let mut groups = GROUPS
                .get_or_init(Mutex::default)
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let removed = groups
                .get_mut(&self.key)
                .and_then(|group| group.listeners.remove(&self.id));
            if groups
                .get(&self.key)
                .is_some_and(|group| group.listeners.is_empty())
            {
                groups.remove(&self.key);
            }
            removed
        };
        drop(removed);
    }
}
pub(super) fn subscribe(source: &Arc<AtomicBool>, wake: Waker) -> Result<CancellationSubscription> {
    let id = NEXT
        .try_update(Ordering::AcqRel, Ordering::Acquire, |v| v.checked_add(1))
        .map_err(|_| {
            Error::InvalidProgram("cancellation notification identity exhausted".into())
        })?;
    let key = Arc::as_ptr(source) as usize;
    let notification = wake.clone();
    {
        let mut groups = GROUPS
            .get_or_init(Mutex::default)
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let group = groups.entry(key).or_insert_with(|| Group {
            source: Arc::downgrade(source),
            listeners: BTreeMap::new(),
        });
        if !group.source.ptr_eq(&Arc::downgrade(source)) {
            return Err(Error::Closed);
        }
        group.listeners.insert(id, wake);
    }
    if source.load(Ordering::Acquire) {
        notification.wake_by_ref();
    }
    Ok(CancellationSubscription { key, id })
}
pub(super) fn notify(source: &Arc<AtomicBool>) {
    let listeners: Vec<_> = GROUPS
        .get_or_init(Mutex::default)
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .get(&(Arc::as_ptr(source) as usize))
        .map_or_else(Vec::new, |group| {
            group.listeners.values().cloned().collect()
        });
    for listener in listeners {
        listener.wake();
    }
}
#[cfg(test)]
#[path = "../../tests/unit/cancellation_notifications.rs"]
mod tests;
