// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorIdentityRead {
  const Mutation: str
  val source = List(9, 2, 2, 1)
  val seed = Set(9)
  val expected = List(2, 1)
  type State = {index: int, checkpoints: int, privateRows: List[int], seen: Set[int],
    owned: bool, identitySlots: bool, externalRead: bool, direct: bool,
    limit: int, failed: bool, canceled: bool, returned: bool, accepted: bool,
    published: List[int]}
  var q: State

  action init = {
    nondet owned = Set(true, false).oneOf()
    nondet identitySlots = Set(true, false).oneOf()
    nondet externalRead = Set(true, false).oneOf()
    nondet limit = Set(0, 1, 2).oneOf()
    q' = {index: 0, checkpoints: 0, privateRows: List(), seen: seed,
      owned: owned, identitySlots: identitySlots, externalRead: externalRead,
      direct: (owned or Mutation == "unowned") and (identitySlots or Mutation == "wrong-slots")
        and (externalRead or Mutation == "feedback"), limit: limit,
      failed: false, canceled: false, returned: false, accepted: false, published: List()}
  }
  action Step = {
    val row = source[if (q.index < source.length()) q.index else 0]
    val novel = not(q.seen.contains(row)) or q.direct and Mutation == "omit-membership"
    val charged = novel and (q.privateRows.length() < q.limit or Mutation == "omit-budget")
    all {
      not(q.failed), not(q.canceled), not(q.returned), q.index < source.length(),
      q' = {...q, index: q.index + 1, seen: if (charged) q.seen.union(Set(row)) else q.seen,
        checkpoints: q.checkpoints + (if (q.direct and not(novel) and Mutation == "skip-duplicate-checkpoint") 0 else 1),
        privateRows: if (charged) q.privateRows.concat(List(row)) else q.privateRows,
        failed: novel and not(charged)}
    }
  }
  action Cancel = all {not(q.returned), not(q.canceled), q' = {...q, canceled: true}}
  action Return = {
    nondet accepted = Set(true, false).oneOf()
    all {
      not(q.returned), q.failed or q.canceled or q.index == source.length(),
      q' = {...q, returned: true, accepted: accepted,
        published: if (accepted and not(q.failed) and (not(q.canceled) or Mutation == "publish-canceled"))
                     q.privateRows else List()}
    }
  }
  action step = any {Step, Cancel, Return}
  val ExactGuard = not(q.direct) or (q.owned and q.identitySlots and q.externalRead)
  val PerOccurrenceCheckpoint = q.checkpoints == q.index
  val FirstOccurrenceOrder = q.privateRows.length() <= expected.length() and
    expected.slice(0, q.privateRows.length()) == q.privateRows
  val ExactBudget = q.privateRows.length() <= q.limit
  val ExactPublication = q.published ==
    (if (q.returned and q.accepted and not(q.failed) and not(q.canceled)) expected else List())
}
