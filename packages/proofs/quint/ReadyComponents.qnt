// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReadyComponents {
  const Tasks: Set[int]
  const Capacity: int
  const Mutation: str
  pure def Pred(task: int): Set[int] = if (task == 2) Set(1) else Set()
  pure def Facts(tasks: Set[int]): Set[(int, str)] = tuples(tasks, Set("batch", "tail"))
  type State = {queued: Set[int], active: Set[int], done: Set[int], stopped: bool, returned: bool, badDispatch: bool,
    offered: Set[int], waiting: Set[int], merged: Set[(int, str)], snapshot: int -> Set[(int, str)]}
  var q: State
  action init = q' = {queued: Tasks, active: Set(), done: Set(), stopped: false, returned: false, badDispatch: false,
    offered: Set(), waiting: Set(), merged: Set(), snapshot: Tasks.mapBy(_ => Set())}
  action Dispatch(t: int): bool = all {not(q.stopped), not(q.returned), q.queued.contains(t), q.active.size() < Capacity,
    Pred(t).subseteq(q.done) or Mutation == "prerequisite",
    q' = {...q, badDispatch: q.badDispatch or not(Pred(t).subseteq(q.done)), queued: q.queued.exclude(Set(t)), active: q.active.union(Set(t)),
      snapshot: q.snapshot.set(t, if (Mutation == "snapshot") Set() else q.merged)}}
  action Offer(t: int): bool = all {not(q.returned), q.active.exclude(q.offered).contains(t),
    q' = {...q, offered: q.offered.union(Set(t)), waiting: q.waiting.union(Set(t))}}
  action Merge(t: int): bool = all {not(q.returned), q.waiting.contains(t),
    q' = {...q, waiting: q.waiting.exclude(Set(t)), merged: if (q.stopped) q.merged else q.merged.union(Set((t,"batch")))}}
  action Complete(t: int): bool = all {not(q.returned), q.active.contains(t),
    (not(q.waiting.contains(t)) and (q.offered.contains(t) or q.stopped)) or Mutation == "credit",
    q' = {...q, active: q.active.exclude(Set(t)), done: q.done.union(Set(t)),
      merged: if (q.stopped or Mutation == "tail") q.merged else q.merged.union(Set((t,"tail")))}}
  action Cancel = all {not(q.returned), not(q.stopped), q' = {...q, stopped: true}}
  action Return = all {not(q.returned), (q.active == Set() and (q.stopped or q.queued == Set())) or Mutation == "early", q' = {...q, returned: true}}
  action taskStep = {nondet t = Tasks.oneOf(); any {Dispatch(t), Offer(t), Merge(t), Complete(t)}}
  action step = any {Cancel, Return, taskStep}
  val Partition = all {q.queued.union(q.active).union(q.done) == Tasks, q.queued.intersect(q.active) == Set(), q.queued.intersect(q.done) == Set(), q.active.intersect(q.done) == Set()}
  val Prerequisites = not(q.badDispatch) and q.active.forall(t => Pred(t).subseteq(q.done))
  val CapacityBound = q.active.size() <= Capacity
  val CompleteReturn = q.returned implies (q.active == Set() and (q.stopped or q.done == Tasks))
  val DependencySnapshot = q.active.union(q.done).forall(t => Facts(Pred(t)).subseteq(q.snapshot.get(t)))
  val CompletedDelivery = not(q.stopped) implies Facts(q.done).subseteq(q.merged)

}
