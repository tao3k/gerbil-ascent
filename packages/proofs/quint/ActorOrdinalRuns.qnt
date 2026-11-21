// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorOrdinalRuns {
  const Mutation: str
  type Row = (int, int)
  type Fixture = {links: List[int], direction: int}
  type State = {input: Fixture, depth: int, expected: List[Row], actual: List[Row]}
  var q: State

  val ascending = List(0, 1, 2, 3, 4)
  val descending = List(4, 3, 2, 1, 0)
  val inputs = Set(
    {links: List(1, 2, -1, 4, -1), direction: 1},
    {links: List(-1, 0, 1, -1, 3), direction: -1},
    {links: List(2, -1, -1, 4, -1), direction: 0})

  pure def ordered(depth: int): List[int] =
    if (depth % 2 == 0) ascending else descending

  pure def follow(links: List[int], origin: int, depth: int): int =
    0.to(4).fold(origin, (current, i) =>
      if (i >= depth or current < 0) current else links.nth(current))

  pure def reference(input: Fixture, depth: int): List[Row] =
    ordered(depth).foldl(List(), (rows, origin) => {
      val endpoint = follow(input.links, origin, depth)
      if (endpoint >= 0) rows.append((origin, endpoint)) else rows
    })

  pure def gather(input: Fixture, depth: int): List[Row] =
    if (input.direction == 0) reference(input, depth)
    else {
      val slots = if (Mutation == "keep-forward") ascending else ordered(depth)
      val sign = if (Mutation == "wrong-direction") -input.direction else input.direction
      slots.foldl(List(), (rows, origin) => {
        val endpoint = origin + sign * depth
        val within = endpoint >= 0 and endpoint < 5
        val sameRun = (origin < 3) == (endpoint < 3)
        if (within and (sameRun or Mutation == "cross-boundary")) rows.append((origin, endpoint))
        else rows
      })
    }

  pure def reverseRows(rows: List[Row]): List[Row] =
    rows.foldl(List(), (output, row) => List(row).concat(output))

  pure def publicRows(input: Fixture): List[Row] =
    List(0, 1, 2, 3, 4).foldl(List(), (output, depth) =>
      reverseRows(reference(input, depth)).concat(output))

  pure def streamedRows(input: Fixture): List[Row] =
    if (input.direction == 0) publicRows(input)
    else {
      val depths = if (Mutation == "keep-depth-order") List(0, 1, 2, 3, 4)
                   else List(4, 3, 2, 1, 0)
      depths.foldl(List(), (output, depth) => {
        val slots = ordered(if (Mutation == "keep-run-order") depth else depth + 1)
        slots.foldl(output, (rows, origin) => {
          val endpoint = origin + input.direction * depth
          val within = endpoint >= 0 and endpoint < 5
          val sameRun = (origin < 3) == (endpoint < 3)
          if (within and sameRun) rows.append((origin, endpoint)) else rows
        })
      })
    }

  action init = {
    nondet input = inputs.oneOf()
    q' = {input: input, depth: 0, expected: reference(input, 0), actual: gather(input, 0)}
  }
  action step = all {
    q.depth < 4,
    q' = {...q, depth: q.depth + 1, expected: reference(q.input, q.depth + 1),
      actual: gather(q.input, q.depth + 1)}
  }
  val ExactEmission = q.actual == q.expected
  val ExactPublicStream = streamedRows(q.input) == publicRows(q.input)
}
