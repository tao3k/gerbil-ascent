// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Microsteps of the generated cache-extension macro, including alias mutation
// before failure. Error identity is data; no failure may publish a version.
module CachePublication {
  const Mutation: str
  type State = {stage: int, version: int, lookup: int, witness: int,
    error: int, original: int, wroteLookup: bool, wroteWitness: bool,
    triedEmpty: bool, usedEmpty: bool, observedPresent: bool}
  var q: State
  action init = q' = {stage: 0, version: 0, lookup: 0, witness: 0,
    error: 0, original: 0, wroteLookup: false, wroteWitness: false,
    triedEmpty: false, usedEmpty: false, observedPresent: false}
  action revoke = all {q.stage == 0,
    q' = {...q, stage: 1, version: if (Mutation == "late-revoke") 0 else -1}}
  action mutate = all {q.stage == 1,
    q' = {...q, stage: 2, lookup: 1}}
  action failProvider = all {q.stage == 1,
    q' = {...q, stage: 5, lookup: 1, original: 7,
      error: if (Mutation == "mask-error") 8 else 7}}
  action install = all {q.stage == 2,
    q' = {...q, stage: 3, wroteLookup: true,
      version: if (Mutation == "early-publish") 1 else q.version}}
  action witness = all {q.stage == 3,
    q' = {...q, stage: 4, witness: 1, wroteWitness: true}}
  action failWitness = all {q.stage == 3,
    q' = {...q, stage: 5, witness: 1, original: 9,
      error: if (Mutation == "mask-witness") 7 else 9}}
  action publish = all {q.stage == 4 or (Mutation == "skip-witness" and q.stage == 3),
    q' = {...q, stage: 5, version: 1}}
  // Saved certificate: scope 0, version 0, key 1 was empty. Scope 1 denotes
  // another lane/entry whose same-version bucket is nonempty. Lookup mutation
  // makes key 1 present in scope 0; a failed publication never enables reuse.
  action tryEmpty = {
    nondet scope = Set(0,1).oneOf()
    nondet key = Set(0,1).oneOf()
    val accepted = q.version >= 0 and
      (scope == 0 or Mutation == "empty-owner") and
      (q.version == 0 or Mutation == "empty-version") and
      (key == 1 or Mutation == "empty-key")
    val present = scope == 1 or key == 0 or q.lookup == 1
    all {(q.stage == 0 or q.stage == 5), not(q.triedEmpty),
      q' = {...q, triedEmpty: true, usedEmpty: accepted, observedPresent: present}}
  }
  action step = any {revoke, mutate, failProvider, install, witness, failWitness, publish, tryEmpty}
  val RevokedAliases = q.stage >= 1 and q.stage < 5 implies q.version == -1
  val FailureRevoked = q.error != 0 implies q.version == -1
  val ErrorIdentity = q.error == q.original
  val CompletePublication = q.version == 1 implies
    (q.error == 0 and q.wroteLookup and q.wroteWitness and q.lookup == 1 and q.witness == 1)
  val EmptyHitSound = q.usedEmpty implies not(q.observedPresent)
  val Safety = RevokedAliases and FailureRevoked and ErrorIdentity and CompletePublication and EmptyHitSound
}
