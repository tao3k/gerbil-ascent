// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module CertificateMaterial {
  const Mutation: str
  pure val Rows = Set(0,1,2,3)
  pure def Width(id: int): int = id
  type State = {phase: str, reserved: Set[int], copied: Set[int], pending: int,
    rows: int, cells: int, failed: bool, published: Set[int]}
  var q: State
  action init = q' = {phase: "working", reserved: Set(), copied: Set(), pending: -1,
    rows: 0, cells: 0, failed: false, published: Set()}
  pure def Fits(s: State, id: int): bool = Width(id) <= 2 and s.rows < 2 and s.cells + Width(id) <= 3
  action Reserve(id: int): bool = all {
    (q.phase == "working" or (Mutation == "resume" and q.phase == "bounded")), q.pending == -1,
    q' = if (q.reserved.contains(id)) q else if (Fits(q,id))
      {...q, phase: "working", reserved: q.reserved.union(Set(id)), pending: id,
        rows: q.rows + (if (Mutation == "seed-skip" and id == 0) 0 else 1), cells: q.cells + Width(id)}
    else {...q, phase: "bounded", failed: true,
      copied: if (Mutation == "late") q.copied.union(Set(id)) else q.copied,
      published: if (Mutation == "partial") q.copied else Set()}
  }
  action Copy = all {q.phase == "working", q.pending != -1,
    q' = {...q, copied: q.copied.union(Set(q.pending)), pending: -1}}
  // Completion assumes an independently established replay fixed point.
  action Complete = all {q.phase == "working", q.pending == -1,
    q' = {...q, phase: "complete", published: q.copied}}
  action reserveStep = {nondet id = Rows.oneOf(); Reserve(id)}
  action step = any {reserveStep, Copy, Complete}
  val CountExact = q.rows == q.reserved.size() and q.cells == q.reserved.fold(0,(sum,id) => sum + Width(id))
  val UsageBounds = q.rows <= 2 and q.cells <= 3 and q.reserved.forall(id => Width(id) <= 2)
  val ReservedBeforeCopy = q.copied.subseteq(q.reserved)
  val NoPartialPublication = (q.phase != "complete" implies q.published == Set()) and
    (q.phase == "complete" implies q.published == q.copied and not(q.failed))
  val FailureTerminal = q.failed implies q.phase == "bounded"
}
