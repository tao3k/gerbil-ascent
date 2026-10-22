// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Stable OS observations and non-consuming bytes, not a kernel implementation proof.
module CheckpointTransport {
  import ExecutionPolicy.* from "./ExecutionPolicy"
  const Mutation: str
  type State = {probes: int, kind: int, before: int, after: int,
                result: int, expected: int, polls: int}
  var q: State
  action init = q' = {probes: 0, kind: 0, before: 0, after: 0,
    result: 0, expected: 0, polls: 0}
  action Probe = {nondet kind = Set(0,1,2,3,4,5).oneOf(); all {
    q.probes < 2,
    val decision = peer_probe(kind == 1 or kind == 5, kind == 0 or kind == 4, kind == 0)
    val expected = if (kind == 1 or kind == 3 or kind == 5) 1 else 0
    val bytes = if (kind == 2 or kind == 3) 2 else 0
    val actual = if (decision != -1) decision else if (kind == 4) -2 else expected
    q' = {probes: q.probes + 1, kind: kind, before: bytes,
      after: bytes - (if (Mutation == "consume-peek" and bytes > 0) 1 else 0),
      result: if (Mutation == "ignore-buffered-hangup" and kind == 3) 0
        else if (Mutation == "fault-open" and kind == 4) 0
        else if (Mutation == "benign-closed" and kind == 0) 1 else actual,
      expected: expected,
      polls: if ((decision == -1 and kind != 4) or (Mutation == "idle-poll" and kind == 0) or (Mutation == "eof-poll" and (kind == 1 or kind == 5))) 1 else 0}
  }}
  action step = any {Probe, all {q.probes == 2, q' = q}}
  val TypeOK = q.probes >= 0 and q.probes <= 2 and q.kind >= 0 and q.kind <= 5
    and q.after >= 0 and Set(0,1).contains(q.polls)
  val StablePeerDecision = q.probes == 0 or q.kind == 4 or q.result == q.expected
  val NoConsume = q.before == q.after
  val FaultClosed = q.probes == 0 or q.kind != 4 or q.result == -2
  val EofNoPoll = q.probes == 0 or not(Set(1,5).contains(q.kind)) or q.polls == 0
  val IdleNoPoll = q.probes == 0 or q.kind != 0 or q.polls == 0
}
