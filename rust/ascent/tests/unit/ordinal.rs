use super::{OrdinalRows, extent};
use crate::{
    Value,
    execution::{Values, values::Row},
};
use std::{collections::HashMap, sync::Arc};

#[test]
fn all_mixed_histories_match_hash_lookup_and_preserve_occurrence_order() {
    let mut values = Values::default();
    let cells: Vec<_> = (0..257).map(|n| values.intern(&Value::from(n))).collect();
    for stride in [1, 3, 17, 127, 256] {
        let mut actual: OrdinalRows = OrdinalRows::default();
        let mut expected: HashMap<_, Vec<Row>> = HashMap::new();
        for step in 0..1028 {
            let key = cells[(step * stride) % cells.len()];
            let row: Row = Arc::new([cells[step % cells.len()], key]);
            actual.insert(key, row.clone());
            expected.entry(key).or_default().push(row);
            assert!(actual.dense.len() <= 2 * expected.len() + 6);
            assert_eq!(actual.dense_keys + actual.sparse.len(), expected.len());
            for key in &cells {
                assert_eq!(actual.get(*key), expected.get(key));
            }
        }
    }
}

#[test]
fn sparse_keys_promote_whole_bins_without_changing_typed_identity() {
    let mut values = Values::default();
    let mut keys: Vec<_> = (0..4096).map(|n| values.intern(&Value::from(n))).collect();
    keys.extend([
        values.intern(&Value::Boolean(false)),
        values.intern(&Value::Symbol("0".into())),
        values.intern(&Value::from("0")),
    ]);
    let mut actual: OrdinalRows = OrdinalRows::default();
    let mut expected: HashMap<_, Vec<Row>> = HashMap::new();
    for key in keys[2048..].iter().chain(&keys[..2048]) {
        for tag in [keys[0], keys[1]] {
            let row: Row = Arc::new([tag, *key]);
            actual.insert(*key, row.clone());
            expected.entry(*key).or_default().push(row);
        }
    }
    // These high typed keys were initially too sparse. A subsequent append
    // now has enough occupied keys to promote their whole existing bins.
    for key in &keys[4096..] {
        let row: Row = Arc::new([keys[1], *key]);
        actual.insert(*key, row.clone());
        expected.entry(*key).or_default().push(row);
    }
    assert!(actual.sparse.is_empty());
    for key in keys {
        assert_eq!(actual.get(key), expected.get(&key));
    }
}

#[test]
fn arbitrary_large_ordinals_and_overflow_never_request_a_dense_allocation() {
    for index in [1024, 1_000_000, usize::MAX / 2, usize::MAX - 1, usize::MAX] {
        assert_eq!(extent(index, 0, 0), None);
    }
    assert_eq!(extent(0, usize::MAX, 0), None);
    assert_eq!(extent(0, 0, usize::MAX), None);
}

#[derive(Clone, Default)]
struct CountingState {
    seed: std::collections::hash_map::RandomState,
    calls: Arc<std::sync::atomic::AtomicUsize>,
}
struct CountingHasher {
    inner: std::collections::hash_map::DefaultHasher,
    calls: Arc<std::sync::atomic::AtomicUsize>,
}
impl std::hash::BuildHasher for CountingState {
    type Hasher = CountingHasher;
    fn build_hasher(&self) -> Self::Hasher {
        CountingHasher {
            inner: self.seed.build_hasher(),
            calls: self.calls.clone(),
        }
    }
}
impl std::hash::Hasher for CountingHasher {
    fn finish(&self) -> u64 {
        self.calls
            .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        self.inner.finish()
    }
    fn write(&mut self, bytes: &[u8]) {
        self.inner.write(bytes);
    }
}

#[test]
fn occupied_dense_reads_preserve_rows_without_rehashing_each_query() {
    use std::sync::atomic::Ordering;
    let mut values = Values::default();
    let keys: Vec<_> = (0..1024).map(|n| values.intern(&Value::from(n))).collect();
    let mut actual = OrdinalRows::<CountingState>::default();
    let mut expected: HashMap<_, Vec<Row>, CountingState> = HashMap::default();
    for key in &keys {
        let row: Row = Arc::new([*key]);
        actual.insert(*key, row.clone());
        expected.entry(*key).or_default().push(row);
    }
    let direct = actual.sparse.hasher().calls.clone();
    let direct_before = direct.load(Ordering::Relaxed);
    let hashed = expected.hasher().calls.clone();
    let hashed_before = hashed.load(Ordering::Relaxed);
    for i in 0..10_000 {
        let key = keys[i % keys.len()];
        assert_eq!(actual.get(key), expected.get(&key));
    }
    assert_eq!(direct.load(Ordering::Relaxed) - direct_before, 0);
    assert_eq!(hashed.load(Ordering::Relaxed) - hashed_before, 10_000);
}
