// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Two callers own prospective cuts only after acquiring the owner gate.
// The maintained solver is represented by exact finite ResultOf, not extracted.
module WithdrawalConcurrency {
  const Mutation: str
  const SecondExpected: int
  pure val Callers = Set(0,1)
  pure def expected(c: int): int = if (c == 0) 0 else SecondExpected
  pure def ResultOf(source: Set[int]): Set[int] = if (source == Set()) Set() else Set(9)
  type State = {holder: int, phase: int -> str, generation: int, source: Set[int], rows: Set[int],
    pending: int -> Set[int], receiptSource: int -> Set[int], receiptRows: int -> Set[int],
    receiptGeneration: int -> int, accepted: int, acceptedGenerations: Set[int]}
  var q: State
  action init = q' = {holder: -1, phase: Map(0 -> "waiting", 1 -> "waiting"),
    generation: 0, source: Set(0,1), rows: Set(9), pending: Map(0 -> Set(), 1 -> Set()),
    receiptSource: Map(0 -> Set(), 1 -> Set()), receiptRows: Map(0 -> Set(), 1 -> Set()),
    receiptGeneration: Map(0 -> -1, 1 -> -1), accepted: 0, acceptedGenerations: Set()}
  action Acquire(c: int): bool = all {q.holder == -1, q.phase.get(c) == "waiting",
    if (expected(c) == q.generation or Mutation == "outside")
      q' = {...q, holder: c, phase: q.phase.set(c, "checking"), pending: q.pending.set(c, q.source.exclude(Set(c)))}
    else q' = {...q, phase: q.phase.set(c, "rejected")}}
  action Check(c: int): bool = all {q.phase.get(c) == "checking", q.holder == c,
    q' = {...q, phase: q.phase.set(c, "ready")}}
  action Reject(c: int): bool = all {Set("checking", "ready").contains(q.phase.get(c)), q.holder == c,
    q' = {...q, phase: q.phase.set(c, "rejected"), holder: if (Mutation == "abandon") c else -1}}
  action Commit(c: int): bool = all {q.phase.get(c) == "ready", q.holder == c or Mutation == "earlyUnlock",
    q' = {...q, source: q.pending.get(c), rows: ResultOf(q.pending.get(c)), generation: q.generation+1,
      holder: -1, accepted: q.accepted+1, acceptedGenerations: q.acceptedGenerations.union(Set(expected(c))),
      phase: q.phase.set(c, if (Mutation == "lateReceipt") "published" else "returned"),
      receiptSource: q.receiptSource.set(c, q.pending.get(c)),
      receiptRows: q.receiptRows.set(c, ResultOf(q.pending.get(c))),
      receiptGeneration: q.receiptGeneration.set(c, q.generation+1)}}
  action EarlyUnlock(c: int): bool = all {Mutation == "earlyUnlock", q.holder == c, q.phase.get(c) == "ready",
    q' = {...q, holder: -1}}
  action ReturnLate(c: int): bool = all {q.phase.get(c) == "published",
    q' = {...q, phase: q.phase.set(c, "returned"), receiptSource: q.receiptSource.set(c, q.source),
      receiptRows: q.receiptRows.set(c, q.rows), receiptGeneration: q.receiptGeneration.set(c, q.generation)}}
  action step = {nondet c = Callers.oneOf(); any {Acquire(c), Check(c), Reject(c), Commit(c), EarlyUnlock(c), ReturnLate(c)}}
  val AtomicSnapshot = q.rows == ResultOf(q.source)
  val ExclusiveOwnership = Callers.forall(c => Set("checking", "ready").contains(q.phase.get(c)) implies q.holder == c)
  val TerminalReleased = q.holder == -1 or Set("checking", "ready").contains(q.phase.get(q.holder))
  val OnePublicationPerGeneration = q.accepted == q.acceptedGenerations.size()
  val ReceiptBound = Callers.forall(c => q.phase.get(c) == "returned" implies
    q.receiptGeneration.get(c) == expected(c)+1 and q.receiptRows.get(c) == ResultOf(q.receiptSource.get(c)))
}
