// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorPairMembership {
  const Mutation: str
  type Row = (int, int)
  type Key = (str, int, int)
  val candidates = Set((-1, 1), (0, 1), (0, 4), (1, 0), (3, 3), (4, 0), (5, 0))
  val seeds = Set((0, 1), (4, 0))
  pure def key(row: Row): Key = {
    val inside = row._1 >= 0 and row._1 < 4 and row._2 >= 0 and row._2 < 4
    val mixed = (row._2 + 3 * row._1) % 4
    if (Mutation == "unbounded") ("packed", 4 * row._1 + row._2, 0)
    else if (inside and Mutation == "short-radix") ("packed", row._1 + row._2, 0)
    else if (inside) ("packed", 4 * row._1 + mixed, 0)
    else if (Mutation == "coalesce-overflow") ("row", 0, 0)
    else ("row", row._1, row._2)
  }
  type State = {seen: Set[Key], logical: Set[Row], emitted: List[Row], expected: List[Row], steps: int}
  var q: State
  action init = q' = {seen: if (Mutation == "ignore-seeds") Set() else seeds.map(key),
    logical: seeds, emitted: List(), expected: List(), steps: 0}
  action step = {
    nondet row = candidates.oneOf()
    val present = q.seen.contains(key(row))
    all { q.steps < 5,
      q' = {seen: q.seen.union(Set(key(row))), logical: q.logical.union(Set(row)),
        emitted: if (present) q.emitted else q.emitted.concat(List(row)),
        expected: if (q.logical.contains(row)) q.expected else q.expected.concat(List(row)),
        steps: q.steps + 1} }
  }
  val ExactMembership = candidates.forall(row => q.seen.contains(key(row)) == q.logical.contains(row))
  val ExactFirstOccurrence = q.emitted == q.expected
}
