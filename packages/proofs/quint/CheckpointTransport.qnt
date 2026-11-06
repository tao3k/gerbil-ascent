// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Stable OS observations and non-consuming bytes, not a kernel implementation proof.
module CheckpointTransport {
  import ExecutionPolicy.* from "./ExecutionPolicy"
  const Mutation: str
  // BEGIN GENERATED WAIT RESULT
  pure def wait_immediate(code: int): bool = Set(35,4,60).contains(code)
  pure def wait_pressure(code: int): bool = Set(14,12).contains(code)
  pure def wait_backoff(pressure: bool, changed: bool): bool = pressure and not(changed)
  // END GENERATED WAIT RESULT
  // BEGIN GENERATED CHECKPOINT COST
  pure def wake_hint(waiting: bool): int = if (waiting) 1 else 0
  pure def added_notification_atomics(publications: int, registrations: int): int = publications + 3 * registrations
  // END GENERATED CHECKPOINT COST
  type State = {probes: int, kind: int, before: int, after: int,
                result: int, expected: int, polls: int,
                waitChecks: int, waitCode: int, waitChanged: bool,
                waitResult: int, waitBackoff: bool, waitGrant: bool,
                noticePhase: int, waitRegistered: bool, waitFlag: bool,
                waitChecked: bool, phaseChanged: bool, waitBlocked: bool,
                noticeStored: bool, noticeRead: bool, noticeSent: bool}
  var q: State
  action init = q' = {probes: 0, kind: 0, before: 0, after: 0,
    result: 0, expected: 0, polls: 0, waitChecks: 0, waitCode: 0, waitChanged: false,
    waitResult: 0, waitBackoff: false, waitGrant: false,
    noticePhase: 0, waitRegistered: false, waitFlag: false, waitChecked: false,
    phaseChanged: false, waitBlocked: false, noticeStored: false, noticeRead: false, noticeSent: false}
  action Probe = {nondet kind = Set(0,1,2,3,4,5).oneOf(); all {
    q.probes < 2,
    val decision = peer_probe(kind == 1 or kind == 5, kind == 0 or kind == 4, kind == 0)
    val expected = if (kind == 1 or kind == 3 or kind == 5) 1 else 0
    val bytes = if (kind == 2 or kind == 3) 2 else 0
    val actual = if (decision != -1) decision else if (kind == 4) -2 else expected
    q' = {...q, probes: q.probes + 1, kind: kind, before: bytes,
      after: bytes - (if (Mutation == "consume-peek" and bytes > 0) 1 else 0),
      result: if (Mutation == "ignore-buffered-hangup" and kind == 3) 0
        else if (Mutation == "fault-open" and kind == 4) 0
        else if (Mutation == "benign-closed" and kind == 0) 1 else actual,
      expected: expected,
      polls: if ((decision == -1 and kind != 4) or (Mutation == "idle-poll" and kind == 0) or (Mutation == "eof-poll" and (kind == 1 or kind == 5))) 1 else 0}
  }}
  action WaitAttempt = {
    nondet code = Set(35,4,60,14,12,22,5,-1).oneOf()
    nondet changed = Set(false,true).oneOf()
    all {q.waitChecks < 2,
      val pressure = wait_pressure(code)
      val expected = if (wait_immediate(code)) 0 else if (pressure) 1 else 2
      val outcome = if (Mutation == "memory-fatal" and pressure) 2
        else if (Mutation == "invalid-retry" and expected == 2) 0 else expected
      q' = {...q, waitChecks: q.waitChecks + 1, waitCode: code, waitChanged: changed,
        waitResult: outcome,
        waitBackoff: if (Mutation == "changed-sleep" and pressure) true else wait_backoff(pressure,changed),
        waitGrant: Mutation == "retry-grant" and outcome != 2}
    }
  }
  // Atomic actions follow actual SeqCst source order. KernelBlock performs
  // the host's final atomic comparison; it cannot block on a changed phase.
  action RegisterWaiter = all {not(q.waitRegistered),
    q' = {...q, waitRegistered: true, waitFlag: Mutation != "register-missing"}}
  action RecheckPhase = all {q.waitRegistered, not(q.waitChecked),
    q' = {...q, waitChecked: true, phaseChanged: q.noticePhase != 0}}
  action KernelBlock = all {q.waitChecked, not(q.phaseChanged), not(q.waitBlocked), q.noticePhase == 0,
    q' = {...q, waitBlocked: true,
      waitFlag: if (Mutation == "registration-cleared") false else q.waitFlag}}
  action StorePhase = all {not(q.noticeStored),
    q' = {...q, noticeStored: true, noticePhase: 1}}
  action InspectWaiter = all {not(q.noticeRead), q.noticeStored or Mutation == "wake-before-phase",
    q' = {...q, noticeRead: true, noticeSent: q.waitFlag}}
  action step = any {Probe, WaitAttempt, RegisterWaiter, RecheckPhase, KernelBlock, StorePhase, InspectWaiter,
    all {q.probes == 2 and q.waitChecks == 2, q' = q}}
  val TypeOK = q.probes >= 0 and q.probes <= 2 and q.kind >= 0 and q.kind <= 5
    and q.after >= 0 and Set(0,1).contains(q.polls)
  val StablePeerDecision = q.probes == 0 or q.kind == 4 or q.result == q.expected
  val NoConsume = q.before == q.after
  val FaultClosed = q.probes == 0 or q.kind != 4 or q.result == -2
  val EofNoPoll = q.probes == 0 or not(Set(1,5).contains(q.kind)) or q.polls == 0
  val IdleNoPoll = q.probes == 0 or q.kind != 0 or q.polls == 0
  val WaitTypeOK = q.waitChecks >= 0 and q.waitChecks <= 2 and Set(0,1,2).contains(q.waitResult)
  val TransientRechecks = q.waitChecks == 0 or not(wait_pressure(q.waitCode)) or q.waitResult == 1
  val FatalStaysFatal = q.waitChecks == 0 or wait_pressure(q.waitCode) or wait_immediate(q.waitCode) or q.waitResult == 2
  val ChangedNeverBackoff = not(q.waitChanged) or not(q.waitBackoff)
  val RetryNoDecision = not(q.waitGrant)
  val NoLostRegisteredWake = not(q.noticeRead and q.waitBlocked and q.noticePhase == 1) or q.noticeSent
  val NoticeTypeOK = Set(0,1).contains(q.noticePhase)
  val NoExtraWake = (if (Mutation == "double-wake" and q.noticeSent) 2 else wake_hint(q.noticeSent)) <= 1
}
