// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorStateLease {
  const Mutation: str
  type State = {phase: str, closed: bool, ticket: int, value: int,
    pendingWake: Set[int], observed: int, acceptedAfterClose: bool, reentered: bool,
    resetLaterReply: bool, endpoint: int, postedEndpoint: int}
  var q: State

  action init = q' = {phase: "spare", closed: false, ticket: 0, value: 0,
    pendingWake: Set(), observed: 0, acceptedAfterClose: false, reentered: false,
    resetLaterReply: false, endpoint: -1, postedEndpoint: -1}

  action send = {
    nondet endpoint = Set(0, 1).oneOf()
    all {
      q.phase == "spare", q.ticket < 3,
      not(q.closed) or Mutation == "admit-after-close",
      q' = {...q, phase: "queued", ticket: q.ticket + 1, acceptedAfterClose: q.closed,
        endpoint: endpoint}
    }
  }
  action post = all {
    q.phase == "queued",
    q' = {...q, phase: if (q.closed) "abandoned" else "ready",
      value: if (q.closed) 0 else q.ticket, pendingWake: q.pendingWake.union(Set(q.ticket)),
      postedEndpoint: if (Mutation == "use-other-endpoint") 1 - q.endpoint else q.endpoint}
  }
  action take = all {
    q.phase == "ready",
    q' = {...q, phase: "consumed", observed: q.value}
  }
  action reset = all {
    q.phase == "consumed" or Mutation == "return-without-read" and q.phase == "ready",
    q' = {...q, phase: "spare", value: if (Mutation == "keep-reply") q.value else 0}
  }
  action discard = all {
    q.phase == "queued" or q.phase == "ready",
    q' = {...q, phase: if (Mutation == "recycle-abandoned") "spare" else "abandoned"}
  }
  action wake = {
    nondet ticket = q.pendingWake.oneOf()
    q' = {...q, pendingWake: q.pendingWake.exclude(Set(ticket)),
      value: if (Mutation == "broadcast-writes" and ticket != q.ticket) ticket else q.value}
  }
  action close = all {not(q.closed), q' = {...q, closed: true}}
  pure def sameEntry(captured: int, available: int): bool = captured == available
  action reenter = all {
    q.phase == "spare", q.ticket > 0,
    sameEntry(q.ticket, if (Mutation == "reenter-retired") q.ticket else q.ticket + 1),
    q' = {...q, reentered: true}
  }
  action resumeReturn = all {
    q.phase == "ready", q.observed > 0, q.observed != q.value,
    q' = if (Mutation == "reset-later-reply")
      {...q, phase: "spare", value: 0, resetLaterReply: true}
      else q
  }
  action step = any {send, post, take, reset, discard, wake, close, reenter, resumeReturn}

  val NoClosedAdmission = not(q.acceptedAfterClose)
  val NoStalePayload = (q.phase != "spare" and q.phase != "queued") or q.value == 0
  val ExactReply = q.phase != "consumed" or q.observed == q.ticket
  val ReadBeforeReturn = q.phase != "spare" or q.observed == q.ticket
  val AtMostOneEntry = not(q.reentered)
  val ReleaseMatchesReply = not(q.resetLaterReply)
  val HandlerTargetsEndpoint = (q.phase != "ready" and q.phase != "consumed")
    or q.postedEndpoint == q.endpoint
}
