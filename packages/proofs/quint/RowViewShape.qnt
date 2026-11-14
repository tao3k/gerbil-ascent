// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Ownership stamps describe controlled field specifications. Payload membership
// is checked afresh by the existing ordinary receiver. POO invalidation is a
// separate upstream premise, also exercised by the compiled Scheme tests.
module RowViewShape {
  const Mutation: str
  type State = {phase: int, parentOwned: bool, parentRev: int, childRev: int,
    eligible: bool, stamp: bool, rows: List[int], expected: List[int],
    payloadValid: bool, payloadChanged: bool, edited: bool, checked: bool,
    admitted: bool, checks: int, callbacks: List[int]}
  var q: State
  action init = {
    nondet owned = Set(false,true).oneOf()
    nondet revision = Set(0,1).oneOf()
    nondet valid = Set(false,true).oneOf()
    q' = {phase: 0, parentOwned: owned, parentRev: revision, childRev: 0,
      eligible: false, stamp: false, rows: List(), expected: List(1,1,2),
      payloadValid: valid, payloadChanged: false, edited: false, checked: false,
      admitted: false, checks: 0, callbacks: List()}
  }
  action create = {
    val eligible = q.parentOwned and q.parentRev == 0
    val stamp = if (Mutation == "claim-arbitrary") true
      else if (Mutation == "claim-stale-parent") q.parentOwned
      else eligible and Mutation != "forget-owner"
    all {q.phase == 0, q' = {...q, phase: 1, eligible: eligible, stamp: stamp,
      rows: if (Mutation == "drop-rows") List(1,2) else q.expected,
      admitted: Mutation == "stamp-valid" and stamp,
      callbacks: if (Mutation == "eager-getter") List(9) else List()}}
  }
  action editParent = all {q.phase == 1, not(q.edited),
    q' = {...q, edited: true, checked: false, parentRev: q.parentRev+1,
      childRev: if (Mutation == "skip-parent-invalidation") q.childRev else q.childRev+1}}
  action editChild = all {q.phase == 1, not(q.edited),
    q' = {...q, edited: true, checked: false, childRev: q.childRev+1}}
  action mutatePayload = all {q.phase == 1, q.checks == 1, not(q.payloadChanged),
    q' = {...q, payloadChanged: true, payloadValid: false, checked: false}}
  action checkRoot = all {q.phase == 1, q.checks < 2,
    q' = {...q, checks: q.checks+1, checked: true,
      admitted: if (Mutation == "cache-validation" and q.checks > 0) q.admitted else q.payloadValid,
      callbacks: q.callbacks.concat(if (not(q.parentOwned) and Mutation != "skip-getter") List(1,2) else List())}}
  action step = any {create,editParent,editChild,mutatePayload,checkRoot}
  val ownedNow = q.stamp and (q.childRev == 0 or Mutation == "ignore-child-revision")
  val StampExact = q.phase == 0 or q.stamp == q.eligible
  val CurrentShape = ownedNow implies (q.parentOwned and q.parentRev == 0 and q.childRev == 0)
  val RowsPreserved = q.phase == 0 or q.rows == q.expected
  val NoEarlyGetter = q.checks > 0 or q.callbacks == List()
  val NoShapeAdmission = q.checks > 0 or not(q.admitted)
  val FreshAdmission = q.checked implies q.admitted == q.payloadValid
  val GetterOrder = q.parentOwned or q.callbacks == (if (q.checks == 0) List() else if (q.checks == 1) List(1,2) else List(1,2,1,2))
}
