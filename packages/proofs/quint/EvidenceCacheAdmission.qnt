// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
module EvidenceCacheAdmission {
  const Mutation: str
  type Key = (int,int,int)
  type State = {current: Key, cached: Key, owner: bool,
    accepted: bool, acceptedKey: Key, failed: bool}
  var q: State
  pure val Keys = tuples(Set(0,1),Set(0,1),Set(0,1))
  action init = q' = {current: (0,0,0), cached: (0,0,0), owner: false,
    accepted: false, acceptedKey: (0,0,0), failed: false}
  // Key components: exact DSL content identity, loaded backend identity,
  // and caller fact-limit policy. Values abstract equality, never hash security.
  action Create = all {not(q.owner), q.current._2 == 0,
    q' = {...q, owner: true, cached: q.current, accepted: false, failed: false}}
  action Change = {nondet key = Keys.oneOf(); q' = {...q, current: key, accepted: false, failed: false}}
  action Reuse = all {q.owner,
    q.cached._1 == q.current._1 or Mutation == "source",
    q.cached._2 == q.current._2 or Mutation == "backend",
    q.cached._3 == q.current._3 or Mutation == "policy",
    q' = {...q, accepted: true, acceptedKey: q.current, failed: false}}
  // Exceptions or boundary identity drift revoke retained owners.
  action Reject = all {q.owner, q' = {...q, accepted: false, failed: true,
    owner: Mutation == "retain"}}
  action Release = q' = {...q, owner: false, accepted: false, failed: false}
  action step = any {Create, Change, Reuse, Reject, Release}
  val ExactSource = q.accepted implies q.cached._1 == q.acceptedKey._1
  val ExactBackend = q.accepted implies q.cached._2 == q.acceptedKey._2
  val ExactPolicy = q.accepted implies q.cached._3 == q.acceptedKey._3
  val FailureRevoked = q.failed implies not(q.owner or q.accepted)
  val LiveAdmission = q.accepted implies q.owner
}
