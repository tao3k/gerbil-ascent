// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module TransitiveComponents {
  const Nodes: Set[int]
  const Mutation: str
  type Edges = Set[(int,int)]
  pure val Pairs = tuples(Nodes,Nodes)
  pure def Close(edges: Edges): Edges = Nodes.fold(edges,(rows,b) => rows.union(Pairs.filter(p => rows.contains((p._1,b)) and rows.contains((b,p._2)))))
  pure def Expected(edges: Edges): Edges = Close(edges.union(Nodes.map(n => (n,n))))
  pure def Concrete(par: int -> int, links: Edges): Edges = Pairs.filter(p => par.get(p._1) == par.get(p._2) or links.contains((par.get(p._1),par.get(p._2))))
  pure def Visible(par: int -> int, links: Edges, live: Set[int]): Edges = Concrete(par,links).intersect(tuples(live,live))
  pure def Walk(links: int -> int, n: int, k: int): int = range(0,k).foldl(n,(node,_) => links.get(node))
  type Snapshot = {inputs: Edges, parent: int -> int, arcs: Edges, active: Set[int], link: int -> int, members: int -> Set[int], size: int -> int}
  type State = {inputs: Edges, parent: int -> int, arcs: Edges, active: Set[int], link: int -> int, members: int -> Set[int], size: int -> int,
    refused: bool, saved: Snapshot, frontier: Edges, before: Edges}
  var q: State
  def snapshot: Snapshot = {inputs:q.inputs,parent:q.parent,arcs:q.arcs,active:q.active,link:q.link,members:q.members,size:q.size}
  def Reach(r: int, s: int): bool = r == s or q.arcs.contains((r,s))
  val Roots = Nodes.map(n => q.parent.get(n))
  type Proposal = {par: int -> int, links: Edges, pre: Edges, winner: int, mem: int -> Set[int], sz: int -> int, chain: int -> int, delta: Edges, raw: Edges, missing: Edges}
  def Plan(edge: (int,int)): Proposal = {
    val a = q.parent.get(edge._1)
    val b = q.parent.get(edge._2)
    val pred = Roots.filter(r => Reach(r,a))
    val succ = Roots.filter(r => Reach(b,r))
    val cycle = if (Reach(b,a)) pred.intersect(succ) else Set()
    val winner = if (cycle == Set()) 0 else cycle.filter(m => cycle.forall(n => q.size.get(m) >= q.size.get(n))).chooseSome()
    val par = Nodes.mapBy(n => if (cycle.contains(q.parent.get(n))) winner else q.parent.get(n))
    val links = q.arcs.union(tuples(pred,succ).filter(p => p._1 != p._2))
    val surviving = Nodes.map(n => par.get(n))
    val between = links.filter(p => surviving.contains(p._1) and not(cycle.contains(p._2) and
      (p._1 == winner or links.contains((p._1,winner))) and (p._2 != winner or p._1 == winner)))
    val merged = cycle.fold(Set(),(acc,r) => acc.union(q.members.get(r)))
    val mass = cycle.fold(0,(acc,r) => acc+q.size.get(r))
    val mem = Nodes.mapBy(r => if (r == winner) merged else if (cycle.contains(r)) Set() else q.members.get(r))
    val sz = Nodes.mapBy(r => if (r == winner) mass else if (cycle.contains(r)) 0 else q.size.get(r))
    val chain = Nodes.mapBy(r => if (cycle.exclude(Set(winner)).contains(r)) winner else q.link.get(r))
    val missing = Pairs.filter(p => pred.contains(q.parent.get(p._1)) and succ.contains(q.parent.get(p._2)) and not(Reach(q.parent.get(p._1),q.parent.get(p._2))))
    val newSelf = Set(edge._1,edge._2).exclude(q.active).map(n => (n,n))
    {par:par,links:between,pre:links,winner:winner,mem:mem,sz:sz,chain:chain,delta:missing.union(newSelf),raw:tuples(pred,succ),missing:missing}
  }
  pure val Initial: Snapshot = {inputs:Set(),parent:Nodes.mapBy(n => n),arcs:Set(),active:Set(),link:Nodes.mapBy(n => n),members:Nodes.mapBy(n => Set(n)),size:Nodes.mapBy(_ => 1)}
  action init = q' = {inputs:Initial.inputs,parent:Initial.parent,arcs:Initial.arcs,active:Initial.active,link:Initial.link,members:Initial.members,size:Initial.size,refused:false,saved:Initial,frontier:Set(),before:Set()}
  action Accept(edge: (int,int)): bool = {
    val plan = Plan(edge)
    all {not(q.inputs.contains(edge)), q' = {...q, inputs:q.inputs.union(Set(edge)), before:Visible(q.parent,q.arcs,q.active),active:q.active.union(Set(edge._1,edge._2)),
      frontier: if (Mutation == "raw") Set(edge) else if (Mutation == "diagonal") plan.missing
        else if (Mutation == "old") Pairs.filter(p => plan.raw.contains((q.parent.get(p._1),q.parent.get(p._2)))).union(plan.delta) else plan.delta,
      parent: if (Mutation == "split") q.parent else plan.par,
      arcs: if (Mutation == "stale") q.arcs.union(Set((q.parent.get(edge._1),q.parent.get(edge._2))))
        else if (Mutation == "adjacency") plan.pre.filter(p => Nodes.map(n => plan.par.get(n)).contains(p._1)) else plan.links,
      link: if (Mutation == "chain" and plan.winner != 0) plan.chain.set(plan.winner,Nodes.filter(r => r != plan.winner).chooseSome()) else plan.chain,
      members: if (Mutation == "members") q.members else plan.mem, size: if (Mutation == "size") q.size else plan.sz, refused:false}}
  }
  action Reject(edge: (int,int)): bool = all {not(q.inputs.contains(edge)), Plan(edge).delta.size() > 0,
    q' = {...q,saved:snapshot,refused:true,arcs:if (Mutation == "reject") Plan(edge).links else q.arcs}}
  action step = {nondet edge = Pairs.oneOf(); any {Accept(edge),Reject(edge)}}
  val ReachExact = Concrete(q.parent,q.arcs) == Expected(q.inputs)
  val SCCExact = Nodes.forall(a => Nodes.forall(b => (q.parent.get(a) == q.parent.get(b)) == (Expected(q.inputs).contains((a,b)) and Expected(q.inputs).contains((b,a)))))
  val ParentRoots = Nodes.forall(n => q.parent.get(q.parent.get(n)) == q.parent.get(n))
  val PrivateArcs = q.arcs.forall(p => p._1 != p._2 and Roots.contains(p._1) and Roots.contains(p._2))
  val RefusalAtomic = q.refused implies snapshot == q.saved
  val ActiveExact = q.active == Nodes.filter(n => q.inputs.exists(edge => n == edge._1 or n == edge._2))
  val DeltaExact = q.frontier == Expected(q.inputs).intersect(tuples(q.active,q.active)).exclude(q.before)
  val ParentChains = Nodes.forall(n => q.link.get(q.parent.get(n)) == q.parent.get(n) and Walk(q.link,n,Nodes.size()) == q.parent.get(n))
  val MemberPartition = Nodes.forall(r => q.members.get(r) == Nodes.filter(n => q.parent.get(n) == r))
  val SizeExact = Nodes.forall(r => q.size.get(r) == q.members.get(r).size())

}
