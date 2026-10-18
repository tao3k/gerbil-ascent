// SPDX-FileCopyrightText: 2026 tao3k team and Contributors
// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
// Observer protocol. This does not model the SDK compiler or allocator.
module PreparationWork {
  const Mutation: str
  type State = {jobs: int, observedJobs: int, imports: int, observedImports: int,
                finished: bool, current: bool, counterValid: bool, published: bool,
                outerAllocation: int, reportedAllocation: int, inventoryDeclarations: int,
                unrequestedJobs: int, compiledSourceCarriers: int,
                inputGeneration: int, cacheGeneration: int, cacheReady: bool, staleReuse: bool}
  var q: State
  action init = q' = {jobs: 0, observedJobs: 0, imports: 0, observedImports: 0,
    finished: false, current: true, counterValid: true, published: false,
    outerAllocation: 0, reportedAllocation: 0, inventoryDeclarations: 0,
    unrequestedJobs: 0, compiledSourceCarriers: 0,
    inputGeneration: 0, cacheGeneration: 0, cacheReady: false, staleReuse: false}
  action ReadInventory = q' = {...q,
    inventoryDeclarations: if (Mutation == "bootstrap-inventory") 1 else 0}
  action Import = all {q.imports < 2,
    q' = {...q, imports: q.imports + 1,
      observedImports: if (Mutation == "forget-import") q.observedImports else q.observedImports + 1,
      published: false}}
  action Gsc = all {q.jobs < 2,
    q' = {...q, jobs: q.jobs + 1,
      observedJobs: if (Mutation == "hide-job") q.observedJobs else q.observedJobs + 1,
      published: false}}
  // Compilation is demanded by the native import graph, not directory size.
  action UnrequestedGsc = all {Mutation == "eager-catalog",
    q' = {...q, unrequestedJobs: q.unrequestedJobs + 1, published: false}}
  action CompileSourceSuite = all {any {Mutation == "compile-source-suite", Mutation == "compile-source-consumer"},
    q' = {...q, compiledSourceCarriers: q.compiledSourceCarriers + 1, published: false}}
  action CacheOutput = all {q.finished,
    q' = {...q, cacheReady: true, cacheGeneration: q.inputGeneration}}
  action ChangeInput = all {q.inputGeneration < 2,
    q' = {...q, inputGeneration: q.inputGeneration + 1, current: false, published: false}}
  action Reuse = all {q.cacheReady,
    q.cacheGeneration == q.inputGeneration or Mutation == "reuse-stale-input",
    q' = {...q, staleReuse: q.staleReuse or q.cacheGeneration != q.inputGeneration}}
  action Allocate = q' = {...q, outerAllocation: 4,
    reportedAllocation: if (Mutation == "sum-nested") 6 else 4, published: false}
  action Finish = all {q.jobs == 2, q.imports == 2, q' = {...q, finished: true}}
  action ChangeSource = q' = {...q, current: false, published: false}
  action CounterDecrease = q' = {...q, counterValid: false, published: false}
  action Publish = all {
    q.finished or Mutation == "publish-partial",
    q.current or Mutation == "ignore-generation",
    q.counterValid or Mutation == "clamp-counter",
    q' = {...q, published: true}}
  action step = any {ReadInventory, Import, Gsc, UnrequestedGsc, CompileSourceSuite,
    CacheOutput, ChangeInput, Reuse, Allocate, Finish, ChangeSource, CounterDecrease, Publish}
  val InventoryDataOnly = q.inventoryDeclarations == 0
  val JobsExact = q.observedJobs == q.jobs
  val ImportsExact = q.observedImports == q.imports
  val AllocationNotNested = q.reportedAllocation == q.outerAllocation
  val Complete = q.published implies q.finished
  val Current = q.published implies q.current
  val OrderedCounter = q.published implies q.counterValid
  val OnlyDemandedCompilation = q.unrequestedJobs == 0
  val SourceCarriersRemainSource = q.compiledSourceCarriers == 0
  val ReuseCurrentInputs = not(q.staleReuse)
}
