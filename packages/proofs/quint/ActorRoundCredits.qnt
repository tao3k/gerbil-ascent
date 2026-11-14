// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorRoundCredits {
  const Tasks: Set[int]
  const Capacity: int
  const EarlyReturn: bool
  type State = {queued: Set[int], active: Set[int], waiting: Set[int], terminal: Set[int], stopped: bool, returned: bool}
  var q: State
  action init = q' = {queued: Tasks, active: Set(), waiting: Set(), terminal: Set(), stopped: false, returned: false}
  action Dispatch(t: int): bool = all {not(q.stopped), not(q.returned), q.queued.contains(t), q.active.size() < Capacity,
    q' = {...q, queued: q.queued.exclude(Set(t)), active: q.active.union(Set(t))}}
  action Offer(t: int): bool = all {not(q.returned), q.active.exclude(q.waiting).contains(t), q' = {...q, waiting: q.waiting.union(Set(t))}}
  action Credit(t: int): bool = all {not(q.returned), q.waiting.contains(t), q' = {...q, waiting: q.waiting.exclude(Set(t))}}
  action Stop = all {not(q.returned), not(q.stopped), q' = {...q, stopped: true}}
  action Finish(t: int): bool = all {not(q.returned), q.active.exclude(q.waiting).contains(t),
    q' = {...q, active: q.active.exclude(Set(t)), terminal: q.terminal.union(Set(t))}}
  action Return = all {not(q.returned), EarlyReturn or (q.active == Set() and (q.stopped or q.queued == Set())), q' = {...q, returned: true}}
  action taskStep = {nondet t = Tasks.oneOf(); any {Dispatch(t), Offer(t), Credit(t), Finish(t)}}
  action step = any {Stop, Return, taskStep}
  val Partition = all {q.queued.union(q.active).union(q.terminal) == Tasks,
    q.queued.intersect(q.active) == Set(), q.queued.intersect(q.terminal) == Set(), q.active.intersect(q.terminal) == Set()}
  val BoundedCredit = q.waiting.subseteq(q.active) and q.waiting.size() <= Capacity
  val BoundedAssigned = q.active.size() <= Capacity
  val CompleteReturn = q.returned implies all {q.active == Set(), q.waiting == Set(), q.stopped or q.queued == Set()}

}
