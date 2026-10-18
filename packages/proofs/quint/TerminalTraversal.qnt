// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Outcomes are post-callback liveness, not visitor return values.
module TerminalTraversal {
  const Mutation: str
  var outcomes: List[bool]
  var position: int
  var stoppedAt: int
  var phase: str
  action init = {
    nondet input = Set(List(), List(true,true), List(false,true), List(true,false,true)).oneOf();
    all {outcomes' = input, position' = 0, stoppedAt' = -1, phase' = "working"}
  }
  action visit = all {
    phase == "working",
    if (position == outcomes.length()) all {
      phase' = "complete", position' = position, stoppedAt' = stoppedAt
    } else all {
      position' = position + 1,
      stoppedAt' = if (outcomes.nth(position)) stoppedAt else position + 1,
      phase' = if (Mutation == "early") "complete"
        else if (outcomes.nth(position) or Mutation == "skip") "working" else "bounded"
    }, outcomes' = outcomes
  }
  action scanTail = all {Mutation == "tail", phase == "bounded", position < outcomes.length(),
    position' = position + 1, phase' = phase, stoppedAt' = stoppedAt, outcomes' = outcomes}
  action resume = all {Mutation == "resume", phase == "bounded",
    phase' = "working", position' = position, stoppedAt' = stoppedAt, outcomes' = outcomes}
  action step = any {visit, scanTail, resume}
  val Bounds = position >= 0 and position <= outcomes.length()
  val FailureFrozen = stoppedAt != -1 implies position == stoppedAt and phase == "bounded"
  val CompletedScan = phase == "complete" implies
    position == outcomes.length() and stoppedAt == -1
}
