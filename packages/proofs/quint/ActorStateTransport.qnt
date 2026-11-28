// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module ActorStateTransport {
  const Mutation: str
  type State = {phase: int, authority: bool, compact: bool, closed: bool,
    rejected: bool, replyAuthority: bool, generation: int, replyGeneration: int,
    expectedGeneration: int, expectedRejection: bool, endpoint: int, replyEndpoint: int}
  var q: State

  action init = {
    nondet authority = Set(false, true).oneOf()
    nondet endpoint = Set(1, 2).oneOf()
    q' = {phase: 0, authority: authority, compact: false, closed: false,
      rejected: false, replyAuthority: false, generation: 0, replyGeneration: 0,
      expectedGeneration: 0, expectedRejection: false, endpoint: endpoint, replyEndpoint: 0}
  }
  action Send = all {q.phase == 0, not(q.closed),
    q' = {...q, phase: 1, compact: not(q.authority) or Mutation == "drop-authority"}}
  action Update = all {not(q.closed), q.generation < 2,
    q' = {...q, generation: q.generation + 1}}
  action Close = all {not(q.closed),
    q' = {...q, closed: true}}
  action Dispatch = all {q.phase == 1,
    q' = {...q, phase: 2, expectedRejection: q.closed, expectedGeneration: q.generation,
      rejected: q.closed and not(q.compact and Mutation == "skip-close"),
      replyAuthority: not(q.compact) and q.authority,
      replyGeneration: if (q.compact and Mutation == "stale-state") 0 else q.generation,
      replyEndpoint: if (Mutation == "foreign-reply") 3 - q.endpoint else q.endpoint}}
  action Take = all {q.phase == 2, q' = {...q, phase: 3}}
  action step = any {Send, Update, Close, Dispatch, Take}
  val AuthorityExact = q.phase < 2 or q.replyAuthority == q.authority
  val CloseExact = q.phase < 2 or q.rejected == q.expectedRejection
  val StateExact = q.phase < 2 or q.rejected or q.replyGeneration == q.expectedGeneration
  val ReplyExact = q.phase < 2 or q.replyEndpoint == q.endpoint
}
