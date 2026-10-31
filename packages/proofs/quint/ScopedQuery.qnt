// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ScopedQuery {
  const Mutation: str
  type State = {id:int, phase:str, hops:Set[int], reach:Set[int], shortest:Set[int], predecessors:Set[int], witnesses:Set[int], branches:Set[int], groups:Set[int], traces:Set[int]}
  var q: State
  pure def place(n:int):int = range(0,n).foldl(1,(v,_) => v*2)
  pure def bit(id:int,n:int):bool = (id / place(n)) % 2 == 1
  pure def edge(id:int,x:int,y:int):bool = y == (x+1)%3 and bit(id%512,x)
  pure def banned(id:int,scope:int,z:int):bool = bit(id%512,3+scope*3+z)
  pure def limit(id:int):int = id/512
  // Independent matrix powers; no calls to the transition's layer fold.
  pure def exact(id:int,s:int,t:int,k:int):bool = if (k == 0) s == t else
    if (k == 1) edge(id,s,t) else 0.to(2).exists(x => edge(id,s,x) and edge(id,x,t))
  pure def expectedHops(id:int):Set[int] = 0.to(26).filter(slot => slot%3 <= limit(id) and exact(id,slot/9,(slot%9)/3,slot%3))
  pure def first(id:int,s:int,t:int,k:int):bool = k <= limit(id) and exact(id,s,t,k) and range(0,k).foldl(true,(ok,n) => ok and not(exact(id,s,t,n)))
  pure def reachable(id:int,s:int,t:int):bool = 0.to(limit(id)).exists(k => exact(id,s,t,k))
  pure def witness(id:int,scope:int,z:int,t:int):bool = banned(id,scope,z) and 0.to(limit(id)).exists(p => 0.to(limit(id)).exists(q =>
    p+q <= limit(id) and exact(id,0,z,p) and exact(id,z,t,q)))
  pure def branch(id:int,scope:int,t:int):bool = reachable(id,0,t) and 0.to(2).forall(z => not(witness(id,scope,z,t)))
  pure def answer(id:int,t:int):bool = branch(id,0,t) and branch(id,1,t)
  pure def evaluate(id:int,mutation:str):State = {
    val cap = if (mutation == "unbounded") 2 else limit(id)
    val seed = 0.to(2).map(s => s*9+s*3)
    val layers = range(1,cap+1).foldl(seed,(h,k) => h.union(0.to(8).filter(p =>
      0.to(2).exists(x => h.contains((p/3)*9+x*3+k-1) and edge(id,x,p%3))).map(p => p*3+k)))
    val reach = layers.map(slot => slot/3)
    val shortest = layers.filter(slot => range(0,slot%3).foldl(true,(ok,k) => ok and not(layers.contains((slot/3)*3+k))))
    val predecessors = 0.to(26).filter(p => 1.to(cap).exists(k =>
      shortest.contains((p/9)*9+(p%3)*3+k) and layers.contains((p/9)*9+((p%9)/3)*3+k-1) and edge(id,(p%9)/3,p%3)))
    val witnesses = 0.to(17).filter(w => {
      val z = (w%9)/3
      val blocked = if (mutation == "global") banned(id,0,z) or banned(id,1,z) else banned(id,w/9,z)
      blocked and (if (mutation == "independentSides") reach.contains(z) and reach.contains(z*3+w%3) else
        0.to(cap).exists(p => 0.to(cap).exists(q => p+q <= cap and shortest.contains(z*3+p) and shortest.contains(z*9+(w%3)*3+q))))
    })
    val branches = 0.to(5).filter(b => reach.contains(b%3) and not(witnesses.exists(w => w/9 == b/3 and w%3 == b%3)))
    val groups = 0.to(2).filter(t => branches.contains(t) and branches.contains(3+t))
    val traces = 0.to(17).filter(slot => groups.contains((slot%9)/3) and branches.contains((slot/9)*3+(slot%9)/3) and shortest.contains(((slot%9)/3)*3+slot%3))
    {id:id,phase:"complete",hops:layers,reach:reach,shortest:shortest,
      predecessors:if (mutation == "forgetPredecessor") Set() else predecessors,witnesses:witnesses,
      branches:branches,groups:groups,traces:if (mutation == "forgetTrace") Set() else traces}
  }
  action init = {nondet id = 0.to(1535).oneOf(); q' = {id:id,phase:"pending",hops:Set(),reach:Set(),shortest:Set(),predecessors:Set(),witnesses:Set(),branches:Set(),groups:Set(),traces:Set()}}
  action step = all {q.phase == "pending",q' = evaluate(q.id,Mutation)}
  val ExactHops = q.phase == "complete" implies q.hops == expectedHops(q.id)
  val ExactReach = q.phase == "complete" implies q.reach == 0.to(8).filter(p => reachable(q.id,p/3,p%3))
  val ExactShortest = q.phase == "complete" implies q.shortest == 0.to(26).filter(p => first(q.id,p/9,(p%9)/3,p%3))
  val ExactPredecessors = q.phase == "complete" implies q.predecessors == 0.to(26).filter(p => 1.to(limit(q.id)).exists(k => first(q.id,p/9,p%3,k) and exact(q.id,p/9,(p%9)/3,k-1) and edge(q.id,(p%9)/3,p%3)))
  val ExactWitnesses = q.phase == "complete" implies q.witnesses == 0.to(17).filter(w => witness(q.id,w/9,(w%9)/3,w%3))
  val ExactBranches = q.phase == "complete" implies q.branches == 0.to(5).filter(b => branch(q.id,b/3,b%3))
  val ExactGroups = q.phase == "complete" implies q.groups == 0.to(2).filter(t => answer(q.id,t))
  val ExactTraces = q.phase == "complete" implies q.traces == 0.to(17).filter(p => answer(q.id,(p%9)/3) and branch(q.id,p/9,(p%9)/3) and first(q.id,0,(p%9)/3,p%3))
  val Private = q.phase != "complete" implies q.hops == Set() and q.reach == Set() and q.shortest == Set() and q.predecessors == Set() and q.witnesses == Set() and q.branches == Set() and q.groups == Set() and q.traces == Set()
  pure def mask(rows:Set[int]):int = rows.fold(0,(m,slot) => m+place(slot))
  pure val conformance = range(0,1536).foldl(List(),(rows,id) => {
    val r = evaluate(id,"none")
    rows.append(List(id,limit(id),mask(r.reach),mask(r.hops),mask(r.shortest),mask(r.predecessors),mask(r.witnesses),mask(r.branches),mask(r.groups),mask(r.traces)))
  })
}
