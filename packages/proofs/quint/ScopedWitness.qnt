// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ScopedWitness {
  const Mutation: str
  type State = {id: int, phase: str, witnesses: Set[int], answer: bool}
  var q: State
  pure def bit(id: int, place: int): bool = (id / place) % 2 == 1
  pure def path(id: int, w: int): bool =
    if (w == 1) bit(id,1) and bit(id,2) else bit(id,4) and bit(id,8)
  pure def blocked(id: int, w: int): bool = bit(id, if (w == 1) 16 else 32)
  pure def expectedWitnesses(id: int): Set[int] = Set(1,2).filter(w => path(id,w) and not(blocked(id,w)))
  pure def expectedAnswer(id: int): bool = expectedWitnesses(id) != Set() or bit(id,128)
  pure def evaluate(id: int, mutation: str): State = {
    val anyBlocked = Set(1,2).exists(w => path(id,w) and blocked(id,w))
    val witnesses = Set(1,2).filter(w => path(id,w) and
      (if (mutation == "late") not(bit(id,64))
       else if (mutation == "anyBlocked") not(anyBlocked) else not(blocked(id,w))))
    val answer = (witnesses != Set() or bit(id,128)) and
      (mutation != "global" or not(bit(id,64)))
    {id: id, phase: "complete", witnesses: if (mutation == "forget") Set() else witnesses, answer: answer}
  }
  action init = {nondet id = 0.to(255).oneOf(); q' = {id:id, phase:"pending", witnesses:Set(), answer:false}}
  action step = all {q.phase == "pending", q' = evaluate(q.id,Mutation)}
  val ExactWitnesses = q.phase == "complete" implies q.witnesses == expectedWitnesses(q.id)
  val ExactAnswer = q.phase == "complete" implies q.answer == expectedAnswer(q.id)
  val Private = q.phase != "complete" implies q.witnesses == Set() and not(q.answer)
  pure def conformanceCase(id: int): List[int] = {
    val result = evaluate(id,"none")
    List(id, (if (result.witnesses.contains(1)) 1 else 0) + (if (result.witnesses.contains(2)) 2 else 0),
      if (result.answer) 1 else 0)
  }
  pure val conformance = range(0,256).foldl(List(), (cases,id) => cases.append(conformanceCase(id)))
}
