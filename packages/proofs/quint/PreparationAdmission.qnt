// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Admission protocol only: counters represent observations, not predicted time.
module PreparationAdmission {
  import PreparationPolicy.* from "./PreparationPolicy"
  const Mutation: str
  type State = {round: int, baseline: int, candidate: int,
    failed: bool, priorFailed: bool, everFailed: bool, matched: bool, complete: bool,
    accounted: bool, warmRebuilds: int, admitted: bool}
  var q: State
  action init = q' = {round: 0, baseline: 2, candidate: 0,
    failed: false, priorFailed: false, everFailed: false, matched: true, complete: false,
    accounted: true, warmRebuilds: 0, admitted: false}
  action Record = {
    nondet cost = Set(1,2,3).oneOf()
    all {q.round < 2,
      q' = {...q, round: q.round + 1, candidate: cost,
        complete: q.round == 1, admitted: false, priorFailed: q.failed,
        everFailed: q.everFailed or cost > q.baseline,
        failed: if (Mutation == "drop-history") cost > q.baseline
                else preparation_latch_failure(q.failed, cost > q.baseline)}}
  }
  action SourceChanged = q' = {...q, matched: false, admitted: false}
  action UnaccountedWork = q' = {...q, accounted: false, admitted: false}
  // A missing or changed producer makes a nominally warm command do real work.
  action MissingProducer = q' = {...q, warmRebuilds: 1, admitted: false}
  action Publish = q' = {...q, admitted:
    preparation_admitted(
      if (Mutation == "ignore-regression") 3 else q.baseline,
      q.candidate,
      if (Mutation == "ignore-warm") 0 else q.warmRebuilds,
      if (q.priorFailed) 1 else 0,
      q.matched or Mutation == "ignore-source",
      q.complete or Mutation == "accept-incomplete",
      q.accounted or Mutation == "ignore-work")}
  action step = any {Record, SourceChanged, UnaccountedWork, MissingProducer, Publish}
  val RetainedFailures = q.everFailed implies q.failed
  val NonRegression = q.admitted implies q.candidate <= q.baseline
  val CurrentSource = q.admitted implies q.matched
  val Complete = q.admitted implies q.complete
  val Accounted = q.admitted implies q.accounted
  val WarmCurrent = q.admitted implies q.warmRebuilds == 0
  val NoUnresolved = q.admitted implies not(q.everFailed)
}
