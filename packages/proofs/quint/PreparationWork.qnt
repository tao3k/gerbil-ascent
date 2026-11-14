// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Observer protocol. This does not model the SDK compiler or allocator.
module PreparationWork {
  import PreparationPolicy.* from "./PreparationPolicy"
  import PreparationInterfaces.* from "./PreparationInterfaces"
  import PreparationSupport.* from "./PreparationSupport"
  const Mutation: str
  type State = {jobs: int, observedJobs: int, imports: int, observedImports: int,
                failedJobs: int, changedInputs: int, finished: bool, current: bool, counterValid: bool, published: bool,
                outerAllocation: int, reportedAllocation: int, rawStart: int, rawFinish: int, inventoryDeclarations: int,
                gscCpu: int, helperCpu: int, residualCpu: int, cumulativeClaim: bool, heapCap: int, heapSections: int, sourceStamp: int, sourceRestored: bool,
                unrequestedJobs: int, compiledSourceCarriers: int,
                inputGeneration: int, commitGeneration: int, manifestGeneration: int, requestKeyGeneration: int, cacheGeneration: int, cacheReady: bool, staleReuse: bool, payloadPresent: bool, receiptPresent: bool, incompleteReuse: bool,
                sourceVmActive: bool, sourceStarts: int, retainedEntryRoots: int, forcedCatalogRoots: int, productionAdmitted: bool, rootsProjected: bool}
  var q: State
  action init = q' = {jobs: 0, observedJobs: 0, imports: 0, observedImports: 0,
    failedJobs: 0, changedInputs: 0, finished: false, current: true, counterValid: true, published: false,
    outerAllocation: 0, reportedAllocation: 0, rawStart: 0, rawFinish: 0, inventoryDeclarations: 0,
    gscCpu: 0, helperCpu: 0, residualCpu: 0, cumulativeClaim: false, heapCap: 3, heapSections: 0, sourceStamp: 0, sourceRestored: false,
    unrequestedJobs: 0, compiledSourceCarriers: 0,
    inputGeneration: 0, commitGeneration: 0, manifestGeneration: 0, requestKeyGeneration: 0, cacheGeneration: 0, cacheReady: false, staleReuse: false, payloadPresent: false, receiptPresent: false, incompleteReuse: false,
    sourceVmActive: false, sourceStarts: 0, retainedEntryRoots: 0, forcedCatalogRoots: 0, productionAdmitted: true, rootsProjected: false}
  // A stateless selector has no protocol transition. Check its complete input
  // domain once; adding eight no-op choices at every state only repeats work.
  pure def selected_interface(admitted: bool, reload: bool, compiling: bool, producer: bool, present: bool): bool = {
    val expected = interface_selected(admitted, reload, compiling, producer, present)
    if ((Mutation == "reuse-unadmitted-interface" and not(admitted)) or
        (Mutation == "reuse-reloaded-interface" and reload) or
        (Mutation == "reuse-compiling-interface" and compiling) or
        (Mutation == "reuse-consumer-interface" and not(producer)) or
        (Mutation == "reuse-missing-interface" and not(present))) true
    else if (Mutation == "expand-admitted-interface" and expected) false else expected
  }
  pure def selection_conforms(admitted: bool): bool =
    Set(false, true).forall(reload => Set(false, true).forall(compiling => Set(false, true).forall(producer =>
      Set(false, true).forall(present => selected_interface(admitted, reload, compiling, producer, present) ==
        interface_selected(admitted, reload, compiling, producer, present)))))
  // 0: filename, 1: qualified symbol, 2: SDK syntax-wrapped origin,
  // 3: unsupported form. No new state transitions or stuttering choices.
  pure def request_selection_conforms(admitted: bool): bool =
    Set(0, 1, 2, 3).forall(request =>
      Set(false, true).forall(reload => Set(false, true).forall(compiling =>
        Set(false, true).forall(producer => Set(false, true).forall(present => {
          val expected = request_interface_selected(request, admitted, reload, compiling, producer, present)
          val actual = if (Mutation == "drop-qualified-interface" and request == 1) false
            else if (Mutation == "drop-syntax-interface" and request == 2) false
            else if (Mutation == "reuse-unknown-interface" and request == 3) true else expected
          actual == expected
        })))))
  pure val AdmittedSelectionExact = selection_conforms(true) and request_selection_conforms(true)
  pure val UnadmittedSelectionExact = selection_conforms(false) and request_selection_conforms(false)
  val InterfaceSelectionExact = if (q.productionAdmitted) AdmittedSelectionExact else UnadmittedSelectionExact
  // Finite protocol controls supplement the unbounded Lean HashMap theorem.
  pure val IndexedAliasesExact = Set(0, 1).forall(k0 => Set(0, 1).forall(k1 =>
    Set(0, 1).forall(v0 => Set(0, 1).forall(v1 => Set(0, 1, 2).forall(key => {
      val expected = first_alias(k0, v0, k1, v1, key)
      val actual = if (Mutation == "last-interface-alias-wins")
        first_alias(k1, v1, k0, v0, key) else expected
      actual == expected
    })))))
  // Check after native projection is requested, so a mutant has a concrete
  // state-transition counterexample rather than a constant-FALSE TLC config.
  val IndexedDispatchExact = not(q.rootsProjected) or IndexedAliasesExact
  // Same finite entries and multiplicity; source-bound Lean retains arbitrary weights.
  // Eight ordinary batches and capacity two distinguish first-wave from tail overlap.
  pure def source_queue(defer: bool): List[int] = if (Mutation == "drop-isolated-source")
    List(0, 1, 2, 3, 4, 5, 6, 7)
    else if (defer) List(0, 1, 2, 3, 4, 5).concat(List(8, 9)).concat(List(6, 7))
    else List(8, 9).concat(List(0, 1, 2, 3, 4, 5, 6, 7))
  pure val SourceQueueExact = source_queue(true) == List(0, 1, 2, 3, 4, 5, 8, 9, 6, 7) and
    source_queue(false) == List(8, 9, 0, 1, 2, 3, 4, 5, 6, 7)
  val SourceQueueCoverage = q.sourceStarts == 0 or SourceQueueExact
  pure def source_live_ratio(darwin: bool, isolated: bool): int =
    if (Mutation == "compact-isolated-source" and isolated) 80
    else if (Mutation == "ignore-ordinary-gc") 50
    else if (darwin and not(isolated)) 80 else 50
  pure val SourceGcExact = source_live_ratio(true, false) == 80 and
    source_live_ratio(true, true) == 50 and source_live_ratio(false, false) == 50 and
    source_live_ratio(false, true) == 50
  val SourceGcIsolation = q.sourceStarts == 0 or SourceGcExact
  action ReadInventory = q' = {...q,
    inventoryDeclarations: if (Mutation == "bootstrap-inventory") 1 else 0}
  action UnadmitProduction = q' = {...q, productionAdmitted: false, rootsProjected: false}
  action ProjectRoots = q' = {...q, rootsProjected: true,
    forcedCatalogRoots: if (q.productionAdmitted) {
      if (Mutation == "expand-producer-catalog") 1 else 0
    } else { if (Mutation == "prune-unadmitted-catalog") 0 else 1 }}
  action Import = all {q.imports < 2,
    q' = {...q, imports: q.imports + 1,
      observedImports: if (Mutation == "forget-import") q.observedImports else q.observedImports + 1,
      published: false}}
  action Gsc = all {q.jobs < 2,
    q' = {...q, jobs: q.jobs + 1,
      observedJobs: if (Mutation == "hide-job") q.observedJobs else q.observedJobs + 1,
      published: false}}
  // Compilation is demanded by the native import graph, not directory size.
  val SelectedSupport = support_roots(Mutation != "eager-catalog", List("unrelated-driver"),
    if (Mutation == "drop-demanded-support") List() else List("requested"),
    if (Mutation == "drop-cached-support") List() else List("cached"))
  action UnrequestedGsc = all {SelectedSupport.foldl(false, (found, root) => found or root == "unrelated-driver"),
    q' = {...q, unrequestedJobs: q.unrequestedJobs + 1, published: false}}
  action CompileSourceSuite = all {any {Mutation == "compile-source-suite", Mutation == "compile-source-consumer"},
    q' = {...q, compiledSourceCarriers: q.compiledSourceCarriers + 1, published: false}}
  action CacheOutput = all {q.finished,
    q' = {...q, cacheReady: true, payloadPresent: true, receiptPresent: true, cacheGeneration: q.inputGeneration,
      sourceStamp: 0, sourceRestored: false}}
  // A compiled snapshot has source stamp 0 and product stamp 1. Fresh Git
  // checkout changes only the source stamp, not the indexed content identity.
  action FreshCheckout = all {q.cacheReady,
    q' = {...q, sourceStamp: 2, sourceRestored: false}}
  action RestoreSource = all {q.cacheReady,
    q.cacheGeneration == q.inputGeneration or Mutation == "restore-stale-source",
    q' = {...q, sourceRestored: true,
      sourceStamp: if (Mutation == "restore-outputs-only") 2 else 0}}
  action ChangeInput = all {q.inputGeneration < 2,
    q' = {...q, inputGeneration: q.inputGeneration + 1, requestKeyGeneration: q.inputGeneration + 1,
      sourceRestored: false, current: false, published: false}}
  action ChangeCommit = all {q.commitGeneration < 2,
    q' = {...q, commitGeneration: q.commitGeneration + 1,
      requestKeyGeneration: if (Mutation == "key-by-commit") q.requestKeyGeneration + 1 else q.requestKeyGeneration}}
  action ChangeManifest = all {q.manifestGeneration < 2,
    q' = {...q, manifestGeneration: q.manifestGeneration + 1,
      requestKeyGeneration: if (Mutation == "key-by-generated-manifest") q.requestKeyGeneration + 1 else q.requestKeyGeneration}}
  action DropPayload = q' = {...q, payloadPresent: false}
  action DropReceipt = q' = {...q, receiptPresent: false}
  action Reuse = all {q.cacheReady,
    q.payloadPresent or Mutation == "reuse-missing-payload",
    q.receiptPresent or Mutation == "reuse-missing-receipt",
    q.cacheGeneration == q.inputGeneration or Mutation == "reuse-stale-input",
    q' = {...q, staleReuse: q.staleReuse or q.cacheGeneration != q.inputGeneration,
      incompleteReuse: q.incompleteReuse or not(q.payloadPresent and q.receiptPresent)}}
  // Current complete inventory: 174 roots, 12 VM workers, unchanged two-entry cap.
  // Generic width/refinement is proved in Lean; this finite instance is not a byte-allocation proof.
  pure val SourceBatchLimit = batch_width(batch_width(174, 12), 12)
  // Suite completion does not evict Gerbil's retained module contexts; VM exit does.
  action StartSourceVm = all {not(q.sourceVmActive), q.sourceStarts < 2,
    q' = {...q, sourceVmActive: true, sourceStarts: q.sourceStarts + 1,
      retainedEntryRoots: SourceBatchLimit + (if (Mutation == "batch-source-roots") 1 else 0)}}
  action ExitSourceVm = all {q.sourceVmActive,
    q' = {...q, sourceVmActive: false,
      retainedEntryRoots: if (Mutation == "retain-source-roots") q.retainedEntryRoots else 0}}
  action Allocate = q' = {...q, outerAllocation: 4,
    reportedAllocation: if (Mutation == "sum-nested") 6 else 4, published: false}
  // GSC child usage already includes native compiler/helper descendants.
  // Keep a partition instead of adding a second inclusive measurement.
  // A positive occupancy-based SDK interval still lacks cumulative event telemetry.
  // SDK live-ratio changes its target. The existing maximum stays separate.
  action ResizeHeap = q' = {...q,
    heapCap: if (Mutation == "raise-heap-for-gc") 4 else 3,
    heapSections: if (Mutation == "skip-heap-cap") 4 else 3}
  action ObserveOccupancy = q' = {...q,
    cumulativeClaim: Mutation == "occupancy-as-cumulative"}
  action ObserveCompilerCpu = q' = {...q, gscCpu: 4, helperCpu: 3,
    residualCpu: if (Mutation == "sum-helper-cpu") 4 else 1}
  action Finish = all {q.jobs == 2, q.imports == 2, q' = {...q, finished: true}}
  action ChangeSource = q' = {...q, current: false, published: false}
  // Current SDK counters can fall when a GC releases earlier still objects.
  // Preserve the signed observation; never coerce it to an allocation saving.
  action CounterDecrease = q' = {...q, rawStart: 8, rawFinish: 0,
    counterValid: false, published: false}
  action CounterNegative = q' = {...q, rawStart: -8, rawFinish: -4,
    counterValid: false, published: false}
  action CompilerFails = q' = {...q, failedJobs: 1, published: false}
  action CompilerInputChanges = q' = {...q, changedInputs: 1, published: false}
  action Publish = all {
    preparation_observation_complete(
      if (Mutation == "hide-compiler-failure") 0 else q.failedJobs,
      if (Mutation == "hide-changed-input") 0 else q.changedInputs,
      0, true),
    q.finished or Mutation == "publish-partial",
    q.current or Mutation == "ignore-generation",
    q.counterValid or Mutation == "clamp-counter" or
      (Mutation == "ignore-negative-raw" and q.rawStart < 0),
    q' = {...q, published: true}}
  action step = any {ReadInventory, UnadmitProduction, ProjectRoots, Import, Gsc, UnrequestedGsc, CompileSourceSuite,
    CacheOutput, FreshCheckout, RestoreSource, DropPayload, DropReceipt, ChangeInput, ChangeCommit, ChangeManifest, Reuse, StartSourceVm, ExitSourceVm,
    Allocate, ResizeHeap, ObserveOccupancy, ObserveCompilerCpu, Finish, ChangeSource, CounterDecrease, CounterNegative, CompilerFails, CompilerInputChanges, Publish}
  val OnlyConsumerRoots = q.productionAdmitted implies q.forcedCatalogRoots == 0
  val DemandedSupportRetained = q.rootsProjected implies SelectedSupport.foldl(false, (found, root) => found or root == "requested")
  val CachedSupportRetained = q.rootsProjected implies SelectedSupport.foldl(false, (found, root) => found or root == "cached")
  val UnadmittedCatalogPresent = (q.rootsProjected and not(q.productionAdmitted)) implies q.forcedCatalogRoots == 1
  val InventoryDataOnly = q.inventoryDeclarations == 0
  val JobsExact = q.observedJobs == q.jobs
  val ImportsExact = q.observedImports == q.imports
  val HeapLimitUnchanged = q.heapCap == 3
  val HeapSelectionBounded = q.heapSections <= q.heapCap
  val CumulativeCapabilityRequired = not(q.cumulativeClaim)
  val AllocationNotNested = q.reportedAllocation == q.outerAllocation
  val CompilerCpuPartition = q.residualCpu >= 0 and q.helperCpu + q.residualCpu == q.gscCpu
  val RestoredSourceClock = q.sourceRestored implies q.sourceStamp <= 1
  val RestoredSourceCurrent = q.sourceRestored implies q.cacheGeneration == q.inputGeneration
  val CompilerWorkComplete = q.published implies (q.failedJobs == 0 and q.changedInputs == 0)
  val Complete = q.published implies q.finished
  val Current = q.published implies q.current
  val OrderedCounter = q.published implies (q.counterValid and q.rawStart >= 0 and q.rawStart <= q.rawFinish)
  val OnlyDemandedCompilation = q.unrequestedJobs == 0
  val SourceCarriersRemainSource = q.compiledSourceCarriers == 0
  val ContentKeyExact = q.requestKeyGeneration == q.inputGeneration
  val CompleteCacheBundle = not(q.incompleteReuse)
  val ReuseCurrentInputs = not(q.staleReuse)
  val PackedStartupCount = complete_packed_starts == 90 and complete_packed_starts < 146
  val BoundedSourceEntries = q.retainedEntryRoots <= SourceBatchLimit
  val ExitedVmReleasesEntries = not(q.sourceVmActive) implies q.retainedEntryRoots == 0
}
