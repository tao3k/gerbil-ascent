// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite publication protocol; no Rust memory-model or liveness claim.
module RayonPublication {
  const Mutation: str
  pure val Tasks = Set(0,1)
  pure val Relations = Set(0,1)
  type Fact = (int,int)
  pure val Facts = tuples(Relations,Set(0,1))
  pure val Base = Set((0,0))
  pure val FactLimit = 3
  pure val WorkLimit = 3
  type State = {active: Set[int], done: Set[int], pending: Set[Fact], frontier: Set[Fact], offered: Set[Fact], heads: Set[int], facts: int, work: int, stopped: bool, phase: str, snapshot: Set[Fact]}
  var q: State
  action init = q' = {active: Tasks, done: Set(), pending: Set(), frontier: Base, offered: Base, heads: Set(), facts: 1, work: 0, stopped: false, phase: "produce", snapshot: Base}
  action Offer(t: int, f: Fact): bool = all {
    q.phase == "produce", q.active.contains(t), not(q.stopped),
    val present = q.frontier.union(q.pending)
    val duplicate = if (Mutation == "digest") present.exists(x => x._2 == f._2) else present.contains(f)
    val cost = if (duplicate) 0 else 1
    if (q.work + 1 > WorkLimit or (q.facts + cost > FactLimit and Mutation != "uncapped"))
      q' = {...q, stopped: true}
    else q' = {...q, offered: q.offered.union(Set(f)), pending: if (duplicate) q.pending else q.pending.union(Set(f)), facts: q.facts + cost, work: q.work + 1}
  }
  action Finish(t: int): bool = all {q.phase == "produce", q.active.contains(t), q' = {...q, active: q.active.exclude(Set(t)), done: q.done.union(Set(t))}}
  action Join = all {q.phase == "produce", q.active == Set() or Mutation == "early", q' = {...q, phase: if (q.stopped) "failed" else "publish"}}
  action Publish(r: int): bool = all {
    q.phase == "publish", not(q.heads.contains(r)),
    val rows = q.pending.filter(f => f._1 == r)
    q' = {...q, frontier: q.frontier.union(rows), pending: q.pending.exclude(rows), heads: q.heads.union(Set(r))}
  }
  action Ready = all {q.phase == "publish", q.heads == Relations, q' = {...q, phase: "ready"}}
  action Stop = all {Set("produce","publish","ready").contains(q.phase), not(q.stopped), q' = {...q, stopped: true}}
  action Complete = all {q.phase == "ready", not(q.stopped) or Mutation == "late", q' = {...q, phase: "complete", snapshot: q.frontier}}
  action Reject = all {Set("publish","ready").contains(q.phase), q.stopped, q' = {...q, phase: "failed"}}
  action taskStep = {nondet t = Tasks.oneOf(); nondet f = Facts.oneOf(); any {Offer(t,f), Finish(t)}}
  action headStep = {nondet r = Relations.oneOf(); Publish(r)}
  action step = any {taskStep, Join, headStep, Ready, Stop, Complete, Reject}
  val TypeOK = all {q.active.subseteq(Tasks), q.done.subseteq(Tasks), q.pending.subseteq(Facts), q.frontier.subseteq(Facts), q.offered.subseteq(Facts), q.heads.subseteq(Relations), q.facts >= 1, q.work >= 0}
  val ExactFacts = q.facts == q.frontier.union(q.pending).size() and q.frontier.intersect(q.pending) == Set()
  val Bounded = q.facts <= FactLimit and q.work <= WorkLimit
  val JoinBarrier = Set("publish","ready","complete").contains(q.phase) implies q.active == Set()
  val SnapshotSafe = if (q.phase == "complete") not(q.stopped) and q.snapshot == q.frontier and q.pending == Set() else q.snapshot == Base
  val CompletionExact = q.phase == "complete" implies q.snapshot == q.offered
}

module RayonPublicationSimulation {
  import RayonPublication(Mutation = "none").*
}

module RayonPublicationCompletedTraces {
  import RayonPublication(Mutation = "none").*
  action twoOffers = {nondet t = Tasks.oneOf(); nondet f = Facts.oneOf(); all {q.work < 2, Offer(t,f)}}
  action finishOffers = {nondet t = Tasks.oneOf(); all {q.work == 2, Finish(t)}}
  // A successful schedule fixture. The main model still explores interruption,
  // exhaustion and all producer/publisher interleavings exhaustively.
  action completedStep = any {twoOffers, finishOffers, Join, headStep, Ready, Complete}
}
