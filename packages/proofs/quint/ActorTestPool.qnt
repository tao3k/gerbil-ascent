// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorTestPool {
  const Tasks: Set[int]
  const Capacity: int
  const EarlyReturn: bool
  type State = {pending: Set[int], active: Set[int], waiting: Set[int], terminal: Set[int], canceled: Set[int], failed: bool, returned: bool}
  var q: State
  action init = q' = {pending: Tasks, active: Set(), waiting: Set(), terminal: Set(), canceled: Set(), failed: false, returned: false}
  action Dispatch(t: int): bool = all {not(q.returned), not(q.failed), q.pending.contains(t), q.active.size() < Capacity,
    q' = {...q, pending: q.pending.exclude(Set(t)), active: q.active.union(Set(t))}}
  action Offer(t: int): bool = all {not(q.returned), q.active.exclude(q.waiting).contains(t), q' = {...q, waiting: q.waiting.union(Set(t))}}
  action Ack(t: int): bool = all {not(q.returned), q.waiting.contains(t), q' = {...q, waiting: q.waiting.exclude(Set(t))}}
  action Finish(t: int): bool = all {not(q.returned), q.active.exclude(q.waiting).contains(t),
    q' = {...q, active: q.active.exclude(Set(t)), terminal: q.terminal.union(Set(t))}}
  action Fail(t: int): bool = all {not(q.returned), q.active.exclude(q.waiting).contains(t),
    q' = {...q, active: q.active.exclude(Set(t)), terminal: q.terminal.union(Set(t)), canceled: q.canceled.union(q.pending), pending: Set(), failed: true}}
  action SinkFault(t: int): bool = all {not(q.returned), q.waiting.contains(t),
    q' = {...q, waiting: q.waiting.exclude(Set(t)), canceled: q.canceled.union(q.pending), pending: Set(), failed: true}}
  action Return = all {not(q.returned), q.pending == Set(), q.active == Set() or EarlyReturn, q' = {...q, returned: true}}
  action taskStep = {nondet t = Tasks.oneOf(); any {Dispatch(t), Offer(t), Ack(t), Finish(t), Fail(t), SinkFault(t)}}
  action step = any {taskStep, Return}
  val Partition = all {q.pending.union(q.active).union(q.terminal).union(q.canceled) == Tasks,
    q.pending.intersect(q.active) == Set(), q.pending.intersect(q.terminal) == Set(), q.pending.intersect(q.canceled) == Set(),
    q.active.intersect(q.terminal) == Set(), q.active.intersect(q.canceled) == Set(), q.terminal.intersect(q.canceled) == Set()}
  val BoundedCredits = all {q.waiting.subseteq(q.active), q.active.size() <= Capacity, q.waiting.size() <= Capacity}
  val StoppedAdmission = q.failed implies q.pending == Set()
  val CompleteReturn = q.returned implies all {q.pending == Set(), q.active == Set(), q.waiting == Set()}

}
