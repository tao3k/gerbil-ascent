// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Private validated predecessor index. Rule/source semantics are finite controls.
module ProofPrefix {
  const Mutation: str
  type State = {deps: List[int], cursor: int, known: Set[int], grounded: Set[int],
    phase: str, refused: bool, published: Set[int]}
  var q: State
  action init = {
    nondet graph = Set(List(-1,0,1), List(-1,-1,1), List(-1,2,1), List(-1,1,1), List(-2,0,1)).oneOf();
    q' = {deps: graph, cursor: 0, known: Set(), grounded: Set(), phase: "working", refused: false, published: Set()}
  }
  action visit = all {q.phase == "working", q.cursor < q.deps.length(),
    val dep = q.deps.nth(q.cursor)
    val justified = dep == -1 or (dep >= 0 and dep < q.cursor and q.grounded.contains(dep))
    val checked = dep == -1 or (dep >= 0 and dep < q.cursor and q.known.contains(dep)) or
      (Mutation == "forward" and dep >= 0 and dep < q.deps.length()) or
      (Mutation == "source" and dep == -2)
    q' = if (checked) {...q, cursor: q.cursor + 1, known: q.known.union(Set(q.cursor)),
      grounded: if (justified) q.grounded.union(Set(q.cursor)) else q.grounded}
      else {...q, phase: "invalid", refused: true,
        known: if (Mutation == "early") q.known.union(Set(q.cursor)) else q.known,
        published: if (Mutation == "partial") q.known else Set()}
  }
  action complete = all {q.phase == "working", q.cursor == q.deps.length(),
    q' = {...q, phase: "complete", published: Set(q.cursor - 1)}}
  action step = any {visit, complete}
  val ExactPrefix = q.known == Set(0,1,2).filter(id => id < q.cursor)
  val GroundedPrefix = q.known.subseteq(q.grounded)
  val PublishedGrounded = q.published.subseteq(q.grounded) and
    (q.phase == "complete" implies q.cursor == q.deps.length())
  val RefusalPrivate = q.refused implies q.phase == "invalid" and q.published == Set()
  val PublicationPhase = q.phase != "complete" implies q.published == Set()
}
