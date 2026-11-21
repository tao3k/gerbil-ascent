// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorSourceCertificate {
  const Mutation: str
  type State = {root: int, captured: List[int], current: List[int],
    ordered: bool, read: bool, borrowed: bool}
  var q: State

  pure def strict(rows: List[int], ascending: bool): bool =
    rows.indices().forall(i =>
      if (i == 0) true
      else if (ascending) rows.nth(i - 1) < rows.nth(i)
      else rows.nth(i) < rows.nth(i - 1))

  action init = {
    nondet source = Set(List(1, 2, 3), List(6, 4, 1), List(1, 2, 2), List(1, 3, 2)).oneOf()
    val ordered = strict(source, true) or strict(source, false)
    q' = {root: 0, captured: source, current: source, ordered: ordered,
      read: false, borrowed: false}
  }

  action replace = all {
    not(q.read), q.root == 0,
    q' = {...q, root: 1, current: List(1, 1, 3)}
  }

  action extend = all {
    not(q.read), q.root == 0,
    q' = {...q, root: 2, current: q.current.append(q.current.nth(0))}
  }

  action admit = all {
    not(q.read),
    q' = {...q, read: true,
      borrowed:
        (q.ordered or Mutation == "ignore-order")
        and (q.root == 0 or (q.root == 1 and Mutation == "match-size")
          or (q.root == 2 and Mutation == "carry-after-append"))}
  }

  action step = any {replace, extend, admit}

  val ExactRoot = not(q.borrowed) or (q.root == 0 and q.current == q.captured)
  val UniqueOrigins = not(q.borrowed) or q.current.indices().map(i => q.current.nth(i)).size()
    == q.current.length()
}
