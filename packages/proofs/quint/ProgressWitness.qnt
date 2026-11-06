// Finite protocol abstraction: the host attests completed work, not CPU ticks.
// Epochs are process incarnations, never machine worker counts.
module ProgressWitness {
  const Mutation: str
  type State = { epoch: int, cursor: int, now: int, last: int,
    groundedLast: int, accepted: bool, grounded: bool, chosen: int, choice: int }
  var q: State
  action init = q' = {epoch: 0, cursor: 0, now: 0, last: 0,
    groundedLast: 0, accepted: false, grounded: false, chosen: -1, choice: -1}
  action tick = all {q.now < 5, q' = {...q, now: q.now + 1, accepted: false}}
  action sample = {
    // Good, duplicate, wrong actor, stale epoch, heartbeat, unattested,
    // regressed counter, changed source, conflicting observation identity,
    // missing cursor, conflicting cursors, conflicting active incarnations.
    nondet kind = Set(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11).oneOf()
    val counter = if (kind == 1) q.cursor else if (kind == 6) 0
      else if (q.cursor < 2) q.cursor + 1 else 2
    val grounded = kind == 0 and counter > q.cursor
    val accept = counter > q.cursor and
      (kind == 0 or (Mutation == "wrong-actor" and kind == 2)
        or (Mutation == "stale-epoch" and kind == 3)
        or (Mutation == "heartbeat" and kind == 4)
        or (Mutation == "unattested" and kind == 5)
        or (Mutation == "changed-source" and kind == 7)
        or (Mutation == "conflicting-id" and kind == 8)
        or (Mutation == "cursor-missing" and kind == 9)
        or (Mutation == "cursor-conflicting" and kind == 10)
        or (Mutation == "active-conflicting" and kind == 11))
      or (Mutation == "duplicate" and kind == 1)
    q' = {...q, cursor: if (accept) counter else q.cursor,
      last: if (accept) q.now else q.last,
      groundedLast: if (grounded) q.now else q.groundedLast,
      accepted: accept, grounded: grounded}
  }
  action restore = q' = {...q, accepted: false,
    last: if (Mutation == "resume-renews") q.now else q.last}
  // New process ownership is external. Prior samples never acquire this epoch.
  action newProcess = all {q.epoch == 0,
    q' = {...q, epoch: 1, cursor: 0, last: q.now, groundedLast: q.now,
      accepted: false, grounded: false}}
  action choose = {nondet c = Set(-1, 0, 7).oneOf();
    q' = {...q, choice: c, chosen: c}}
  action step = any {tick, sample, restore, newProcess, choose}
  val OnlyGroundedCompletion = q.accepted implies q.grounded
  val NoInventedTime = q.last == q.groundedLast
  val RestoredCursorNotPermission = q.choice == q.chosen
  val Safety = OnlyGroundedCompletion and NoInventedTime and RestoredCursorNotPermission
}
