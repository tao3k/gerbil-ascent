// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module EvidenceConsumption {
  const Mutation: str
  var generation: int
  var reference: int
  var consumption: int
  var intentOK: bool
  var finished: bool
  var cost: int
  var first: int
  action init = all { generation' = 0, reference' = -1, consumption' = -1,
    intentOK' = false, finished' = false, cost' = 0, first' = -1 }
  action Evidence = all {reference' = generation, generation' = generation,
    consumption' = consumption, intentOK' = intentOK, finished' = finished, cost' = cost, first' = first}
  action Consume = {
    nondet accepted = Set(true, false).oneOf()
    val admit = reference == generation and (accepted or Mutation == "intent")
    all {generation' = generation, reference' = reference,
      consumption' = if (admit) generation else consumption,
      intentOK' = if (admit) accepted else intentOK,
      finished' = finished, cost' = cost, first' = first}}
  action Call = { nondet tokens = Set(0,1,2).oneOf()
    all {generation' = generation, reference' = reference, consumption' = consumption,
      intentOK' = intentOK, finished' = finished, cost' = cost + tokens, first' = first}}
  action Verify = all {generation' = generation, reference' = reference,
    consumption' = consumption, intentOK' = intentOK, cost' = cost,
    finished' = (finished or consumption == generation or Mutation == "unconsumed"),
    first' = if (first < 0 and (consumption == generation or Mutation == "unconsumed")) cost else first}
  action Invalidate = all {generation < 2, generation' = generation + 1,
    reference' = -1, consumption' = if (Mutation == "stale") consumption else -1,
    intentOK' = false, finished' = false, cost' = 0, first' = -1}
  action step = any {Evidence, Consume, Call, Verify, Invalidate}
  val Safety = all {consumption < 0 or (consumption == generation and intentOK),
    not(finished) or consumption == generation, first < 0 or first <= cost}
}
