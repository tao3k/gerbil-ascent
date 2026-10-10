// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Frozen matching outcomes; 999 tags a noninteger, not the integer 999.
module NumericProbe {
  const Mutation: str
  var input: List[int]
  var mode: int
  var position: int
  var remaining: int
  var value: int
  var seen: bool
  var valid: bool
  var produced: bool
  var phase: str
  pure def Expected(m: int, xs: List[int]): int =
    if (m == 0) xs.foldl(0,(a,b) => a+b)
    else if (xs.length() == 0) 0
    else xs.slice(1,xs.length()).foldl(xs.nth(0),(a,b) => if (m == 1) (if (a < b) a else b) else (if (a > b) a else b))
  action init = {
    nondet rows = Set(List(),List(2,3),List(-2,-3),List(999,2),List(2,999),List(0)).oneOf();
    nondet kind = Set(0,1,2).oneOf();
    nondet budget = Set(0,1,2).oneOf();
    all {input' = rows, mode' = kind, position' = 0, remaining' = budget,
      value' = 0, seen' = Mutation == "empty", valid' = true, produced' = false, phase' = "working"}
  }
  action probe = all {
    phase == "working",
    if (position == input.length()) all {
      phase' = "complete", produced' = (valid and (mode == 0 or seen)),
      position' = position, remaining' = remaining, value' = value, seen' = seen, valid' = valid
    } else if (remaining == 0) all {
      phase' = "bounded", produced' = Mutation == "refusal",
      position' = position, remaining' = remaining, value' = value, seen' = seen, valid' = valid
    } else {
      val row = input.nth(position);
      all {
        position' = position + 1, remaining' = remaining - 1,
        valid' = (valid and (row != 999 or Mutation == "type-skip")),
        seen' = (seen or (valid and row != 999)),
        value' = if (not(valid) or row == 999) value else if (mode == 0) value + row
          else if (not(seen)) (if (Mutation == "zero") 0 else row)
          else if (mode == 1) (if (value < row) value else row) else (if (value > row) value else row),
        phase' = if (Mutation == "early") "complete" else "working",
        produced' = Mutation == "early"
      }
    }, input' = input, mode' = mode
  }
  action step = probe
  val TypedPrefix = valid == input.slice(0,position).indices().forall(i => input.nth(i) != 999)
  val PrefixValue = valid implies
    seen == (position > 0) and value == Expected(mode,input.slice(0,position))
  val PublicationExact = phase == "complete" implies
    position == input.length() and produced == (valid and (mode == 0 or seen))
  val Unpublished = phase != "complete" implies not(produced)
  val Bounds = remaining >= 0 and position >= 0 and position <= input.length()
}
