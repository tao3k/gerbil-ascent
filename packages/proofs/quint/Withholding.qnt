// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module Withholding {
  const Mutation: str
  type State = {heads: List[int], bodies: List[int], cursor: int,
    removed: Set[int], protected: Set[int], phase: str, published: Set[int], bound: bool}
  var q: State
  val source = Set(0,1,2)
  action init = {
    nondet selection = Set((List(0,1),List(2,0)), (List(0,1),List(2,2)),
      (List(0),List(3)), (List(0),List(2))).oneOf();
    nondet bound = Set(false,true).oneOf();
    q' = {heads: selection._1, bodies: selection._2, cursor: 0, removed: Set(),
      protected: Set(), phase: "collect", published: Set(), bound: bound}
  }
  action collect = all {q.phase == "collect", q.cursor < q.heads.length(),
    q' = {...q, cursor: q.cursor + 1, removed: q.removed.union(Set(q.heads.nth(q.cursor))),
      protected: q.protected.union(Set(q.bodies.nth(q.cursor))),
      published: if (Mutation == "early") source.exclude(q.removed.union(Set(q.heads.nth(q.cursor)))) else Set()}
  }
  action publish = all {q.phase == "collect", q.cursor == q.heads.length(),
    val protected = if (Mutation == "local") Set(q.bodies.nth(0)) else q.protected
    val valid = (q.bound or Mutation == "stale") and q.removed.subseteq(source) and
      (q.protected.subseteq(source) or Mutation == "missing") and q.removed.intersect(protected) == Set()
    q' = if (valid) {...q, phase: "complete", published: source.exclude(q.removed)}
      else {...q, phase: "refused", published: Set()}
  }
  action step = any {collect, publish}
  val Private = q.phase != "complete" implies q.published == Set()
  val Bound = q.phase == "complete" implies q.bound
  val Protected = q.phase == "complete" implies q.protected.subseteq(q.published)
  val ExactCut = q.phase == "complete" implies q.published == source.exclude(q.removed)
}
