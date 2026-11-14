// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ReaderLifetime {
  const Rows: Set[int]
  const Readers: Set[int]
  const Budget: int
  const Mutation: str
  type State = {committed: Set[int], reading: Set[int], canceled: Set[int], alive: bool, current: int -> bool, valid: int -> bool,
    captured: int -> Set[int], accepted: Set[int], credits: int}
  var q: State
  pure val Initial = {committed: Set(), reading: Set(), canceled: Set(), alive: false, current: Readers.mapBy(_ => true), valid: Readers.mapBy(_ => true),
    captured: Readers.mapBy(_ => Set()), accepted: Set(), credits: 0}
  action init = q' = Initial
  action Publish = {nondet cut = Rows.powerset().oneOf(); all {cut.size() <= Budget,
    q' = {...q, committed: cut, current: Readers.mapBy(r => if (q.reading.contains(r)) {if (Mutation == "aba") q.captured.get(r) == cut else false} else q.current.get(r)),
      valid: Readers.mapBy(r => if (q.reading.contains(r)) false else q.valid.get(r)), accepted: Set()}}}
  action Borrow(r: int): bool = all {not(q.reading.contains(r)), q' = {...q, reading: q.reading.union(Set(r)), canceled: q.canceled.exclude(Set(r)), alive: true,
    current: q.current.set(r,true), valid: q.valid.set(r,true), captured: q.captured.set(r,q.committed), accepted: q.accepted.exclude(Set(r)), credits: q.credits+1}}
  action Cancel(r: int): bool = all {q.reading.exclude(q.canceled).contains(r), q' = {...q, canceled: q.canceled.union(Set(r))}}
  def released(r: int): State = {...q, reading: q.reading.exclude(Set(r)),
    alive: if (Mutation == "retire") false else q.reading.exclude(Set(r)) != Set(), credits: if (Mutation == "credit") q.credits else q.credits-1}
  action Drain(r: int): bool = all {q.reading.intersect(q.canceled).contains(r), q' = released(r)}
  action Reply(r: int): bool = all {q.reading.exclude(q.canceled).contains(r), q.current.get(r), q' = {...released(r), accepted: q.accepted.union(Set(r))}}
  action Discard(r: int): bool = all {q.reading.exclude(q.canceled).contains(r), not(q.current.get(r)), Mutation != "stuck", q' = released(r)}
  action Finish(r: int): bool = any {Drain(r), Reply(r), Discard(r)}
  action readerStep = {nondet r = Readers.oneOf(); any {Borrow(r), Cancel(r), Finish(r)}}
  action step = any {Publish, readerStep}
  action anyFinish = {nondet r = Readers.oneOf(); Finish(r)}
  temporal fairness = if (Mutation == "unfair") true else if (Mutation == "global") anyFinish.weakFair(q) else Readers.forall(r => Finish(r).weakFair(q))
  temporal spec = q == Initial and step.orKeep(q).always() and fairness
  temporal ReaderCompletion = Readers.forall(r => (q.reading.contains(r) implies not(q.reading.contains(r)).eventually()).always())
  val ReaderAlive = q.reading != Set() implies q.alive
  val CreditBalance = q.credits == q.reading.size()
  val AcceptedCurrent = q.accepted.forall(r => q.valid.get(r) and q.captured.get(r) == q.committed)
  pure val RoundInitial = {...Initial, reading: Readers, alive: Readers != Set(), credits: Readers.size()}
  action roundInit = q' = RoundInitial
  action roundReaderStep = {nondet r = Readers.oneOf(); any {Cancel(r), Finish(r)}}
  action roundStep = any {Publish, roundReaderStep}
  temporal roundFairness = if (Mutation == "unfair") true else anyFinish.weakFair(q)
  temporal roundSpec = q == RoundInitial and roundStep.orKeep(q).always() and roundFairness
  temporal RoundCompletion = (q.reading == Set()).eventually()

}
