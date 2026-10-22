// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module OwnedLookup {
  const Mutation: str
  type Row = List[int]
  // BEGIN GENERATED OWNED ROW COST
  pure def TupleTemporaryCalls(rows: List[Row]): int = rows.foldl(0, (n,row) => n + (if (row.length() == 0) 0 else 1))
  pure def TupleTemporaryBytes(rows: List[Row], valueBytes: int): int = rows.foldl(0, (n,row) => n + row.length() * valueBytes)
  pure def TupleDirectCalls(rows: List[Row]): int = rows.length()
  pure def TupleStagedCalls(rows: List[Row]): int = TupleDirectCalls(rows) + TupleTemporaryCalls(rows)
  // END GENERATED OWNED ROW COST
  pure def Queries(i: int): (List[int],List[int]) =
    if (i == 0) (List(),List()) else if (i == 1) (List(0),List(0))
    else if (i == 2) (List(1),List(0)) else if (i == 3) (List(0,0),List(0,1))
    else if (i == 4) (List(1,0),List(1,0)) else (List(0),List(99))
  pure def Match(row: Row, query: (List[int],List[int])): bool =
    if (query._1.length() == 0) true else 0.to(query._1.length()-1).fold(true, (ok,i) => ok and row.nth(query._1.nth(i)) == query._2.nth(i))
  pure def Selected(rows: List[Row], i: int): List[Row] =
    rows.foldl(List(), (acc,row) => if (Match(row,Queries(i))) acc.append(row) else acc)
  pure def Collect(rows: List[Row]): List[Row] = rows.foldl(List(), (acc,row) => acc.append(row))
  pure def Reverse(rows: List[Row]): List[Row] = rows.foldl(List(), (acc,row) => List(row).concat(acc))
  type State = {held: List[Row], source: List[Row], results: int -> List[Row], ready: Set[int],
    mutated: Set[int], retired: bool, rejected: bool}
  var q: State
  action init = q' = {held: List(List(0,0),List(0,1),List(1,0)),
    source: List(List(0,0),List(0,1),List(1,0)), results: Map(0 -> List(), 1 -> List(), 2 -> List(), 3 -> List(), 4 -> List(), 5 -> List()), ready: Set(), mutated: Set(), retired: false, rejected: false}
  action Read = {
    nondet i = 0.to(5).oneOf()
    val rows = Collect(Selected(q.source,i))
    val public = if (Mutation == "order" or (Mutation == "export" and i == 0)) Reverse(rows) else if (Mutation == "empty" and i == 0) List()
      else if (Mutation == "duplicate") rows.concat(rows) else rows
    all {not(q.ready.contains(i)), q' = {...q, ready: q.ready.union(Set(i)), results: q.results.set(i,public)}}
  }
  action Mutate = {
    nondet i = 0.to(5).oneOf()
    all {q.ready.contains(i), not(q.mutated.contains(i)), q' = {...q,
      mutated: q.mutated.union(Set(i)), results: if (Mutation == "shared") q.ready.fold(q.results, (m,k) => m.set(k,List(List(99,99))))
        else q.results.set(i,List(List(99,99))), source: if (Mutation == "borrow") List(List(99,99)) else q.source}}
  }
  action Retire = all {not(q.retired), q' = {...q, retired: true,
    source: if (Mutation == "retire") List() else q.source}}
  pure def Valid(query: (List[int],List[int])): bool =
    query._1.length() == query._2.length() and query._1.foldl(true, (ok,c) => ok and c >= 0)
  action Reject = all {not(Valid((List(0,1),List(0)))), not(q.rejected), q' = {...q, rejected: true,
    source: if (Mutation == "reject") List() else q.source}}
  action step = any {Read, Mutate, Retire, Reject}
  val NoTupleTemporary = (if (Mutation == "tuple-temp") TupleStagedCalls(q.held) else TupleDirectCalls(q.held)) == q.held.length()
  val FrozenExact = q.source == q.held
  val OrderedExact = q.ready.exclude(q.mutated).forall(i => q.results.get(i) == Selected(q.held,i))
  val RejectedStable = q.rejected implies q.source == q.held
}
