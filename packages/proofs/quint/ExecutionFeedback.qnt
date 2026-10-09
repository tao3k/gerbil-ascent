// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ExecutionFeedback {
  const Mutation: str
  type State = {actual: Set[int], expected: Set[int], bound: bool, complete: bool,
    status: str, missing: Set[int], extra: Set[int]}
  var q: State
  action init = {
    nondet actual = Set(Set(), Set(0), Set(1), Set(0,1)).oneOf();
    nondet expected = Set(Set(), Set(0), Set(1), Set(0,1)).oneOf();
    nondet bound = Set(false,true).oneOf();
    nondet complete = Set(false,true).oneOf();
    q' = {actual: actual, expected: expected, bound: bound, complete: complete,
      status: "pending", missing: Set(), extra: Set()}
  }
  action grade = all {q.status == "pending",
    val admitted = (q.bound or Mutation == "stale") and (q.complete or Mutation == "partial")
    val missing = if (Mutation == "missing") Set() else q.expected.exclude(q.actual)
    val extra = if (Mutation == "extra") Set() else q.actual.exclude(q.expected)
    q' = if (admitted) {...q, status: if (missing == Set() and extra == Set()) "match" else "mismatch",
      missing: missing, extra: extra} else {...q, status: "inconclusive"}
  }
  action step = grade
  val Qualified = (q.status == "match" or q.status == "mismatch") implies q.bound and q.complete
  val ExactDifferences = (q.status == "match" or q.status == "mismatch") implies
    q.missing == q.expected.exclude(q.actual) and q.extra == q.actual.exclude(q.expected)
  val ExactMatch = q.status == "match" implies q.actual == q.expected
  val InconclusivePrivate = q.status == "inconclusive" implies q.missing == Set() and q.extra == Set()
}
