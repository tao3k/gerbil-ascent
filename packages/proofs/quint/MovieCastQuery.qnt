// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module MovieCastQuery {
  const Mutation: str
  type State = {id:int,phase:str,evidence:Set[int],answers:Set[int],traces:Set[int]}
  var q: State
  pure def place(n:int):int = range(0,n).foldl(1,(v,_) => v*2)
  pure def bit(id:int,n:int):bool = id/place(n)%2 == 1
  pure def support(id:int,scope:int,a:int):bool = bit(id%512,scope*3+a) and
    (not(bit(id%512,6+a)) or (scope == 1 and id/512 != 1))
  pure def expected(id:int,a:int):bool = if (id/512 == 2) support(id,0,a) and support(id,1,a) else support(id,0,a) or support(id,1,a)
  pure def evaluate(id:int,mutation:str):State = {
    val source = 0.to(5).filter(p => bit(id%512,p))
    val banned = 0.to(2).filter(a => bit(id%512,6+a))
    val evidence = source.filter(p => not(banned.contains(p%3)) or
      (p/3 == 1 and id/512 != 1 and mutation != "global") or mutation == "early")
    val left = evidence.filter(p => p/3 == 0).map(p => p%3)
    val right = evidence.filter(p => p/3 == 1).map(p => p%3)
    val answers = if (id/512 == 2 and mutation != "union") left.intersect(right) else left.union(right)
    val traces = evidence.filter(p => answers.contains(p%3))
    {id:id,phase:"complete",evidence:evidence,answers:answers,traces:if (mutation == "forget") Set() else traces}
  }
  action init = {nondet id = 0.to(1535).oneOf(); q' = {id:id,phase:"pending",evidence:Set(),answers:Set(),traces:Set()}}
  action step = all {q.phase == "pending",q' = evaluate(q.id,Mutation)}
  val ExactEvidence = q.phase == "complete" implies q.evidence == 0.to(5).filter(p => support(q.id,p/3,p%3))
  val ExactAnswer = q.phase == "complete" implies q.answers == 0.to(2).filter(a => expected(q.id,a))
  val ExactTrace = q.phase == "complete" implies q.traces == 0.to(5).filter(p => expected(q.id,p%3) and support(q.id,p/3,p%3))
  val Private = q.phase != "complete" implies q.evidence == Set() and q.answers == Set() and q.traces == Set()
  pure def mask(rows:Set[int]):int = rows.fold(0,(m,p) => m+place(p))
  pure val conformance = range(0,1536).foldl(List(),(rows,id) => {
    val r = evaluate(id,"none")
    rows.append(List(id,mask(r.evidence),mask(r.answers),mask(r.traces)))
  })
}
