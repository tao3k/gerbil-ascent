// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Stable IDs model duplicate source occurrences. Public selectors use current
// list positions. ResultOf is a finite graph, not the native grounded solver.
module WithdrawalSession {
  const Mutation: str
  pure def ResultOf(source: Set[int]): Set[int] =
    (if (source.contains(0) or source.contains(1)) Set(1) else Set()).union(
      if (source.contains(2)) Set(2) else Set()).union(
      if ((source.contains(0) or source.contains(1)) and source.contains(2)) Set(3) else Set())
  type State = {source: Set[int], graph: Set[int], rows: Set[int], generation: int,
    phase: str, pending: Set[int], expected: Set[int], native: Set[int], good: bool}
  var q: State
  action init = q' = {source: Set(0,1,2), graph: Set(0,1,2), rows: Set(1,2,3),
    generation: 0, phase: "idle", pending: Set(), expected: Set(), native: Set(), good: false}
  action Begin = {
    nondet position = Set(0,1,2).oneOf()
    val ordered = List(0,1,2).select(id => q.source.contains(id))
    all {q.phase == "idle", position < ordered.length(),
      q' = {...q, phase: "checking", good: false,
        expected: q.source.exclude(Set(ordered.nth(position))),
        pending: q.source.exclude(Set(if (Mutation == "ordinal") position else ordered.nth(position)))}}
  }
  action Check = {nondet good = Set(true,false).oneOf(); all {q.phase == "checking",
    q' = {...q, phase: "ready", good: good,
      native: if (good) ResultOf(q.pending) else Set(9)}}}
  action Commit = all {q.phase == "ready", q.good or Mutation == "unchecked",
    q' = {...q, phase: "idle", generation: q.generation+1, source: q.pending, rows: q.native,
      graph: if (Mutation == "staleGraph") q.graph else q.pending}}
  action Abort = all {q.phase != "idle", q' = {...q, phase: "idle"}}
  action Early = all {q.phase == "checking", Mutation == "early", q' = {...q, source: q.pending}}
  action step = any {Begin, Check, Commit, Abort, Early}
  val AtomicSnapshot = q.rows == ResultOf(q.source) and q.graph == q.source
  val CurrentOrdinal = q.phase == "idle" or q.pending == q.expected
  val ExplorationBound = q.generation <= 3
}
