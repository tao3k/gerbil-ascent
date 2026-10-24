// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ProviderFrontier {
  const Nodes: Set[int]
  const InitialInputs: Set[(int,int)]
  const Mutation: str
  pure val Pairs = tuples(Nodes,Nodes)
  pure def Join3(left: Set[(int,int)], middle: Set[(int,int)], right: Set[(int,int)]): Set[(int,int)] =
    Pairs.filter(p => Nodes.exists(b => Nodes.exists(c => left.contains((p._1,b)) and middle.contains((b,c)) and right.contains((c,p._2)))))
  pure def BodyOf(rows: Set[(int,int)]): Set[(int,int)] = Join3(rows,rows,rows)
  pure def Pivots(fresh: Set[(int,int)], rows: Set[(int,int)]): Set[(int,int)] = Join3(fresh,rows,rows).union(Join3(rows,fresh,rows)).union(Join3(rows,rows,fresh))
  // Floyd-Warshall folds all admitted intermediate nodes, without a runtime cap.
  pure def Close(edges: Set[(int,int)]): Set[(int,int)] = Nodes.fold(edges,(rows,b) =>
    rows.union(Pairs.filter(p => rows.contains((p._1,b)) and rows.contains((b,p._2)))))
  pure def Concrete(edges: Set[(int,int)]): Set[(int,int)] = {
    val members = Nodes.filter(n => edges.exists(p => n == p._1 or n == p._2))
    Close(edges.union(edges.map(p => (p._2,p._1))).union(members.map(n => (n,n))))
  }
  pure val SeededInputs = Set((Nodes.chooseSome(),Nodes.chooseSome()))
  type State = {inputs: Set[(int,int)], total: Set[(int,int)], delta: Set[(int,int)], pending: Set[(int,int)], delivered: Set[(int,int)], answers: Set[(int,int)], phase: str}
  var q: State
  action init = q' = {inputs: InitialInputs, total: Concrete(InitialInputs), delta: Set(), pending: Concrete(InitialInputs), delivered: Concrete(InitialInputs),
    answers: if (Mutation == "initial") Set() else BodyOf(Concrete(InitialInputs)), phase: "idle"}
  action Inject(edge: (int,int)): bool = {
    val pending = Concrete(q.inputs.union(Set(edge)))
    all {q.phase == "idle", not(q.inputs.contains(edge)), q' = {...q, inputs: q.inputs.union(Set(edge)), pending: pending,
      delta: if (Mutation == "raw") Set(edge).exclude(q.total) else if (Mutation == "foreign") pending.exclude(q.total).union(Pairs.exclude(pending))
        else if (Mutation == "overlap") pending else pending.exclude(q.total), phase: "pending",
      answers: if (Mutation == "early") BodyOf(pending) else q.answers}}
  }
  action Consume = all {q.phase == "pending", q' = {...q,
    delivered: if (Mutation == "omit") q.delivered else q.delivered.union(q.delta), total: q.pending, delta: Set(), phase: "idle",
    answers: (if (Mutation == "replace") Set() else q.answers).union(Pivots(q.delta,if (Mutation == "old") q.total else q.pending))}}
  action injectStep = {nondet edge = Pairs.oneOf(); Inject(edge)}
  action step = any {injectStep, Consume}
  val FrontierComplete = q.phase == "pending" implies (q.pending == q.total.union(q.delta) and q.delta.subseteq(q.pending))
  val ExactFrontier = (q.phase == "pending" and Mutation == "none") implies q.delta == q.pending.exclude(q.total)
  val DeliveredExact = q.phase == "idle" implies (q.delivered == q.total and q.total == Concrete(q.inputs))
  val ConsumerSnapshot = q.answers == BodyOf(q.total)

}

module ProviderFrontierFixture {
  const Fault: str
  const Seeded: bool
  import ProviderFrontier(Nodes = Set(1,2,3), InitialInputs = if (Seeded) Set((1,1)) else Set(), Mutation = Fault).*
}
