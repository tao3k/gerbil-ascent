// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorLocalCredit {
  const Mutation: str
  val expected = List(0, 1, 2)
  val prior = List(9)
  type State = {stage: int, limit: int, staged: List[int], published: List[int],
    canceled: bool, failed: bool, terminal: bool, returned: bool,
    ownerAccepted: bool, mergedAfterCancel: bool, yields: int}
  var q: State

  action init = {
    nondet limit = Set(0, 1, 2, 3).oneOf()
    q' = {stage: 0, limit: limit, staged: List(), published: prior,
      canceled: false, failed: false, terminal: false, returned: false,
      ownerAccepted: false, mergedAfterCancel: false, yields: 0}
  }
  action Cancel = all {not(q.returned), not(q.canceled), q' = {...q, canceled: true}}
  // A full batch, a poll-only credit and the terminal tail.
  action Credit = {
    val offered = if (q.stage == 0) List(0, 1) else if (q.stage == 1) List() else List(2)
    val ordered = if (Mutation == "reverse-batch" and q.stage == 0) List(1, 0) else offered
    val allowed = not(q.canceled) or Mutation == "skip-cancel"
    val staged = ordered.foldl(q.staged, (rows, row) =>
      if (allowed and (rows.length() < q.limit or Mutation == "skip-budget") and
          not(q.stage == 2 and Mutation == "drop-tail")) rows.concat(List(row)) else rows)
    all {
      not(q.returned), not(q.failed), not(q.terminal),
      q' = {...q, stage: q.stage + 1, staged: staged,
        terminal: q.stage == 2,
        failed: not(allowed) or staged.length() < q.staged.length() + offered.length()
          and Mutation != "drop-tail",
        mergedAfterCancel: q.mergedAfterCancel or
          (q.canceled and staged.length() > q.staged.length()),
        yields: q.yields + (if (Mutation == "skip-yield") 0 else 1)}
    }
  }
  action Return = {
    nondet ownerAccepted = Set(true, false).oneOf()
    all {
      not(q.returned), q.failed or q.terminal,
      q' = {...q, returned: true, ownerAccepted: ownerAccepted,
        published: if ((ownerAccepted or Mutation == "skip-owner") and not(q.failed)
                       and (not(q.canceled) or Mutation == "publish-canceled"))
                   q.staged else prior}
    }
  }
  action step = any {Cancel, Credit, Return}
  val OrderedPrefix = expected.slice(0, q.staged.length()) == q.staged
  val ResourceExact = q.staged.length() <= q.limit
  val NoCanceledMerge = not(q.mergedAfterCancel)
  val YieldAtCredit = q.yields == q.stage
  val PublicationExact = q.published == prior or
    (q.returned and q.terminal and not(q.failed) and not(q.canceled)
     and q.ownerAccepted and q.published == expected)
}
