// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorRankedFunctional {
  const Mutation: str
  type Row = (int, int)
  type Fixture = {edges: List[Row], seeds: List[Row], shape: bool}
  type State = {input: Fixture, certified: bool, frontier: List[Row],
    logical: List[Row], emitted: List[Row], expected: List[Row], rounds: int}
  var q: State

  val fixtures = Set(
    {edges: List((1, 3), (0, 1), (3, 4), (2, 3)), seeds: List(), shape: true},
    {edges: List((0, 1), (0, 1), (1, 2)), seeds: List(), shape: true},
    {edges: List((0, 1), (0, 2), (1, 3), (2, 3)), seeds: List(), shape: true},
    {edges: List((1, 2), (2, 1)), seeds: List(), shape: true},
    {edges: List((0, 1), (1, 2)), seeds: List((0, 2)), shape: true},
    {edges: List((0, 1), (1, 2)), seeds: List(), shape: false})
  pure def members(rows: List[Row]): Set[Row] =
    rows.foldl(Set(), (acc, row) => acc.union(Set(row)))
  pure def increasing(rows: List[Row]): bool =
    members(rows).forall(row => row._1 >= 0 and row._1 < row._2)
  pure def distinctOrigins(rows: List[Row]): bool =
    members(rows).map(row => row._1).size() == rows.length()
  pure def chooseRows(rows: List[Row], seen: List[Row]): List[Row] =
    rows.foldl(List(), (kept, row) =>
      if (members(seen).union(members(kept)).contains(row)) kept else kept.concat(List(row)))
  pure def reverseRows(rows: List[Row]): List[Row] =
    rows.foldl(List(), (reversed, row) => List(row).concat(reversed))
  pure def extendRows(rows: List[Row], edges: List[Row]): List[Row] =
    rows.foldl(List(), (acc, left) =>
      edges.foldl(acc, (out, right) =>
        if (left._2 == right._1) out.concat(List((left._1, right._2))) else out))

  action init = {
    nondet input = fixtures.oneOf()
    val base = chooseRows(input.edges, input.seeds)
    q' = {input: input,
      certified: (input.shape or Mutation == "ignore-shape")
        and (input.seeds.length() == 0 or Mutation == "ignore-seeds")
        and (increasing(input.edges) or Mutation == "ignore-rank")
        and (distinctOrigins(input.edges) or Mutation == "ignore-origins"),
      frontier: reverseRows(base), emitted: base, expected: base,
      logical: input.seeds.concat(base), rounds: 0}
  }
  action step = {
    val raw = extendRows(q.frontier, q.input.edges)
    val novel = chooseRows(raw, q.logical)
    val actual = if (q.certified) raw else novel
    all {q.rounds < 5, q.frontier.length() > 0,
      q' = {...q, frontier: reverseRows(actual), logical: q.logical.concat(novel),
        emitted: q.emitted.concat(actual), expected: q.expected.concat(novel), rounds: q.rounds + 1}}
  }
  val ExactGuard = not(q.certified) or (q.input.shape and q.input.seeds.length() == 0
    and increasing(q.input.edges) and distinctOrigins(q.input.edges))
  val FirstOccurrenceOrder = q.emitted == q.expected
}
