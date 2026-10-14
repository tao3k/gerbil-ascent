//! Convert arena objects to thread-safe relational cells once at admission.
use super::objects::{Arena, Id, Object};
use crate::{FrozenValue, Result, Value};
static NEXT_SNAPSHOT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
pub(super) fn snapshot() -> Result<u64> {
    NEXT_SNAPSHOT
        .fetch_update(
            std::sync::atomic::Ordering::Relaxed,
            std::sync::atomic::Ordering::Relaxed,
            |v| v.checked_add(1),
        )
        .map_err(|_| super::objects::fail("value snapshot identity exhausted"))
}
impl Arena {
    pub(super) fn freeze(&self, owner: u64, snapshot: u64, id: Id) -> Result<Value> {
        Ok(match self.get(id)? {
            Object::Number(v) if v.is_integer() => Value::Integer(v.to_integer()),
            Object::Boolean(v) => Value::Boolean(*v),
            Object::Text(v) => Value::Text(v.as_str().into()),
            Object::Symbol(v, true) => Value::Symbol(v.as_str().into()),
            _ => Value::Object(FrozenValue::new(owner, snapshot, self.graph(id)?)?),
        })
    }
}
