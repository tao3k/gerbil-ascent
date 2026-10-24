// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// One count scan over frozen binding outcomes; no rule solver replica.
module CountProbe {
  const Mutation: str
  var outcomes: List[bool]
  var remaining: int
  var position: int
  var count: int
  var published: int
  var phase: str
  var failed: bool
  pure def Count(xs: List[bool]): int = xs.foldl(0,(n,b) => n + (if (b) 1 else 0))
  action init = {
    nondet input = Set(List(), List(true,false), List(false,true), List(false,false)).oneOf();
    nondet budget = Set(0,1,2,3).oneOf();
    all {outcomes' = input, remaining' = budget, position' = 0, count' = 0,
      published' = -1, phase' = "working", failed' = false}
  }
  action probe = all {
    phase == "working",
    if (position == outcomes.length()) all {
      phase' = "complete", published' = count, count' = count,
      remaining' = remaining, position' = position, failed' = failed
    } else if (remaining == 0) all {
      phase' = "bounded", failed' = true,
      published' = if (Mutation == "refusal") count else -1,
      count' = count, remaining' = remaining, position' = position
    } else all {
      remaining' = remaining - 1, position' = position + 1,
      count' = count + (if (outcomes.nth(position) or Mutation == "unmatched") 1 else 0),
      phase' = if (Mutation == "early") "complete" else "working",
      published' = if (Mutation == "early") count else -1,
      failed' = failed
    }, outcomes' = outcomes
  }
  action resume = all {Mutation == "resume", phase == "bounded",
    phase' = "working", remaining' = 1, position' = position, count' = count,
    published' = published, outcomes' = outcomes, failed' = failed}
  action step = any {probe, resume}
  val PrefixCount = count == Count(outcomes.slice(0,position))
  val CompleteExact = phase == "complete" implies
    position == outcomes.length() and published == Count(outcomes) and not(failed)
  val PublishedOnlyComplete = phase != "complete" implies published == -1
  val FailureTerminal = failed implies phase == "bounded"
  val Bounds = remaining >= 0 and position >= 0 and position <= outcomes.length()
}
