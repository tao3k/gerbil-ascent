// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Finite order/ownership model, not a source proof of Rust's sorting algorithm.
module RankedPublication {
  const Mutation: str
  val Codes = Set(0,1,2,3,4)
  val Scalars = List(8,-3,20,0,9)
  val Ranks = List(2,0,4,1,3)
  val Rows = Set(List()).union(Codes.map(c => List(c))).union(
    Codes.fold(Set(), (rows,a) => rows.union(Codes.map(b => List(a,b)))))
  pure def Less(a: List[int], b: List[int]): bool =
    if (a.length() == 0) b.length() > 0
    else if (b.length() == 0) false
    else if (a.nth(0) != b.nth(0)) a.nth(0) < b.nth(0)
    else if (Mutation == "drop-prefix") false
    else if (a.length() == 1) b.length() > 1
    else if (b.length() == 1) false else a.nth(1) < b.nth(1)
  pure def Oracle(a: List[int], b: List[int]): bool =
    if (a.length() == 0) b.length() > 0
    else if (b.length() == 0) false
    else if (a.nth(0) != b.nth(0)) a.nth(0) < b.nth(0)
    else if (a.length() == 1) b.length() > 1
    else if (b.length() == 1) false else a.nth(1) < b.nth(1)
  pure def Rank(row: List[int]): List[int] = row.foldl(List(), (xs,c) => xs.append(
    if (Mutation == "raw-code-order") c else if (Mutation == "reverse-rank") 4-Ranks.nth(c) else Ranks.nth(c)))
  pure def Decode(row: List[int]): List[int] = row.foldl(List(), (xs,c) => xs.append(Scalars.nth(c)))
  type State = {phase: int, source: List[int], decoded: List[int],
    sorted: bool, canceled: bool, failed: bool, published: bool}
  var q: State
  action init = {
    nondet row = Rows.oneOf()
    nondet canceled = Set(false,true).oneOf()
    nondet failed = Set(false,true).oneOf()
    q' = {phase: 0, source: row, decoded: List(), sorted: false,
      canceled: canceled, failed: failed, published: false}
  }
  action step = all {q.phase == 0,
    q' = {...q, phase: 1, decoded: if (Mutation == "wrong-decode") List(999) else Decode(q.source),
      sorted: Mutation != "missing-order",
      published: (not(q.canceled) or Mutation == "ignore-cancel") and
        (not(q.failed) or Mutation == "ignore-failure")}}
  val OrderEmbedding = q.phase == 0 or Rows.forall(a => Rows.forall(b => Less(Rank(a),Rank(b)) == Oracle(Decode(a),Decode(b))))
  val DecodeExact = q.phase == 0 or q.decoded == Decode(q.source)
  val OrderedPublication = q.phase == 0 or not(q.published) or q.sorted
  val NoCanceledPublication = not(q.published and q.canceled)
  val NoFailedPublication = not(q.published and q.failed)
}
