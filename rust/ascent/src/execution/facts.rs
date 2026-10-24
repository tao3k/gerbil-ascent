//! Query-local `SipHash` digests travel with immutable rows between dedup sets.
use super::values::Row;
use std::{
    collections::{HashSet, hash_map::RandomState},
    hash::{BuildHasher, BuildHasherDefault, Hash, Hasher},
};

/// Digest collisions still compare the complete typed row. Every set in one
/// evaluation shares its digest authority; no digest crosses a request boundary.
#[derive(Clone, Debug)]
pub(crate) struct Fact {
    pub row: Row,
    digest: u64,
}
impl Fact {
    pub fn new(row: Row, authority: &RandomState) -> Self {
        Self {
            digest: authority.hash_one(&row),
            row,
        }
    }
}
impl PartialEq for Fact {
    fn eq(&self, other: &Self) -> bool {
        self.digest == other.digest && self.row == other.row
    }
}
impl Eq for Fact {}
impl Hash for Fact {
    fn hash<H: Hasher>(&self, state: &mut H) {
        state.write_u64(self.digest);
    }
}
/// Only `Fact` may key these private sets. Its digest was already produced by
/// randomized `SipHash`; hashing that digest again buys no collision protection.
#[derive(Default)]
pub(crate) struct DigestHasher(u64);
impl Hasher for DigestHasher {
    fn finish(&self) -> u64 {
        self.0
    }
    fn write(&mut self, _bytes: &[u8]) {
        unreachable!("Fact writes exactly one digest")
    }
    fn write_u64(&mut self, digest: u64) {
        self.0 = digest;
    }
}
pub(crate) type FactSet = HashSet<Fact, BuildHasherDefault<DigestHasher>>;

#[cfg(test)]
#[path = "../../tests/unit/facts.rs"]
mod tests;
