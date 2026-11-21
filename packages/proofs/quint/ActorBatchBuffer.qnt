// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorBatchBuffer {
  const Mutation: str
  val ordered = List(0, 1, 2)
  val prior = List(9)
  type State = {phase: int, buffer: List[int], written: int, generated: int,
    lease: List[int], delivered: List[int], limit: int, terminal: bool,
    stopped: bool, refused: bool, accepted: bool, readPastCount: bool,
    attemptedExact: bool, published: List[int]}
  var q: State

  action init = {
    nondet limit = Set(0, 1, 2, 3).oneOf()
    q' = {phase: 0, buffer: List(-1, -1), written: 0, generated: 0, lease: List(),
      delivered: List(), limit: limit, terminal: false, stopped: false, refused: false,
      accepted: false, readPastCount: false, attemptedExact: true, published: prior}
  }
  action Fill = all {
    q.phase == 0, q.written < 2, q.generated < ordered.length(),
    q' = {...q, buffer: q.buffer.replaceAt(q.written % 2, q.generated),
      written: q.written + 1, generated: q.generated + 1}
  }
  action Offer = all {
    q.phase == 0, q.written == 2 or q.generated == ordered.length(),
    q' = {...q, phase: 1, lease: q.buffer.slice(0, q.written),
      terminal: q.generated == ordered.length() and q.written < 2}
  }
  action ReuseWhileOffered = all {
    Mutation == "overwrite-before-credit", q.phase == 1,
    q' = {...q, buffer: q.buffer.replaceAt(0, 9)}
  }
  action Deliver = {
    val rows = if (Mutation == "read-past-count") q.buffer
               else if (Mutation == "drop-tail" and q.terminal) List()
               else q.buffer.slice(0, q.written)
    val room = q.limit - q.delivered.length()
    val fits = rows.length() <= room or Mutation == "omit-budget"
    val count = if (q.stopped) 0 else if (fits) rows.length() else room
    val attempted = if (q.stopped or fits or Mutation == "skip-refused-row") count else count + 1
    val orderedAttempt = rows.foldl(List(), (acc, row) =>
      if (not(q.stopped) and acc.length() <= room) acc.concat(List(row)) else acc)
    all {
      q.phase == 1,
      q' = {...q, phase: 2, delivered: q.delivered.concat(rows.slice(0, count)),
        readPastCount: q.readPastCount or rows.length() > q.written,
        attemptedExact: q.attemptedExact and rows.slice(0, attempted) == orderedAttempt,
        refused: q.stopped or not(fits)}
    }
  }
  action Credit = all {
    q.phase == 2 or (Mutation == "credit-before-read" and q.phase == 1),
    not(q.terminal), not(q.refused), not(q.stopped),
    q' = {...q, phase: 0, written: 0, lease: List()}
  }
  action Cancel = all {q.phase < 3, not(q.stopped), q' = {...q, stopped: true}}
  action Return = {
    nondet accepted = Set(true, false).oneOf()
    all {
      q.phase == 2, q.terminal or q.refused or q.stopped,
      q' = {...q, phase: 3, accepted: accepted,
        published: if (accepted and not(q.refused) and (not(q.stopped) or Mutation == "publish-canceled"))
                     q.delivered else prior}
    }
  }
  action step = any {Fill, Offer, ReuseWhileOffered, Deliver, Credit, Cancel, Return}
  val LeaseIntegrity = q.phase != 1 or q.buffer.slice(0, q.written) == q.lease
  val ReadExtent = not(q.readPastCount)
  val ExactDeliveredPrefix = q.delivered.length() <= ordered.length() and
    ordered.slice(0, q.delivered.length()) == q.delivered
  val ResourceExact = q.delivered.length() <= q.limit
  val AttemptedPrefix = q.attemptedExact
  val ExactPublication = q.published ==
    (if (q.phase == 3 and q.accepted and not(q.stopped) and not(q.refused)) ordered else prior)
}
