// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ProviderRouting {
  const Mutation: str
  type Row = {id: int, a: int, b: int}
  pure val Readers = Set("rows","parts")
  pure val Queries = Set("single","reorder","repeat","conflict","absent")
  pure val Input = List({id:10,a:7,b:1},{id:11,a:7,b:2},{id:12,a:9,b:1},{id:13,a:7,b:1})
  pure def Constraints(query: str): List[(int,int)] = if (query == "single") List((0,7))
    else if (query == "reorder") List((1,1),(0,7)) else if (query == "repeat") List((0,7),(0,7))
    else if (query == "conflict") List((0,7),(0,9)) else List((0,6))
  pure def Coordinate(row: Row, column: int): int = if (column == 0) row.a else row.b
  pure def Matches(row: Row, constraints: List[(int,int)]): bool = constraints.indices().forall(i => Coordinate(row,constraints.nth(i)._1) == constraints.nth(i)._2)
  pure def Filter(rows: List[Row], constraints: List[(int,int)]): List[Row] = rows.foldl(List(),(acc,row) => if (Matches(row,constraints)) acc.append(row) else acc)
  pure def Reverse(rows: List[Row]): List[Row] = rows.foldl(List(),(acc,row) => List(row).concat(acc))
  type State = {phase: str -> str, query: str -> str, work: str -> List[Row], emitted: str -> List[Row]}
  var q: State
  action init = q' = {phase: Readers.mapBy(_ => "new"), query: Readers.mapBy(_ => "single"), work: Readers.mapBy(_ => List()), emitted: Readers.mapBy(_ => List())}
  action Build(r: str, query: str, k: int): bool = {
    val candidates = Filter(Input,List(Constraints(query).nth(k)))
    all {q.phase.get(r) == "new", k >= 0, k < Constraints(query).length(),
      q' = {...q, work: q.work.set(r, if (Mutation == "drop" and candidates.length() > 0) candidates.tail() else if (Mutation == "order") Reverse(candidates) else candidates),
        phase: q.phase.set(r,"walk"), query: q.query.set(r,query)}}
  }
  action Read(r: str): bool = {
    val row = q.work.get(r).head()
    val constraints = if (Mutation == "prefix") List(Constraints(q.query.get(r)).head()) else Constraints(q.query.get(r))
    val returned = if (Mutation == "representative") {...row,id:99} else row
    all {q.phase.get(r) == "walk", q.work.get(r).length() > 0, q' = {...q,
      emitted: q.emitted.set(r, if (Matches(row,constraints)) q.emitted.get(r).append(returned) else q.emitted.get(r)), work: q.work.set(r,q.work.get(r).tail())}}
  }
  action Finish(r: str): bool = all {q.phase.get(r) == "walk", q.work.get(r) == List(), q' = {...q, phase: q.phase.set(r,"complete")}}
  action Cancel(r: str): bool = all {q.phase.get(r) == "walk", q' = {...q, phase: q.phase.set(r,"canceled")}}
  action buildStep = {nondet r = Readers.oneOf(); nondet query = Queries.oneOf(); nondet k = Set(0,1).oneOf(); Build(r,query,k)}
  action readerStep = {nondet r = Readers.oneOf(); any {Read(r), Finish(r), Cancel(r)}}
  action step = any {buildStep, readerStep}
  val CompleteExact = Readers.forall(r => q.phase.get(r) == "complete" implies q.emitted.get(r) == Filter(Input,Constraints(q.query.get(r))))

}
