// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ProviderReplay {
  const Nodes: Set[int]
  const Scopes: Set[int]
  const Mutation: str
  type Row = (int,int,int)
  type Event = {row:Row,kind:str}
  pure val Rows = tuples(Scopes,Nodes,Nodes)
  pure val Edges = Rows.filter(e => e._2 != e._3)
  pure def Reverse(xs: List[a]): List[a] = xs.foldl(List(),(acc,x) => List(x).concat(acc))
  pure def Range(xs: List[a]): Set[a] = xs.indices().map(i => xs.nth(i))
  pure def Reach(rows:Set[Row],g:int,x:int,y:int):bool = x == y or rows.contains((g,x,y))
  pure def Step(rows:Set[Row],e:Row):Set[Row] = rows.union(Set((e._1,e._2,e._2),(e._1,e._3,e._3)))
    .union(Rows.filter(p => p._1 == e._1 and Reach(rows,e._1,p._2,e._2) and Reach(rows,e._1,e._3,p._3)))
  pure def Code(p:Row):int = 4*p._1+2*p._2+p._3
  pure def Enumerate(rows:Set[Row]):List[Row] = rows.fold(List(),(xs,p) =>
    xs.foldl(List(),(acc,x) => if (Code(x) < Code(p)) acc.append(x) else acc).concat(List(p)).concat(xs.foldl(List(),(acc,x) => if (Code(x) >= Code(p)) acc.append(x) else acc)))
  pure def Close(rows:Set[Row]):Set[Row] = Nodes.fold(rows,(rs,n) => rs.union(Rows.filter(p => rs.contains((p._1,p._2,n)) and rs.contains((p._1,n,p._3)))))
  pure def Expected(edges:Set[Row]):Set[Row] = Close(edges.union(Rows.filter(p => p._2 == p._3 and edges.exists(e => e._1 == p._1 and Set(e._2,e._3).contains(p._2)))))
  type ReplayResult = {rows:Set[Row],output:List[Row]}
  pure def Replay(events:List[Event]):ReplayResult = Reverse(events).foldl({rows:Set(),output:List()},(prior,e) => {
    val rows = Step(prior.rows,e.row)
    val fresh = Enumerate(rows.exclude(prior.rows))
    {rows:rows,output:prior.output.concat(if (e.kind == "derived") Reverse(fresh) else fresh)}
  })
  type Snapshot = {inputs:Set[Row],total:Set[Row],journal:List[Event],ordered:List[Row]}
  type State = {inputs:Set[Row],total:Set[Row],journal:List[Event],ordered:List[Row],phase:str,pending:Set[Row],event:Event,
    held:bool,heldJournal:List[Event],heldTotal:Set[Row],heldOrder:List[Row],refused:bool,saved:Snapshot}
  var q:State
  def snapshot:Snapshot = {inputs:q.inputs,total:q.total,journal:q.journal,ordered:q.ordered}
  pure val Initial: Snapshot = {inputs:Set(),total:Set(),journal:List(),ordered:List()}
  action init = q' = {inputs:Initial.inputs,total:Initial.total,journal:Initial.journal,ordered:Initial.ordered,phase:"idle",pending:Set(),event:{row:(0,0,1),kind:"source"},held:false,heldJournal:List(),heldTotal:Set(),heldOrder:List(),refused:false,saved:Initial}
  action Stage(e:Row,kind:str):bool = all {q.phase == "idle",not(q.inputs.contains(e)),q' = {...q,event:{row:e,kind:kind},
    pending:Step(q.total,if (Mutation == "scope") (0,e._2,e._3) else e),phase:"pending",
    journal:if (Mutation == "early") List({row:e,kind:kind}).concat(q.journal) else q.journal,refused:false}}
  action Commit = all {q.phase == "pending",q' = {...q,inputs:q.inputs.union(Set(q.event.row)),total:q.pending,
    ordered:q.ordered.concat(if (q.event.kind == "derived") Reverse(Enumerate(q.pending.exclude(q.total))) else Enumerate(q.pending.exclude(q.total))),
    journal:if (Mutation == "drop") q.journal else List({row:q.event.row,kind:if (Mutation == "kind") "source" else q.event.kind}).concat(q.journal),phase:"idle"}}
  action Capture = all {q.phase == "idle",not(q.held),q' = {...q,held:true,heldJournal:q.journal,heldTotal:q.total,heldOrder:q.ordered}}
  action Reject(e:Row):bool = all {q.phase == "idle",not(q.inputs.contains(e)),Step(q.total,e) != q.total,
    q' = {...q,refused:true,saved:snapshot,journal:if (Mutation == "reject") List({row:e,kind:"source"}).concat(q.journal) else q.journal}}
  action eventStep = {nondet e = Edges.oneOf(); nondet kind = Set("source","derived").oneOf(); any {Reject(e),Stage(e,kind)}}
  action step = any {Commit,Capture,eventStep}
  val PublishedExact = q.total == Expected(q.inputs)
  val JournalExact = Replay(q.journal).rows == q.total
  val OrderExact = Replay(q.journal).output == q.ordered and Range(q.ordered) == q.total and q.ordered.length() == q.total.size()
  val HeldExact = q.held implies {
    val cut = if (Mutation == "cut") q.journal else q.heldJournal
    Replay(cut).rows == q.heldTotal and Replay(cut).output == q.heldOrder
  }
  val RefusalAtomic = q.refused implies snapshot == q.saved

}
