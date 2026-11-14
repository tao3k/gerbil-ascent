// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorSession {
  const Cuts: Set[int]
  const GenerationCutoff: int
  const Mutation: str
  type State = {generation: int, epoch: int, pending: int, committed: int, published: Set[int], publishedCut: int,
    frozen: int, phase: str, assigned: bool, closing: bool, stalePublish: bool, earlyClose: bool}
  var q: State
  pure def Result(cut: int): Set[int] = Set(cut)
  action init = q' = {generation: 0, epoch: 0, pending: 0, committed: 0, published: Result(0), publishedCut: 0,
    frozen: 0, phase: "idle", assigned: false, closing: false, stalePublish: false, earlyClose: false}
  action Update = {nondet cut = Cuts.oneOf(); all {q.phase == "idle", not(q.closing), q' = {...q, pending: cut, generation: q.generation + 1}}}
  action Start = all {q.phase == "idle", not(q.closing), q' = {...q, generation: q.generation + 1, epoch: q.generation + 1, frozen: q.pending, phase: "running", assigned: true}}
  action Cancel = all {Set("running", "draining").contains(q.phase), q' = {...q, generation: q.generation + 1, phase: "draining"}}
  action Finish(success: bool): bool = all {q.assigned, Set("running", "draining").contains(q.phase),
    q' = if (success and (q.epoch == q.generation or Mutation == "stale"))
      {...q, published: Result(q.frozen), publishedCut: q.frozen, committed: q.frozen,
        stalePublish: q.stalePublish or q.epoch != q.generation, assigned: false, phase: "idle"}
    else {...q, pending: q.committed, assigned: false, phase: "idle"}}
  action RequestClose = all {q.phase != "closed", not(q.closing), q' = {...q, closing: true,
    generation: if (q.assigned) q.generation + 1 else q.generation, phase: if (q.assigned) "draining" else q.phase}}
  action Close = all {q.closing, q.phase != "closed", not(q.assigned) or Mutation == "early", q' = {...q, phase: "closed", earlyClose: q.earlyClose or q.assigned}}
  action step = any {Update, Start, Cancel, Finish(true), Finish(false), RequestClose, Close}
  val ConsistentPublication = q.published == Result(q.publishedCut) and q.committed == q.publishedCut
  val NoStalePublication = not(q.stalePublish)
  val DrainedClose = not(q.earlyClose) and (q.phase == "closed" implies not(q.assigned))
  // Only the checker configuration references this predicate; step is unbounded.
  val Exploration = q.generation <= GenerationCutoff

}
