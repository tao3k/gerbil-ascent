//! Result leases are invalidated by release, source replacement or owner close.
use crate::{Engine, Error, Result, Row, Snapshot};
use std::{
    collections::BTreeMap,
    sync::{
        Arc,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};
pub(super) struct Scope {
    pub identity: u64,
    pub engine: Engine,
    pub generation: u64,
    pub closed: AtomicBool,
    pub owners: AtomicUsize,
}
impl Scope {
    pub fn check(&self) -> Result<()> {
        self.engine.check()?;
        if self.closed.load(Ordering::Acquire) {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
}
struct Retained {
    scope: Arc<Scope>,
    snapshot: Arc<Snapshot>,
    queries: Arc<[String]>,
    aliases: Arc<BTreeMap<String, String>>,
    released: AtomicBool,
}
impl Retained {
    fn release(&self) {
        if !self.released.swap(true, Ordering::AcqRel) {
            self.scope.owners.fetch_sub(1, Ordering::AcqRel);
        }
    }
}
impl Drop for Retained {
    fn drop(&mut self) {
        self.release();
    }
}
/// Owned result scoped to the source generation that produced it.
#[derive(Clone)]
pub struct SourceResult(Arc<Retained>);
impl SourceResult {
    pub(super) fn retain(
        scope: Arc<Scope>,
        snapshot: Arc<Snapshot>,
        queries: Arc<[String]>,
        aliases: Arc<BTreeMap<String, String>>,
    ) -> Result<Self> {
        scope.check()?;
        scope
            .owners
            .try_update(Ordering::AcqRel, Ordering::Acquire, |n| {
                (n < 64).then_some(n + 1)
            })
            .map_err(|_| Error::InvalidUpdate("result owner limit; release results".into()))?;
        Ok(Self(Arc::new(Retained {
            scope,
            snapshot,
            queries,
            aliases,
            released: AtomicBool::new(false),
        })))
    }
    pub(crate) fn fork(&self) -> Result<Self> {
        self.check()?;
        Self::retain(
            self.0.scope.clone(),
            self.0.snapshot.clone(),
            self.0.queries.clone(),
            self.0.aliases.clone(),
        )
    }
    pub(super) fn released(&self) -> bool {
        self.0.released.load(Ordering::Acquire)
    }
    fn check(&self) -> Result<()> {
        self.0.scope.check()?;
        if self.released() {
            Err(Error::Closed)
        } else {
            Ok(())
        }
    }
    /// # Errors
    /// Closed, released, stale-generation and unknown-query owners are rejected.
    pub fn rows(&self, relation: &str) -> Result<&[Row]> {
        let name = self.resolve(relation)?;
        Ok(&self.0.snapshot.relations[name])
    }
    pub(crate) fn resolve(&self, relation: &str) -> Result<&str> {
        self.check()?;
        if !self.0.queries.iter().any(|query| query == relation) {
            return Err(Error::InvalidUpdate("unknown result relation".into()));
        }
        self.0
            .aliases
            .get(relation)
            .map(String::as_str)
            .ok_or_else(|| Error::InvalidUpdate("unknown result export".into()))
    }
    /// Retain a typed cell reference without serializing or walking its graph.
    /// # Errors
    /// Rejects unknown queries, invalid coordinates and revoked result authority.
    pub fn value(&self, relation: &str, row: usize, column: usize) -> Result<RowValue> {
        let value = self
            .rows(relation)?
            .get(row)
            .and_then(|row| row.get(column))
            .cloned()
            .ok_or_else(|| Error::InvalidUpdate("result value coordinate".into()))?;
        Ok(RowValue {
            owner: self.clone(),
            value,
        })
    }
    /// # Errors
    /// Rejects released or invalidated owners.
    pub fn relations(&self) -> Result<&BTreeMap<String, Vec<Row>>> {
        self.check()?;
        Ok(&self.0.snapshot.relations)
    }
    /// Process-local source-session identity, preserved across successful replacements.
    /// # Errors
    /// Rejects released or invalidated owners.
    pub fn identity(&self) -> Result<u64> {
        self.check()?;
        Ok(self.0.scope.identity)
    }
    /// # Errors
    /// Rejects released or invalidated owners.
    pub fn generation(&self) -> Result<u64> {
        self.check()?;
        Ok(self.0.scope.generation)
    }
    /// Release is idempotent and immediately returns one slot to this scope.
    #[must_use]
    pub fn is_released(&self) -> bool {
        self.0.released.load(Ordering::Acquire)
    }
    pub fn close(&self) {
        self.0.release();
    }
}

/// Result-scoped typed value reference; observation does not grant callable authority.
#[derive(Clone)]
pub struct RowValue {
    owner: SourceResult,
    value: crate::Value,
}
impl RowValue {
    pub(super) fn in_scope(&self, scope: &Arc<Scope>) -> bool {
        Arc::ptr_eq(scope, &self.owner.0.scope)
    }

    /// # Errors
    /// Release, source replacement and engine/session closure revoke admission.
    pub fn value(&self) -> Result<crate::Value> {
        self.owner.check()?;
        Ok(self.value.clone())
    }
}

impl std::fmt::Debug for RowValue {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RowValue").finish_non_exhaustive()
    }
}
