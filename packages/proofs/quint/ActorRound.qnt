// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorRound {
  const Workers: Set[int]
  const GenerationCutoff: int
  const RoundCutoff: int
  const Mutation: str
  type Message = {epoch: int, tick: int, owner: int, rows: Set[int]}
  type State = {generation: int, round: int, seed: Set[int], frozen: Set[int], total: Set[int], delta: Set[int], done: Set[int], outstanding: Set[int],
    workGeneration: int, mailbox: Set[Message], history: Set[Message], accepted: Set[Message], phase: str, publishedSeed: Set[int], published: Set[int], badBarrier: bool}
  var q: State
  pure val Seeds = Set(Set(1), Set(2))
  pure def Rows(worker: int, cut: Set[int]): Set[int] = if (worker == 1) {if (cut.contains(1)) Set(2) else Set()} else {if (cut.contains(2)) Set(3) else Set()}
  pure def Closure(input: Set[int]): Set[int] = if (input.contains(1)) Set(1,2,3) else Set(2,3)
  def message(worker: int): Message = {epoch: q.workGeneration, tick: q.round, owner: worker, rows: Rows(worker,q.frozen)}
  action init = q' = {generation: 0, round: 0, seed: Set(2), frozen: Set(2), total: Set(2), delta: Set(), done: Set(), outstanding: Set(), workGeneration: 0,
    mailbox: Set(), history: Set(), accepted: Set(), phase: "idle", publishedSeed: Set(2), published: Set(2,3), badBarrier: false}
  action Start = {nondet input = Seeds.oneOf(); all {Set("idle","complete","canceled").contains(q.phase),
    q' = {...q, seed: input, total: input, frozen: input, generation: q.generation+1, workGeneration: q.generation+1, round: 0,
      done: Set(), delta: Set(), accepted: Set(), outstanding: Workers, phase: "running"}}}
  action Reply(worker: int): bool = all {Set("running","draining").contains(q.phase), q.outstanding.contains(worker),
    q' = {...q, mailbox: q.mailbox.union(Set(message(worker))), history: q.history.union(Set(message(worker))), outstanding: q.outstanding.exclude(Set(worker))}}
  action Replay = {nondet msg = q.history.oneOf(); q' = {...q, mailbox: q.mailbox.union(Set(msg))}}
  def Current(msg: Message): bool = msg.epoch == q.generation and msg.tick == q.round
  action Accept = {nondet msg = q.mailbox.oneOf(); all {q.phase == "running", Current(msg) or Mutation == "stale", not(q.done.contains(msg.owner)),
    q' = {...q, done: q.done.union(Set(msg.owner)), delta: q.delta.union(msg.rows), accepted: q.accepted.union(Set(msg)), mailbox: q.mailbox.exclude(Set(msg))}}}
  action Drop = {nondet msg = q.mailbox.oneOf(); all {not(Current(msg)) or q.done.contains(msg.owner) or q.phase != "running", q' = {...q, mailbox: q.mailbox.exclude(Set(msg))}}}
  action Barrier = all {q.phase == "running", (q.done == Workers and q.outstanding == Set()) or Mutation == "early",
    q' = if (q.delta.subseteq(q.total))
      {...q, badBarrier: q.badBarrier or q.done != Workers or q.outstanding != Set(), published: q.total, publishedSeed: q.seed, phase: "complete"}
    else {...q, badBarrier: q.badBarrier or q.done != Workers or q.outstanding != Set(), total: q.total.union(q.delta), frozen: q.total.union(q.delta),
      round: q.round+1, delta: Set(), done: Set(), accepted: Set(), outstanding: Workers, workGeneration: q.generation, phase: "running"}}
  action Cancel = all {q.phase == "running", q' = {...q, phase: "draining", generation: q.generation+1, accepted: Set(),
    published: if (Mutation == "cancel") q.total else q.published, publishedSeed: if (Mutation == "cancel") q.seed else q.publishedSeed}}
  action CancelAck(worker: int): bool = all {q.phase == "draining", q.outstanding.contains(worker), q' = {...q, outstanding: q.outstanding.exclude(Set(worker))}}
  action Drained = all {q.phase == "draining", q.outstanding == Set(), q' = {...q, phase: "canceled"}}
  action workerStep = {nondet worker = Workers.oneOf(); any {Reply(worker), CancelAck(worker)}}
  action step = any {Start, Replay, Accept, Drop, Barrier, Cancel, Drained, workerStep}
  val CompletePublication = q.published == Closure(q.publishedSeed)
  val NoStaleCompletion = q.accepted.forall(msg => Current(msg))
  val CompleteBarrier = not(q.badBarrier)
  val Exploration = q.generation <= GenerationCutoff and q.round <= RoundCutoff

}
