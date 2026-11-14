// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ScopedReachabilityMask {
  const Mutation: str
  type State = {id:int, phase:str, reach:Set[int], witnesses:Set[int], branches:Set[int], groups:Set[int]}
  var q: State
  pure def place(n:int):int = range(0,n).foldl(1,(v,_) => v*2)
  pure def bit(id:int,n:int):bool = (id / place(n)) % 2 == 1
  pure def edge(id:int,x:int,y:int):bool = y == (x+1)%3 and bit(id,x)
  pure def expectedReach(id:int,x:int,y:int):bool = x == y or edge(id,x,y) or
    0.to(2).exists(z => edge(id,x,z) and edge(id,z,y))
  pure def banned(id:int,scope:int,z:int):bool = bit(id,3+scope*3+z)
  pure def expectedWitnesses(id:int):Set[int] = 0.to(17).filter(slot =>
    banned(id,slot/9,(slot%9)/3) and expectedReach(id,0,(slot%9)/3) and expectedReach(id,(slot%9)/3,slot%3))
  pure def expectedBranches(id:int):Set[int] = 0.to(5).filter(slot =>
    expectedReach(id,0,slot%3) and not(expectedWitnesses(id).exists(w => w/9 == slot/3 and w%3 == slot%3)))
  pure def closure(id:int,scope:int,clean:bool):Set[int] = {
    val seed = 0.to(2).filter(x => not(clean) or not(banned(id,scope,x))).map(x => x*3+x)
    range(0,3).foldl(seed,(r,_) => r.union(0.to(8).filter(pair =>
      (not(clean) or not(banned(id,scope,pair%3))) and
      0.to(2).exists(x => r.contains((pair/3)*3+x) and edge(id,x,pair%3)))))
  }
  pure def evaluate(id:int,mutation:str):State = {
    val reach = closure(id,0,false)
    val witnesses = 0.to(17).filter(slot => {
      val scope = slot/9
      val z = (slot%9)/3
      val t = slot%3
      val blocked = if (mutation == "global") banned(id,0,z) or banned(id,1,z) else banned(id,scope,z)
      blocked and reach.contains(z) and reach.contains(z*3+t) and (mutation != "late" or z == t)
    })
    val branches = 0.to(5).filter(slot => if (mutation == "cleanAlternative")
      closure(id,slot/3,true).contains(slot%3) else
      reach.contains(slot%3) and not(witnesses.exists(w => w/9 == slot/3 and w%3 == slot%3)))
    {id:id,phase:"complete",reach:reach,witnesses:if (mutation == "forgetWitness") Set() else witnesses,
      branches:branches,groups:0.to(2).filter(t => branches.contains(t) and branches.contains(3+t))}
  }
  action init = {nondet id = 0.to(511).oneOf(); q' = {id:id,phase:"pending",reach:Set(),witnesses:Set(),branches:Set(),groups:Set()}}
  action step = all {q.phase == "pending",q' = evaluate(q.id,Mutation)}
  val ExactReach = q.phase == "complete" implies q.reach == 0.to(8).filter(p => expectedReach(q.id,p/3,p%3))
  val ExactWitnesses = q.phase == "complete" implies q.witnesses == expectedWitnesses(q.id)
  val ExactBranches = q.phase == "complete" implies q.branches == expectedBranches(q.id)
  val ExactGroups = q.phase == "complete" implies q.groups == 0.to(2).filter(t => expectedBranches(q.id).contains(t) and expectedBranches(q.id).contains(3+t))
  val Private = q.phase != "complete" implies q.reach == Set() and q.witnesses == Set() and q.branches == Set() and q.groups == Set()
  pure def mask(rows:Set[int]):int = rows.fold(0,(m,slot) => m+place(slot))
  pure def conformanceCase(id:int):List[int] = {
    val result = evaluate(id,"none")
    List(id,mask(result.reach),mask(result.witnesses),mask(result.branches),mask(result.groups))
  }
  pure val conformance = range(0,512).foldl(List(),(rows,id) => rows.append(conformanceCase(id)))
}
