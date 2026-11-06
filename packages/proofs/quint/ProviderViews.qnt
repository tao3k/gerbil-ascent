// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ProviderViews {
  const Rows: Set[int]
  const Budget: int
  const Mutation: str
  const ExplorationBound: int
  type View = (int, Set[int])
  type State = {generation: int, committed: Set[int], published: View, candidate: Set[int], phase: str, reading: bool,
    canceled: bool, alive: bool, captured: View, observed: View, replyAccepted: bool, replyRevision: int, replyRows: Set[int]}
  var q: State
  pure def DescriptorCount(cut: Set[int]): int = if (cut == Set()) 0 else 1
  action init = q' = {generation: 0, committed: Set(), published: (0,Set()), candidate: Set(), phase: "idle", reading: false,
    canceled: false, alive: false, captured: (0,Set()), observed: (0,Set()), replyAccepted: false, replyRevision: 0, replyRows: Set()}
  action Stage = {nondet cut = Rows.powerset().oneOf(); all {q.phase == "idle", cut != q.committed,
    q' = {...q, candidate: cut, phase: "staged", published: if (Mutation == "early") (q.generation+1,cut) else q.published}}}
  action Publish = all {q.phase == "staged", (if (Mutation == "budget") DescriptorCount(q.candidate) else q.candidate.size()) <= Budget,
    q' = {...q, generation: q.generation+1, committed: q.candidate, published: (q.generation+1,q.candidate), phase: "idle",
      observed: if (Mutation == "alias" and q.reading) (q.generation+1,q.candidate) else q.observed, replyAccepted: false}}
  action Reject = all {q.phase == "staged", q.candidate.size() > Budget, q' = {...q, phase: "idle"}}
  action Borrow = all {not(q.reading), not(q.replyAccepted), q' = {...q, reading: true, canceled: false, alive: true, captured: q.published, observed: q.published}}
  action Cancel = all {q.reading, not(q.canceled), q' = {...q, canceled: true, alive: if (Mutation == "retire") false else q.alive}}
  action Drain = all {q.reading, q.canceled, q' = {...q, reading: false, alive: false}}
  action Reply = all {q.reading, not(q.canceled), q.captured._1 == q.generation or Mutation == "stale",
    q' = {...q, replyAccepted: true, replyRevision: q.captured._1, replyRows: q.observed._2, reading: false, alive: false}}
  action Discard = all {q.reading, not(q.canceled), q.captured._1 != q.generation, Mutation != "stuck", q' = {...q, reading: false, alive: false}}
  action step = any {Stage, Publish, Reject, Borrow, Cancel, Drain, Reply, Discard}
  val Explore = q.generation <= ExplorationBound
  val AtomicPublication = q.published == (q.generation,q.committed)
  val FrozenRead = q.reading implies q.observed == q.captured
  val ReaderAlive = q.reading implies q.alive
  val CurrentReply = q.replyAccepted implies (q.replyRevision == q.generation and q.replyRows == q.committed)
  val LogicalBudget = q.committed.size() <= Budget

}
