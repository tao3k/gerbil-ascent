// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module BranchScopedWitness {
  const Mutation: str
  type State = {id: int, phase: str, witnesses: Set[int], answers: Set[int], unionAnswer: bool}
  var q: State
  pure def bit(id: int, place: int): bool = (id / place) % 2 == 1
  pure def place(slot: int): int = if (slot == 0) 1 else if (slot == 1) 2 else if (slot == 2) 4 else 8
  pure def path(id: int, slot: int): bool =
    if (slot % 2 == 0) bit(id,1) and bit(id,2) else bit(id,4) and bit(id,8)
  pure def blocked(id: int, slot: int): bool = bit(id,16 * place(slot))
  pure def direct(id: int, scope: int): bool = bit(id,if (scope == 0) 256 else 512)
  pure def expectedWitnesses(id: int): Set[int] = 0.to(3).filter(slot => path(id,slot) and not(blocked(id,slot)))
  pure def expectedAnswers(id: int): Set[int] = Set(0,1).filter(scope =>
    direct(id,scope) or expectedWitnesses(id).exists(slot => slot / 2 == scope))
  pure def evaluate(id: int, mutation: str): State = {
    val witnesses = 0.to(3).filter(slot => path(id,slot) and
      (if (mutation == "crossMask") not(blocked(id,slot)) and not(blocked(id,(slot+2)%4))
       else if (mutation == "switchMask") not(blocked(id,(slot+2)%4))
       else not(blocked(id,slot))))
    val answers = Set(0,1).filter(scope => direct(id,scope) or witnesses.exists(slot => slot / 2 == scope))
    {id:id, phase:"complete",
      witnesses:if (mutation == "forgetScope") witnesses.map(slot => slot % 2) else witnesses,
      answers:if (mutation == "collapseBranch") (if (answers == Set()) Set() else Set(0)) else answers,
      unionAnswer:answers != Set()}
  }
  action init = {nondet id = 0.to(1023).oneOf();
    q' = {id:id,phase:"pending",witnesses:Set(),answers:Set(),unionAnswer:false}}
  action step = all {q.phase == "pending", q' = evaluate(q.id,Mutation)}
  val ExactWitnesses = q.phase == "complete" implies q.witnesses == expectedWitnesses(q.id)
  val ExactBranches = q.phase == "complete" implies q.answers == expectedAnswers(q.id)
  val ExactUnion = q.phase == "complete" implies q.unionAnswer == (expectedAnswers(q.id) != Set())
  val Private = q.phase != "complete" implies q.witnesses == Set() and q.answers == Set() and not(q.unionAnswer)
  pure def conformanceCase(id: int): List[int] = {
    val result = evaluate(id,"none")
    List(id, result.witnesses.fold(0,(mask,slot) => mask+place(slot)),
      result.answers.fold(0,(mask,scope) => mask+place(scope)), if (result.unionAnswer) 1 else 0)
  }
  pure val conformance = range(0,1024).foldl(List(),(cases,id) => cases.append(conformanceCase(id)))
}
