// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Microsteps of the generated cache-extension macro, including alias mutation
// before failure. Error identity is data; no failure may publish a version.
module CachePublication {
  const Mutation: str
  type State = {stage: int, version: int, lookup: int, witness: int,
    error: int, original: int, wroteLookup: bool, wroteWitness: bool,
    triedEmpty: bool, usedEmpty: bool, observedPresent: bool,
    deltaPhase: int, deltaVersion: int, deltaPresent: bool,
    triedDelta: bool, usedDelta: bool, observedDelta: bool, observedDeltaVersion: int}
  var q: State
  action init = q' = {stage: 0, version: 0, lookup: 0, witness: 0,
    error: 0, original: 0, wroteLookup: false, wroteWitness: false,
    triedEmpty: false, usedEmpty: false, observedPresent: false,
    deltaPhase: 0, deltaVersion: 0, deltaPresent: false,
    triedDelta: false, usedDelta: false, observedDelta: false, observedDeltaVersion: 0}
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
    // Distinct scope includes another lane and another column layout.
    nondet scope = Set(0,1,2).oneOf()
    nondet key = Set(0,1).oneOf()
    val accepted = q.version >= 0 and
      (scope == 0 or Mutation == "empty-owner") and
      (q.version == 0 or Mutation == "empty-version") and
      (key == 1 or Mutation == "empty-key")
    val present = scope != 0 or key == 0 or q.lookup == 1
    all {(q.stage == 0 or q.stage == 5), not(q.triedEmpty),
      q' = {...q, triedEmpty: true, usedEmpty: accepted, observedPresent: present}}
  }
  // Delta revision is independent of source publication. Restoration is an ABA
  // of rows, not an ABA of the generation. Observations retain their use epoch.
  action replaceDelta = all {q.deltaPhase == 0,
    q' = {...q, deltaPhase: 1, deltaVersion: 1, deltaPresent: true}}
  action restoreDelta = all {q.deltaPhase == 1,
    q' = {...q, deltaPhase: 2, deltaVersion: 2, deltaPresent: false}}
  action tryDelta = {
    val accepted = q.deltaVersion == 0 or Mutation == "empty-version"
    all {not(q.triedDelta),
      q' = {...q, triedDelta: true, usedDelta: accepted,
        observedDelta: q.deltaPresent, observedDeltaVersion: q.deltaVersion}}
  }
  action step = any {revoke, mutate, failProvider, install, witness, failWitness, publish,
    tryEmpty, replaceDelta, restoreDelta, tryDelta}
  val RevokedAliases = q.stage >= 1 and q.stage < 5 implies q.version == -1
  val FailureRevoked = q.error != 0 implies q.version == -1
  val ErrorIdentity = q.error == q.original
  val CompletePublication = q.version == 1 implies
    (q.error == 0 and q.wroteLookup and q.wroteWitness and q.lookup == 1 and q.witness == 1)
  val SourceEmptySound = q.usedEmpty implies not(q.observedPresent)
  val DeltaEmptySound = q.usedDelta implies not(q.observedDelta)
  val DeltaCertificateCurrent = q.usedDelta implies q.observedDeltaVersion == 0
  // Include delta scope in the existing version mutation's admission boundary.
  val EmptyHitSound = SourceEmptySound and DeltaEmptySound and DeltaCertificateCurrent
  val Safety = RevokedAliases and FailureRevoked and ErrorIdentity and CompletePublication and EmptyHitSound
}
