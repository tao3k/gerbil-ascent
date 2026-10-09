// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Stable IDs distinguish duplicate source occurrences. The initial complete
// logical graph is immutable; storage can discard retired supports atomically.
// ResultOf is a finite graph, not the native grounded solver.
module WithdrawalSession {
  const Mutation: str
  pure val Initial = Set(0,1,2)
  pure val InitialOrder = List(0,1,2)
  pure def ResultOf(source: Set[int]): Set[int] =
    (if (source.contains(0) or source.contains(1)) Set(1) else Set()).union(
      if (source.contains(2)) Set(2) else Set()).union(
      if ((source.contains(0) or source.contains(1)) and source.contains(2)) Set(3) else Set())
  type State = {source: Set[int], graph: Set[int], storage: Set[int], priorStorage: Set[int],
    pendingStorage: Set[int], removed: Set[int], ids: List[int],
    savedSource: Set[int], savedRows: Set[int], rows: Set[int], generation: int, phase: str, pending: Set[int], expected: Set[int],
    pendingRemoved: Set[int], pendingIds: List[int], candidate: Set[int], good: bool}
  var q: State
  action init = q' = {source: Initial, graph: Initial, storage: Initial, priorStorage: Initial,
    pendingStorage: Initial, removed: Set(), ids: InitialOrder,
    savedSource: Set(), savedRows: Set(), rows: Set(1,2,3), generation: 0, phase: "idle", pending: Set(), expected: Set(),
    pendingRemoved: Set(), pendingIds: List(), candidate: Set(), good: false}
  action Begin = {
    nondet position = Set(0,1,2).oneOf()
    val token = q.ids.nth(position)
    all {q.phase == "idle", position < q.ids.length(),
      q' = {...q, phase: "checking", good: false, priorStorage: q.storage,
        expected: q.source.exclude(Set(token)),
        pending: q.source.exclude(Set(if (Mutation == "ordinal") position else token)),
        pendingIds: q.ids.select(id => id != token),
        pendingRemoved: if (Mutation == "forgetRemoved") Set(token) else q.removed.union(Set(token))}}
  }
  action Check = {nondet good = Set(true,false).oneOf(); all {q.phase == "checking",
    q' = {...q, phase: "ready", good: good,
      candidate: if (good) ResultOf(q.storage.exclude(q.pendingRemoved)) else Set(9)}}}
  action Commit = all {q.phase == "ready", q.good or Mutation == "unchecked",
    q' = {...q, phase: "idle", generation: q.generation+1, source: q.pending, rows: q.candidate,
      savedRows: if (Mutation == "borrowObservation") q.candidate else q.savedRows,
      graph: if (Mutation == "graphEdit") q.pending else q.graph, removed: q.pendingRemoved,
      ids: if (Mutation == "rebase") InitialOrder.select(id => id < q.pendingIds.length()) else q.pendingIds}}
  action Abort = all {q.phase != "idle", q' = {...q, phase: "idle"}}
  action Early = all {q.phase == "checking", Mutation == "early", q' = {...q, source: q.pending}}
  action Observe = all {q.phase == "idle", q' = {...q, savedSource: q.source, savedRows: q.rows}}
  action BeginCompact = all {q.phase == "idle",
    q' = {...q, phase: "compactChecking", good: false, priorStorage: q.storage,
      pendingStorage: if (Mutation == "compactLoss") Set() else q.storage.intersect(q.source)}}
  action CheckCompact = {nondet good = Set(true,false).oneOf(); all {
    q.phase == "compactChecking", q' = {...q, phase: "compactReady", good: good}}}
  action CommitCompact = all {q.phase == "compactReady", q.good,
    q' = {...q, phase: "idle", storage: q.pendingStorage,
      ids: if (Mutation == "compactRebase") InitialOrder.select(id => id < q.ids.length()) else q.ids}}
  action EarlyCompact = all {q.phase == "compactChecking", Mutation == "compactEarly",
    q' = {...q, storage: q.pendingStorage}}
  action step = any {Begin, Check, Commit, Abort, Early, Observe,
    BeginCompact, CheckCompact, CommitCompact, EarlyCompact}
  val AtomicSnapshot = q.rows == ResultOf(q.source) and q.graph.exclude(q.removed) == q.source
  val FrozenGraph = q.graph == Initial
  val CurrentTokens = q.ids == InitialOrder.select(id => q.source.contains(id))
  val CurrentOrdinal = not(Set("checking", "ready").contains(q.phase)) or q.pending == q.expected
  val CumulativeSupport = not(Set("checking", "ready").contains(q.phase)) or q.storage.exclude(q.pendingRemoved) == q.expected
  val SupportCoverage = q.storage.exclude(q.removed) == q.source and q.storage.subseteq(Initial)
  val StorageAtomic = q.phase == "idle" or q.storage == q.priorStorage
  val HistoricalObservation = q.savedRows == ResultOf(q.savedSource)
  val ExplorationBound = q.generation <= 3
}
