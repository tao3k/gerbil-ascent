// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// One child writer, original caller publication, and fenced notification lifetime.
module OwnerAdmission {
  const Mutation: str
  type State = {generation: int, canceled: bool, mirrored: bool, expired: bool,
                requested: bool, accepted: bool, badPublication: bool,
                oldNotification: int, badNotification: bool, work: int, refused: bool, metadataReady: bool, ownerReady: bool, metadataScopeDelta: int}
  var q: State
  action init = q' = {generation: 1, canceled: false, mirrored: false, expired: false,
    requested: false, accepted: false, badPublication: false,
    oldNotification: 0, badNotification: false, work: 0, refused: false, metadataReady: false, ownerReady: false, metadataScopeDelta: 0}
  action InitializeMetadata = all {not(q.metadataReady),
    q' = {...q, metadataReady: true,
      metadataScopeDelta: if (Mutation == "metadata-spends-scope") 1 else q.metadataScopeDelta}}
  action Ready = all {not(q.ownerReady),
    q.metadataReady or Mutation == "ready-before-metadata",
    q' = {...q, ownerReady: true}}
  action Cancel = all {not(q.canceled), q' = {...q, canceled: true}}
  action Expire = all {not(q.expired), q' = {...q, expired: true}}
  action Deliver = all {q.canceled, not(q.mirrored), q' = {...q, mirrored: true}}
  action Charge = all {q.ownerReady, not(q.accepted), not(q.canceled), not(q.expired), not(q.requested),
    q.work < 3,
    q' = {...q, work: if (q.work < 2 or Mutation == "ignore-budget") q.work + 1 else q.work,
      refused: q.work == 2}}
  action Request = all {q.ownerReady, not(q.requested), not(q.accepted),
    q' = {...q, requested: true,
      accepted: Mutation == "child-publishes",
      badPublication: Mutation == "child-publishes"}}
  action Publish = all {q.requested, not(q.accepted),
    val cancel = if (Mutation == "mirror-authority") q.mirrored else q.canceled
    val expired = if (Mutation == "ignore-deadline") false else q.expired
    val grant = not(cancel) and not(expired)
    q' = {...q, accepted: grant,
      badPublication: grant and (q.canceled or q.expired)}}
  // Retirement serializes against notifications before the next generation.
  action Retire = all {q.generation == 1,
    q' = {...q, generation: 2, oldNotification: 1, canceled: false,
      mirrored: false, expired: false, requested: false, accepted: false,
      work: 0, refused: false}}
  action LateNotification = all {q.oldNotification == 1, q.generation == 2,
    val targets = q.oldNotification == q.generation or Mutation == "unfenced-notice"
    q' = {...q, oldNotification: 0, mirrored: if (targets) true else q.mirrored,
      badNotification: targets}}
  action step = any {InitializeMetadata, Ready, Cancel, Expire, Deliver, Charge, Request, Publish, Retire, LateNotification,
    q' = q}
  val OwnerReady = not(q.ownerReady) or q.metadataReady
  val LibraryScopes = q.metadataScopeDelta == 0
  val CallerOnly = not(q.badPublication)
  val LeaseFence = not(q.badNotification)
  val BudgetExact = q.work >= 0 and q.work <= 2
  // Finite policy controls are independent of the unbounded Lean cost identities.
  pure val SnapshotCurrentPolicy = Set(false,true).forall(sameProcess => Set(false,true).forall(current => {
    val admitted = sameProcess and (current or Mutation == "skip-snapshot-reverify")
    admitted == (sameProcess and current)
  }))
  pure val ResourceLifetimePolicy = Set(false,true).forall(host => Set(false,true).forall(native => {
    val removed = not(native) and (not(host) or Mutation == "drop-resource-with-host")
    removed == (not(host) and not(native))
  }))
  pure val ForkLifetimePolicy = Set(false,true).forall(host => Set(false,true).forall(native => {
    val removed = Mutation == "fork-drops-parent" and not(host) and not(native)
    not(removed)
  }))
  pure val CapturedCopyCostPolicy = Set(1,2,3,12,20).forall(pools => Set(1,2,7).forall(files => {
    val copies = if (Mutation == "repeat-package-copy") pools * files else files
    copies == files
  }))
  val SnapshotCurrent = q.generation == 0 or SnapshotCurrentPolicy
  val ResourceLifetime = q.generation == 0 or ResourceLifetimePolicy
  val ForkLifetime = q.generation == 0 or ForkLifetimePolicy
  val CapturedCopyCost = q.generation == 0 or CapturedCopyCostPolicy
}
