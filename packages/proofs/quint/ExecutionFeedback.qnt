// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ExecutionFeedback {
  const Mutation: str
  type State = {actual: Set[int], expected: Set[int], bound: bool, complete: bool,
    paired: bool, referenceBound: bool, referenceComplete: bool, sameQuery: bool,
    status: str, missing: Set[int], extra: Set[int]}
  var q: State
  action init = {
    nondet actual = Set(Set(), Set(0), Set(1), Set(0,1)).oneOf();
    nondet expected = Set(Set(), Set(0), Set(1), Set(0,1)).oneOf();
    nondet bound = Set(false,true).oneOf();
    nondet complete = Set(false,true).oneOf();
    nondet paired = Set(false,true).oneOf();
    nondet referenceBound = Set(false,true).oneOf();
    nondet referenceComplete = Set(false,true).oneOf();
    nondet sameQuery = Set(false,true).oneOf();
    q' = {actual: actual, expected: expected, bound: bound, complete: complete,
      paired: paired, referenceBound: referenceBound, referenceComplete: referenceComplete, sameQuery: sameQuery,
      status: "pending", missing: Set(), extra: Set()}
  }
  pure def evaluate(s: State, mutation: str): State = {
    val referenceAdmitted = not(s.paired) or
      ((s.referenceBound or mutation == "referenceStale") and
       (s.referenceComplete or mutation == "referencePartial") and
       (s.sameQuery or mutation == "query"))
    val admitted = (s.bound or mutation == "stale") and (s.complete or mutation == "partial") and referenceAdmitted
    val missing = if (mutation == "missing") Set() else s.expected.exclude(s.actual)
    val extra = if (mutation == "extra") Set() else s.actual.exclude(s.expected)
    if (admitted) {...s, status: if (missing == Set() and extra == Set()) "match" else "mismatch",
      missing: missing, extra: extra} else {...s, status: "inconclusive"}
  }
  action grade = all {q.status == "pending", q' = evaluate(q, Mutation)}
  pure def bit(id: int, place: int): bool = (id / place) % 2 == 1
  pure def rows(mask: int): Set[int] = Set(0,1).filter(v => bit(mask, if (v == 0) 1 else 2))
  pure def mask(rows: Set[int]): int = (if (rows.contains(0)) 1 else 0) + (if (rows.contains(1)) 2 else 0)
  // All 1024 initial states, in deterministic ID order; shared with the actual
  // grade transition, not a second grading implementation in a generator.
  pure def conformanceCase(id: int): List[int] = {
    val s = {actual: rows(id % 4), expected: rows((id / 4) % 4),
      bound: bit(id,16), complete: bit(id,32), paired: bit(id,64),
      referenceBound: bit(id,128), referenceComplete: bit(id,256), sameQuery: bit(id,512),
      status: "pending", missing: Set(), extra: Set()}
    val result = evaluate(s,"none")
    List(id, if (result.status == "inconclusive") 0 else if (result.status == "match") 1 else 2,
      mask(result.missing), mask(result.extra))
  }
  pure val conformance = range(0,1024).foldl(List(), (allCases,id) => allCases.append(conformanceCase(id)))
  action step = grade
  val Qualified = (q.status == "match" or q.status == "mismatch") implies
    q.bound and q.complete and (not(q.paired) or (q.referenceBound and q.referenceComplete and q.sameQuery))
  val ExactDifferences = (q.status == "match" or q.status == "mismatch") implies
    q.missing == q.expected.exclude(q.actual) and q.extra == q.actual.exclude(q.expected)
  val ExactMatch = q.status == "match" implies q.actual == q.expected
  val InconclusivePrivate = q.status == "inconclusive" implies q.missing == Set() and q.extra == Set()
}
