// Generated from ExecutionPolicy.lean (ArchivePolicy); formal CI checks exact source.
pub const CACHE_PARENT_LEVELS: usize = 4;
pub const CACHE_NAMESPACE: &str = "ascent-program-v1";
#[derive(Default)]
pub struct Metrics {
    pub starts: usize,
    pub completed: usize,
    pub pending: usize,
    pub failed: usize,
    pub invalid: usize,
    pub changed: usize,
    pub sources: usize,
    pub builder_ok: bool,
    pub graph_ok: bool,
}
#[rustfmt::skip]
pub fn decode(state: &str, timed: bool, phase: &str) -> Option<usize> {
    match (state, timed, phase == "program-plan") {
        ("start", false, _) => Some(0),
        ("complete", true, _) => Some(1),
        ("cached", false, _) => Some(2),
        ("failed", true, _) => Some(3),
        ("complete", false, true) => Some(4),
        _ => None,
    }
}
#[rustfmt::skip]
pub fn compilation_units(phase: &str, kind: usize) -> usize {
    usize::from(phase == "native-object" && kind == 0)
}
#[rustfmt::skip]
pub fn complete(m: &Metrics) -> bool {
    m.builder_ok && m.graph_ok && m.starts == m.completed && m.pending == 0 && m.failed == 0 && m.invalid == 0 && m.changed == 0 && 0 < m.sources
}
