// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module RectangleCompaction {
  const Mutation: str
  type Row = (int,int)
  pure def Reverse(xs: List[a]): List[a] = xs.foldl(List(), (acc,x) => List(x).concat(acc))
  pure def Product(left: List[int], right: List[int]): List[Row] =
    left.foldl(List(), (acc,a) => acc.concat(right.foldl(List(), (pairs,b) => pairs.append((a,b)))))
  pure def Original(left: List[int], targets: List[List[int]]): List[Row] =
    targets.foldl(List(), (acc,right) => acc.concat(Product(left,right)))
  pure def Compact(left: List[int], targets: List[List[int]]): List[Row] = {
    val rights = targets.foldl(List(), (acc,right) => acc.concat(right))
    if (left.length() == 1 or Mutation == "heavy")
      Product(left, if (Mutation == "order") Reverse(rights) else rights)
    else Original(left,targets)
  }
  pure def Select(rows: List[Row], key: int): List[Row] =
    rows.foldl(List(), (acc,row) => if (row._2 == key) acc.append(row) else acc)
  type State = {phase: str, left: List[int], targets: List[List[int]], cut: List[Row], held: List[Row],
    count: int, retired: bool, plans: int -> List[Row], ready: Set[int], keys: int -> int, reads: int -> List[Row]}
  var q: State
  action init = q' = {phase: "new", left: List(), targets: List(), cut: List(), held: List(), count: 0,
    retired: false, plans: Map(0 -> List(), 1 -> List()), ready: Set(), keys: Map(0 -> 0, 1 -> 1), reads: Map(0 -> List(), 1 -> List())}
  action Capture = {
    nondet left = Set(List(0),List(0,1)).oneOf()
    nondet targets = Set(List(List(0),List(1,2)), List(List(0,1),List(2)),
      List(List(0),List(),List(1,0))).oneOf()
    val cut = Compact(left,targets)
    all {q.phase == "new", q' = {...q, phase: "frozen", left: left, targets: targets,
      cut: cut, held: Original(left,targets), plans: Map(0 -> Select(cut,0), 1 -> Select(cut,1)),
      count: if (Mutation == "mass") targets.length() else cut.length()}}
  }
  action Retire = all {q.phase == "frozen", not(q.retired), q' = {...q, retired: true,
    targets: List(List(99)), cut: if (Mutation == "alias") Product(q.left,List(99)) else q.cut}}
  action Read = {
    nondet reader = Set(0,1).oneOf()
    val key = if (Mutation == "shared" and reader == 1) q.keys.get(0) else q.keys.get(reader)
    all {q.phase == "frozen", not(q.ready.contains(reader)), q' = {...q,
      ready: q.ready.union(Set(reader)), reads: q.reads.set(reader,q.plans.get(key))}}
  }
  action step = any {Capture, Retire, Read}
  val OrderedExact = q.phase == "frozen" implies q.cut == q.held
  val WeightedCount = q.phase == "frozen" implies q.count == q.held.length()
  val IndependentReaders = q.ready.forall(r => q.reads.get(r) == Select(q.held,q.keys.get(r)))
}
