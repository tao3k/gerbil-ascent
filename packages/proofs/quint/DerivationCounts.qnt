// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Two synchronous equations; work/cap refusal never publishes partial counts.
module DerivationCounts {
  const Mutation: str
  var q: {seed: int, recursive: bool, source: int, answer: int,
    remaining: int, cap: int, phase: str, published: int}
  action init = {
    nondet seed = Set(0,1,2).oneOf()
    nondet recursive = Set(false,true).oneOf()
    nondet budget = Set(0,1,2,3,4).oneOf()
    nondet cap = Set(1,4).oneOf()
    q' = {seed: seed, recursive: recursive, source: 0, answer: 0,
      remaining: budget, cap: cap, phase: "working", published: -1}
  }
  action round = {
    val target = if (q.recursive) q.source + q.answer else q.source * q.source
    val updated = target +
      (if (Mutation == "accumulate") q.answer else 0)
    val stable = q.source == q.seed and target == q.answer
    all {q.phase == "working",
      q' = if (q.remaining == 0 or q.seed > q.cap or updated > q.cap)
        {...q, phase: "bounded", published: if (Mutation == "refusal") q.answer else -1}
      else if (stable or Mutation == "early")
        {...q, source: q.seed, answer: updated, remaining: q.remaining - 1,
          phase: "complete", published: updated}
      else {...q, source: q.seed, answer: updated, remaining: q.remaining - 1}
    }
  }
  action step = round
  val Private = q.phase != "complete" implies q.published == -1
  val Fixed = q.phase == "complete" implies q.source == q.seed and
    q.answer == (if (q.recursive) q.source + q.answer else q.source * q.source)
  val Exact = q.phase == "complete" implies
    (if (q.recursive) q.seed == 0 and q.published == 0 else q.published == q.seed * q.seed)
}
