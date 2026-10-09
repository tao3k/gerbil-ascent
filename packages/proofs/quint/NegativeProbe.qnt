// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// One frozen negative atom. Binding outcomes are input, not a solver model.
module NegativeProbe {
  const Mutation: str
  var outcomes: List[bool]
  var remaining: int
  var position: int
  var phase: str
  var failed: bool
  action init = {
    nondet input = Set(List(), List(true, false), List(false, true), List(false, false)).oneOf();
    nondet budget = Set(0,1,2,3).oneOf();
    all {
    outcomes' = input, remaining' = budget, position' = 0,
    phase' = "working", failed' = false }
  }
  action probe = all {
    phase == "working",
    if (remaining == 0) all {
      phase' = if (Mutation == "refusal") "absent" else "bounded",
      failed' = true, remaining' = remaining, position' = position
    } else if (position == outcomes.length()) all {
      phase' = "absent", remaining' = remaining - 1,
      position' = position, failed' = failed
    } else all {
      remaining' = remaining - 1, position' = position + 1,
      phase' = if (outcomes.nth(position)) "matched" else if (Mutation == "early") "absent" else "working",
      failed' = failed
    }, outcomes' = outcomes
  }
  action resume = all {Mutation == "resume", phase == "bounded",
    phase' = "working", remaining' = 1, position' = position,
    outcomes' = outcomes, failed' = failed}
  action step = any {probe, resume}
  val AbsenceSound = phase == "absent" implies
    position == outcomes.length() and outcomes.foldl(true,(clear,value) => clear and not(value)) and not(failed)
  val WitnessSound = phase == "matched" implies
    position > 0 and position <= outcomes.length() and outcomes.nth(position - 1)
  val FailureTerminal = failed implies phase == "bounded"
  val Bounds = remaining >= 0 and position >= 0 and position <= outcomes.length()
}
