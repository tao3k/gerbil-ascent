// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module SessionTransaction {
  const GenerationCutoff: int
  const Mutation: str
  type Cut = (int,int,int)
  pure val Cuts = tuples(Set(0,1),Set(0,1),Set(0,1))
  pure def ResultOf(cut: Cut): Set[int] = if (cut._1 == 1 or (cut._2 == 1 and cut._3 == 0)) Set(1) else Set()
  pure def GlobalResultOf(cut: Cut): Set[int] = if ((cut._1 == 1 or cut._2 == 1) and cut._3 == 0) Set(1) else Set()
  type State = {generation: int, source: Cut, result: Set[int], phase: str, base: int, pending: Cut, candidate: Set[int], complete: bool}
  var q: State
  action init = q' = {generation: 0, source: (0,0,0), result: Set(), phase: "idle", base: -1, pending: (0,0,0), candidate: Set(), complete: false}
  action Begin = {nondet cut = Cuts.oneOf(); all {q.phase == "idle", q' = {...q, pending: cut, base: q.generation, phase: "solving", candidate: Set(), complete: false}}}
  action Solve = all {q.phase == "solving", q' = {...q,
    candidate: if (Mutation == "global") GlobalResultOf(q.pending)
      else if (Mutation == "reuse" and q.pending._1 == q.source._1 and q.pending._2 == q.source._2 and q.pending._3 != q.source._3) q.result
      else ResultOf(q.pending), complete: true, phase: "ready"}}
  action ExternalCommit = {nondet cut = Cuts.oneOf(); q' = {...q, source: cut, result: ResultOf(cut), generation: q.generation+1}}
  action Commit = all {q.phase == "ready", q.complete, q.base == q.generation or Mutation == "stale",
    q' = {...q, generation: q.generation+1, source: q.pending, result: q.candidate, phase: "idle"}}
  action Abort = all {q.phase != "idle", q' = {...q, phase: "idle", complete: false, candidate: Set()}}
  action EarlyPublish = all {Mutation == "early", q.phase == "solving", q' = {...q, source: q.pending}}
  action step = any {Begin, Solve, Commit, Abort, ExternalCommit, EarlyPublish}
  val TypeOK = all {q.generation >= 0, Cuts.contains(q.source), Cuts.contains(q.pending), q.result.subseteq(Set(1)), q.candidate.subseteq(Set(1)),
    q.base >= -1, Set("idle","solving","ready").contains(q.phase), Set(true,false).contains(q.complete)}
  val ExplorationBound = q.generation <= GenerationCutoff
  val AtomicSnapshot = q.result == ResultOf(q.source)
  temporal NoStaleCommit = (Commit implies q.base == q.generation).orKeep(q).always()
  temporal AbortPreservesSnapshot = (Abort implies (q.generation,q.source,q.result).next() == (q.generation,q.source,q.result)).orKeep(q).always()

}
