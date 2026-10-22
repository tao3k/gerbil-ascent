// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Scoped queue/deadline and advisory-fanout model; no host-memory/liveness claim.
module RequestScheduling {
  import ExecutionPolicy.* from "./ExecutionPolicy"
  const Mutation: str
  // BEGIN GENERATED FANOUT CAPACITY
  pure def fanout_capacity(workers: int, available: int): int =
    if (workers < available) workers else available
  // END GENERATED FANOUT CAPACITY
  // BEGIN GENERATED LIVE FANOUT
  pure def stage_fanout(eligible: bool, current: bool): bool = eligible and current
  pure def stage_probe(eligible: bool): int = if (eligible) 1 else 0
  // END GENERATED LIVE FANOUT
  type State = {clock: int, phase: str, canceled: bool, entered: bool,
                expiredAtEntry: bool, canceledAtEntry: bool,
                failed: bool, snapshot: int, pending: int, publishedOnOwner: bool}
  var q: State
  action init = q' = {clock: 0, phase: "queued", canceled: false, entered: false,
    expiredAtEntry: false, canceledAtEntry: false, failed: false, snapshot: 0, pending: 1, publishedOnOwner: false}
  action Tick = all {q.phase == "queued", q.clock < 3, q' = {...q, clock: q.clock + 1}}
  action Cancel = all {Set("queued", "evaluate", "ready").contains(q.phase),
    not(q.canceled), q' = {...q, canceled: true}}
  action Start = all {
    q.phase == "queued",
    val expired = q.clock >= 2
    val allowed = (not(q.canceled) or Mutation == "ignore-queued-cancel") and
      (not(expired) or Mutation == "reset-at-worker")
    q' = {...q, phase: if (allowed) "evaluate" else "failed", entered: allowed,
      expiredAtEntry: expired, canceledAtEntry: q.canceled, failed: not(allowed),
      pending: if (Mutation == "early-retire") 0 else q.pending}
  }
  action Evaluate(error: bool): bool = all {q.phase == "evaluate",
    q' = {...q, failed: error or q.canceled,
      phase: if (error or q.canceled) "failed" else "ready"}}
  action Publish = all {
    q.phase == "ready" or (Mutation == "publish-failed" and q.phase == "failed"),
    if (q.canceled) q' = {...q, phase: "failed", failed: true}
    else q' = {...q, phase: "published", snapshot: 1, publishedOnOwner: Mutation != "caller-publish"}
  }
  action Return = all {Set("failed", "published").contains(q.phase),
    q' = {...q, phase: "returned", pending: 0}}
  action step = {nondet error = Set(false,true).oneOf(); any {Tick, Cancel, Start, Evaluate(error), Publish, Return}}
  val TypeOK = q.clock >= 0 and q.clock <= 3 and q.pending >= 0 and q.pending <= 1 and
    Set("queued","evaluate","ready","failed","published","returned").contains(q.phase)
  val NoExpiredAdmission = not(q.entered) or not(q.expiredAtEntry)
  val NoCanceledAdmission = not(q.entered) or not(q.canceledAtEntry)
  val HeldFailure = not(q.failed) or q.snapshot == 0
  val OwnerPublication = q.snapshot == 0 or q.publishedOnOwner
  val PendingExact = q.pending == (if (q.phase == "returned") 0 else 1)
  pure val FanoutPolicy = Set(1,3,12).forall(workers => Set(1,2,3,12,13).forall(pending =>
    Set(false,true).forall(fanout_allowed => Set(false,true).forall(across => Set(false,true).forall(within => {
      val actual = if (Mutation == "short-fanout" and across) true
        else if (Mutation == "unbounded-fanout" and not(across)) fanout_allowed
        else request_fanout(workers,pending,fanout_allowed,across,within)
      actual == (fanout_allowed and not(across) and (within or pending < workers))
    })))))
  val FanoutExact = TypeOK and FanoutPolicy
  pure val StagePolicy = Set(1,3,12).forall(workers => Set(1,3,12,13).forall(before =>
    Set(1,3,12,13).forall(current => Set(false,true).forall(eligible =>
    Set(false,true).forall(fanout_allowed => Set(false,true).forall(across => Set(false,true).forall(within => {
      val policy = request_fanout(workers,
        if (Mutation == "stale-stage-fanout") before else current, fanout_allowed, across, within)
      val reads = if (Mutation == "eager-stage-probe") 1 else stage_probe(eligible)
      stage_fanout(eligible,policy) ==
        (eligible and fanout_allowed and not(across) and (within or current < workers)) and
        reads == (if (eligible) 1 else 0)
    })))))))
  val StageExact = TypeOK and StagePolicy
  pure val CapacityPolicy = Set(1,3,12).forall(workers => Set(1,3,12).forall(available => {
    val capacity = if (Mutation == "pool-size-as-capacity") workers else fanout_capacity(workers,available)
    capacity > 0 and capacity <= workers and capacity <= available and
      capacity == (if (workers < available) workers else available) and
      not(request_fanout(capacity,available,true,false,false))
  }))
  val CapacityExact = TypeOK and CapacityPolicy
}
