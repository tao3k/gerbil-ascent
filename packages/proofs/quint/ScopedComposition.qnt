// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ScopedComposition {
  const Mutation: str
  type State = {id:int, phase:str, witnesses:Set[int], covered:Set[int], missing:Set[int], answer:bool}
  var q: State
  pure def bit(id:int, place:int):bool = (id / place) % 2 == 1
  pure def place(slot:int):int = if (slot == 0) 1 else if (slot == 1) 2 else if (slot == 2) 4 else 8
  pure def required(id:int):Set[int] = Set(0,1).filter(g => bit(id,64*place(g)))
  pure def member(id:int, slot:int):bool = bit(id,4*place(slot))
  pure def supported(id:int, slot:int):bool = member(id,slot) and bit(id,place(slot%2))
  pure def expectedWitnesses(id:int):Set[int] = 0.to(3).filter(slot =>
    bit(id,256) and required(id).contains(slot/2) and supported(id,slot))
  pure def expectedCovered(id:int):Set[int] = required(id).filter(g =>
    expectedWitnesses(id).exists(slot => slot/2 == g))
  pure def expectedMissing(id:int):Set[int] = if (bit(id,256)) required(id).exclude(expectedCovered(id)) else Set()
  pure def evaluate(id:int, mutation:str):State = {
    val witnesses = expectedWitnesses(id)
    val covered = if (mutation == "allBranches") required(id).filter(g =>
      bit(id,256) and member(id,g*2) and member(id,g*2+1) and bit(id,1) and bit(id,2))
      else expectedCovered(id)
    val missing = if (bit(id,256)) required(id).exclude(covered).filter(g =>
      mutation != "emptyGroup" or member(id,g*2) or member(id,g*2+1)) else Set()
    val answer = bit(id,256) and (if (mutation == "union") covered != Set() else missing == Set())
    {id:id,phase:"complete", witnesses:if (mutation == "forgetWitness") Set() else witnesses,
      covered:covered,missing:missing,answer:answer}
  }
  action init = {nondet id = 0.to(511).oneOf();
    q' = {id:id,phase:"pending",witnesses:Set(),covered:Set(),missing:Set(),answer:false}}
  action step = all {q.phase == "pending",q' = evaluate(q.id,Mutation)}
  val ExactWitnesses = q.phase == "complete" implies q.witnesses == expectedWitnesses(q.id)
  val ExactCoverage = q.phase == "complete" implies q.covered == expectedCovered(q.id)
  val ExactMissing = q.phase == "complete" implies q.missing == expectedMissing(q.id)
  val ExactAnswer = q.phase == "complete" implies q.answer == (bit(q.id,256) and expectedMissing(q.id) == Set())
  val Private = q.phase != "complete" implies q.witnesses == Set() and q.covered == Set() and q.missing == Set() and not(q.answer)
  pure def conformanceCase(id:int):List[int] = {
    val result = evaluate(id,"none")
    List(id,result.witnesses.fold(0,(mask,slot) => mask+place(slot)),
      result.covered.fold(0,(mask,g) => mask+place(g)), result.missing.fold(0,(mask,g) => mask+place(g)),
      if (result.answer) 1 else 0)
  }
  pure val conformance = range(0,512).foldl(List(),(cases,id) => cases.append(conformanceCase(id)))
}
