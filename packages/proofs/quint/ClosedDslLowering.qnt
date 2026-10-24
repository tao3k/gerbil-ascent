// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Whole-source choice precedes construction; failure never retries another route.
module ClosedDslLowering {
  const Mutation: str
  var phase: str
  var recognized: bool
  var route: str
  var attempts: int
  var owner: bool
  var rejected: bool
  action init = all {
    phase' = "reader", recognized' = false, route' = "none",
    attempts' = 0, owner' = false, rejected' = false
  }
  action Read = { nondet complete = Set(false,true).oneOf(); all {
    phase == "reader", phase' = "chosen", recognized' = complete,
    route' = if (complete or Mutation == "partial") "closed" else "macro",
    attempts' = attempts, owner' = owner, rejected' = rejected
  }}
  action Reject = all {
    phase == "reader", phase' = "terminal", rejected' = true,
    recognized' = recognized, route' = route, attempts' = attempts,
    owner' = Mutation == "rejectOwner"
  }
  action Construct = all {
    phase == "chosen", phase' = "executing", attempts' = attempts + 1,
    recognized' = recognized, route' = route, owner' = owner, rejected' = rejected
  }
  action Finish = { nondet success = Set(false,true).oneOf(); all {
    phase == "executing", phase' = "terminal", owner' = success,
    attempts' = if (not(success) and Mutation == "retry") attempts + 1 else attempts,
    recognized' = recognized, route' = route, rejected' = not(success)
  }}
  action Idle = all {
    phase == "terminal", phase' = phase, recognized' = recognized,
    route' = route, attempts' = attempts, owner' = owner, rejected' = rejected
  }
  action step = any {Read, Reject, Construct, Finish, Idle}
  // Canonical positive snapshot occurrences: caller root + copied root.
  // The old copier also performs Term, Atom and Rule intermediate checks.
  pure def snapshot_checks(terms: int, captured: bool): int =
    if (not(captured) or Mutation == "retain-snapshot-intermediate") 5 * terms
    else if (Mutation == "skip-snapshot-root") terms else 2 * terms
  val SnapshotRoots = snapshot_checks(14, true) == 2 * 14 and attempts >= 0
  val SnapshotWorkExact = snapshot_checks(14, false) - snapshot_checks(14, true) == 3 * 14 and attempts >= 0
  val WholeChoice = route != "closed" or recognized
  val NoRetry = attempts <= 1
  val FailurePrivate = not(rejected) or not(owner)
}
