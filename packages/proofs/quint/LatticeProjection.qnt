// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module LatticeProjection {
  const Mutation: str
  const Remaining: int
  pure val Keys = Set(0,1)
  pure val Values = Set(0,1,2)
  pure val Events = tuples(Keys,Values)
  pure val Seed = Keys.mapBy(_ => 2)
  pure def RowsOf(store: int -> int): Set[(int,int)] = Keys.map(k => (k,store.get(k)))
  pure def Expected(events: Set[(int,int)]): int -> int = Keys.mapBy(k => Values.filter(v => (v == 2 or events.contains((k,v)))
    and Values.forall(w => events.contains((k,w)) implies v <= w)).chooseSome())
  type State = {cut: Set[(int,int)], applied: Set[(int,int)], current: int -> int, dirty: Set[int], rows: Set[(int,int)], held: Set[(int,int)], phase: str, refusedCost: int}
  var q: State
  def NextDirty(e: (int,int)): Set[int] = if (e._2 < q.current.get(e._1)) q.dirty.union(Set(e._1)) else q.dirty
  def PendingCost(e: (int,int)): int = NextDirty(e).size()
  def AdmissionCost(e: (int,int)): int = if (Mutation == "budget-events") q.applied.size()+1 else PendingCost(e)
  pure def Apply(store: int -> int, e: (int,int)): int -> int = store.set(e._1, if (store.get(e._1) <= e._2) store.get(e._1) else e._2)
  action init = q' = {cut: Set(), applied: Set(), current: Seed, dirty: Set(), rows: RowsOf(Seed), held: RowsOf(Seed), phase: "initial", refusedCost: 0}
  action Begin = {nondet cut = Events.powerset().oneOf(); all {q.phase == "initial", q' = {...q, cut: cut, phase: "collecting"}}}
  action Inject(e: (int,int)): bool = all {q.phase == "collecting", q.cut.exclude(q.applied).contains(e), AdmissionCost(e) <= Remaining or Mutation == "budget-skip",
    q' = {...q, applied: q.applied.union(Set(e)), current: if (Mutation == "false" and e._1 == 0) q.current
      else q.current.set(e._1, if (Mutation == "overwrite") e._2
        else if (Mutation == "prior") {if (Seed.get(e._1) <= e._2) Seed.get(e._1) else e._2}
        else {if (q.current.get(e._1) <= e._2) q.current.get(e._1) else e._2}),
      dirty: if (e._2 >= q.current.get(e._1)) q.dirty else if (Mutation == "lost-key" and e._1 == 0) q.dirty
        else if (Mutation == "repeat-key" and q.dirty.contains(e._1)) q.dirty.exclude(Set(e._1)) else q.dirty.union(Set(e._1))}}
  action Refuse(e: (int,int)): bool = all {q.phase == "collecting", q.cut.exclude(q.applied).contains(e), AdmissionCost(e) > Remaining, Mutation != "budget-skip",
    q' = {...q, phase: "refused", refusedCost: PendingCost(e), applied: q.applied.union(Set(e)), current: Apply(q.current,e), dirty: NextDirty(e),
      rows: if (Mutation == "refusal-publish") RowsOf(Apply(q.current,e)) else q.rows}}
  action Settle = all {q.phase == "collecting", q.applied == q.cut or Mutation == "early", q' = {...q, phase: "settled"}}
  action Publish = all {q.phase == "settled", q' = {...q, phase: "finished",
    rows: if (Mutation == "retain") q.rows.union(RowsOf(q.current)) else if (Mutation == "stale") q.rows
      else q.rows.filter(row => not(q.dirty.contains(row._1))).union(q.dirty.map(k => (k,q.current.get(k)))),
    held: if (Mutation == "borrow") RowsOf(q.current) else q.held}}
  action eventStep = {nondet e = Events.oneOf(); any {Inject(e), Refuse(e)}}
  action step = any {Begin, eventStep, Settle, Publish}
  val MapExact = q.current == Expected(q.applied)
  val SnapshotExact = q.phase == "finished" implies q.rows == RowsOf(Expected(q.cut))
  val KeyCoverage = q.dirty == Keys.filter(k => q.current.get(k) != Seed.get(k))
  val BudgetBound = q.phase != "refused" implies q.dirty.size() <= Remaining
  val RefusalSound = q.phase == "refused" implies q.refusedCost > Remaining
  val RefusalStable = q.phase == "refused" implies q.rows == RowsOf(Seed)
  val PrivateStable = Set("initial","collecting","settled").contains(q.phase) implies q.rows == RowsOf(Seed)
  val HeldStable = q.held == RowsOf(Seed)

}
