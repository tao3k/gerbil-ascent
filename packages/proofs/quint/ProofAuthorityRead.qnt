// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// The two production RPCs read the same source-state-generation field. Native
// Scheme/C ABI evaluation and positive replay retain their separate obligations.
module ProofAuthorityRead {
  const Mutation: str
  type State = {checked: bool, alive: bool, generation: bool, fingerprinted: bool,
    eligible: bool, matched: bool, canceled: bool, expired: bool, replayed: bool,
    authority: bool, verified: bool, projections: int}
  var q: State
  action init = {
    nondet alive = Set(false,true).oneOf()
    nondet generation = Set(false,true).oneOf()
    nondet fingerprinted = Set(false,true).oneOf()
    nondet eligible = Set(false,true).oneOf()
    nondet matched = Set(false,true).oneOf()
    nondet canceled = Set(false,true).oneOf()
    nondet expired = Set(false,true).oneOf()
    nondet replayed = Set(false,true).oneOf()
    q' = {checked: false, alive: alive, generation: generation, fingerprinted: fingerprinted,
      eligible: eligible, matched: matched, canceled: canceled, expired: expired, replayed: replayed,
      authority: false, verified: false, projections: 0}
  }
  action step = {
    val authority = (q.alive or Mutation == "allow-closed") and
      (q.generation or Mutation == "skip-generation") and
      (not(q.canceled) or Mutation == "skip-cancel") and
      (not(q.expired) or Mutation == "reset-deadline") and
      (not(q.fingerprinted) or q.matched or Mutation == "skip-fingerprint" or
        (not(q.eligible) and Mutation == "skip-foreign-fingerprint"))
    val projection = (q.fingerprinted and (q.eligible or Mutation != "skip-foreign-fingerprint")) or Mutation == "project-without-fingerprint"
    all {not(q.checked), q' = {...q, checked: true, authority: authority,
      verified: authority and (q.eligible or Mutation == "verify-foreign") and ((q.fingerprinted and q.replayed) or
        (not(q.fingerprinted) and Mutation == "verify-unsupported")),
      projections: if (not(q.alive) or q.canceled or q.expired or not(projection)) 0
        else if (authority and q.eligible) 2 else 1}}
  }
  val OwnerRequired = q.authority implies q.alive
  val GenerationRequired = q.authority implies q.generation
  val CancelRequired = q.authority implies not(q.canceled)
  val DeadlineRequired = q.authority implies not(q.expired)
  val FingerprintRequired = (q.authority and q.fingerprinted) implies q.matched
  val RefusalNeverVerified = q.verified implies (q.authority and q.eligible and q.fingerprinted and q.replayed)
  val NoUnusedProjection = (q.checked and not(q.fingerprinted)) implies q.projections == 0
  val ForeignStillProjects = (q.checked and q.alive and not(q.canceled) and not(q.expired) and
    q.fingerprinted and not(q.eligible)) implies q.projections == 1
}
