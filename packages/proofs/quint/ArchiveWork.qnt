// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Build-time protocol; compiler cache decisions remain owned by the pinned SDK.
module ArchiveWork {
  import ArchivePolicy.* from "./ArchivePolicy"
  const Mutation: str
  type State = {owner: int, overlap: bool, requests: int, profile: int, generation: int,
    snapshot: int, ready: bool, cachedGeneration: int, cachedProfile: int, worked: bool,
    starts: int, completed: int, pending: int, failed: int, invalid: int, sources: int,
    nativeWork: int, hits: int, duplicates: int, published: bool,
    privateCopy: int, savedCopy: int}
  var q: State
  action init = q' = {owner: -1, overlap: false, requests: 0, profile: 0, generation: 0,
    snapshot: 0, ready: false, cachedGeneration: -1, cachedProfile: -1, worked: false,
    starts: 0, completed: 0, pending: 0, failed: 0, invalid: 0, sources: 1,
    nativeWork: 0, hits: 0, duplicates: 0, published: false, privateCopy: -1, savedCopy: -1}
  action Acquire = all {q.owner == -1, q.requests < 3,
    q' = {...q, owner: q.profile, requests: q.requests + 1, snapshot: q.generation,
      worked: false, starts: 0, completed: 0, pending: 0, failed: 0, invalid: 0,
      nativeWork: 0, hits: 0, published: false}}
  action Contend = all {q.owner != -1, Mutation == "omit-lease",
    q' = {...q, overlap: true}}
  action Work = all {q.owner != -1, not(q.worked),
    val current = q.ready and q.cachedGeneration == q.snapshot
    val hit = current and (Mutation != "split-by-profile" or q.cachedProfile == q.profile)
    q' = {...q, worked: true,
      starts: if (hit and Mutation != "count-hit-as-work") 0 else 1,
      completed: if (hit and Mutation != "count-hit-as-work") 0 else 1,
      nativeWork: if (hit) 0 else 1, hits: if (hit) 1 else 0,
      duplicates: if (current and not(hit)) q.duplicates + 1 else q.duplicates}}
  action ForgetTerminal = all {q.owner != -1, q.worked, not(q.published), q.pending == 0, Mutation == "hide-pending",
    q' = {...q, pending: 1, starts: q.starts + 1, nativeWork: q.nativeWork + 1}}
  action Fail = all {q.owner != -1, q.worked, not(q.published), q.failed == 0,
    q' = {...q, failed: 1, starts: q.starts + 1, nativeWork: q.nativeWork + 1}}
  action UnknownEvent = all {q.owner != -1, q.worked, not(q.published),
    q' = {...q, invalid: 1}}
  action Publish = all {q.owner != -1, q.worked,
    val changed = if (q.snapshot == q.generation) 0 else 1
    archive_complete(
      q.starts - (if (Mutation == "hide-failure") q.failed else 0) - (if (Mutation == "hide-pending") q.pending else 0), q.completed,
      if (Mutation == "hide-pending") 0 else q.pending,
      if (Mutation == "hide-failure") 0 else q.failed,
      if (Mutation == "hide-unknown") 0 else q.invalid,
      if (Mutation == "ignore-source") 0 else changed,
      q.sources, true, true),
    q' = {...q, published: true, ready: true, cachedGeneration: q.snapshot, cachedProfile: q.profile,
      privateCopy: if (q.savedCopy == -1) q.snapshot else q.privateCopy,
      savedCopy: if (q.savedCopy == -1) q.snapshot else q.savedCopy}}
  action Release = all {q.owner != -1, q.worked,
    q' = {...q, owner: -1, profile: 1 - q.profile}}
  action ChangeInput = all {q.generation < 2,
    q' = {...q, generation: q.generation + 1, published: false,
      privateCopy: if (Mutation == "link-shared" and q.savedCopy != -1) q.generation + 1 else q.privateCopy}}
  action step = any {Acquire, Contend, Work, Fail, UnknownEvent, Publish, Release, ChangeInput, ForgetTerminal}
  val LeaseExclusive = not(q.overlap)
  val NativeCostExact = q.starts == q.nativeWork
  val ProfilesShareWork = q.duplicates == 0
  val SourceCurrent = q.published implies q.snapshot == q.generation
  val ReceiptComplete = q.published implies (q.pending == 0 and q.failed == 0 and q.invalid == 0)
  val PrivateOutputStable = q.privateCopy == q.savedCopy
}
