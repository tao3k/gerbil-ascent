-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Work observations, not a hardware latency model. GSC invocations consume
concrete hashed inputs. Import allocator snapshots are process-wide/inclusive:
they cannot be added as if nested imports owned disjoint allocation intervals.
The SDK compiler/allocator and the observer/decoder remain outside this proof. -/
namespace Ascent.PreparationWork

-- Importing build.ss evaluates its PackageSpec declaration even when the
-- consumer only requests its module list. The separate data module has no
-- such declaration. Source controls read that module with Gerbil's reader
-- and accept only quoted inventory data and its canonical four-entry append.
inductive InventorySource where
  | moduleData
  | buildEntry
  deriving DecidableEq

def inventoryPackageDeclarations : InventorySource → Nat
  | .moduleData => 0
  | .buildEntry => 1

def inventoryImportSchemeSource : String :=
  "        (only-in \"../../build-modules.ss\" gerbil-ascent-library-modules gerbil-ascent-build-input-modules)\n"

theorem module_data_avoids_package_declaration :
    inventoryPackageDeclarations .moduleData = 0 ∧
    inventoryPackageDeclarations .buildEntry = 1 := by decide

abbrev Dependency := List String × List String
def requested (tests : List String) (entry : Dependency) : Bool :=
  entry.1.any tests.contains
def selected (tests : List String) (entries : List Dependency) : List String :=
  (entries.filter (requested tests)).flatMap Prod.snd

-- A declared dependency has no cost effect in a lane that does not request it.
-- In particular scheme-artifact-test is absent from prepare-test-library's
-- performance consumers. Deleting its bridge entry cannot explain that lane.
theorem inactive_dependency_no_work (tests : List String)
    (before after : List Dependency) (entry : Dependency)
    (inactive : requested tests entry = false) :
    selected tests (before ++ entry :: after) = selected tests (before ++ after) := by
  simp [selected, List.filter_append, inactive]

def selectionSchemeSource : String :=
  ";; Generated from PreparationWork.lean; formal CI compares this region.\n" ++
  "(def (preparation-selected-dependencies tests entries)\n" ++
  "  (apply append\n" ++
  "    (map cdr\n" ++
  "      (filter (lambda (entry) (ormap (cut member <> tests) (car entry))) entries))))\n"

-- The native ASP/Gerbil graph supplies dependencies; this policy decides only
-- which carriers are compiled. It never removes a source Suite from discovery.
def retainedSource (sourceSuites : Bool) (sourceConsumers : List String) (path : String) : Bool :=
  !sourceConsumers.contains path && (!sourceSuites || !path.endsWith "-test.ss")

def sourceSchemeSource : String :=
  ";; Generated from PreparationWork.lean; formal CI compares this region.\n" ++
  "(def (preparation-retained-source? source source-suites? source-consumers)\n" ++
  "  (and (not (member source source-consumers))\n" ++
  "       (or (not source-suites?) (not (string-suffix? \"-test.ss\" source)))))\n"

theorem performance_carriers_retained (path : String) (sourceConsumers : List String)
    (compiled : path ∉ sourceConsumers) :
    retainedSource false sourceConsumers path = true := by simp [retainedSource, compiled]

theorem source_suite_not_compiled (path : String) (sourceConsumers : List String)
    (suite : path.endsWith "-test.ss" = true) :
    retainedSource true sourceConsumers path = false := by simp [retainedSource, suite]

theorem source_dependencies_retained (path : String) (sourceConsumers : List String)
    (compiled : path ∉ sourceConsumers)
    (support : path.endsWith "-test.ss" = false) :
    retainedSource true sourceConsumers path = true := by simp [retainedSource, support, compiled]

theorem explicit_source_not_compiled (path : String) (sourceConsumers : List String)
    (source : path ∈ sourceConsumers) (sourceSuites : Bool) :
    retainedSource sourceSuites sourceConsumers path = false := by simp [retainedSource, source]

-- Production carriers already belong to make. Forcing every producer from
-- source is not necessary to project consumer dependencies. This selects only
-- explicit roots; SDK import/compile closure remains a separate premise.
def projectionRoots (production modules tests consumers : List String)
    (productionCurrent : Bool) : List String :=
  (if productionCurrent then modules.filter (fun m => !production.contains m) else modules) ++
    tests ++ consumers

def rootsSchemeSource : String :=
  "(def (preparation-projection-roots production modules tests source-consumers production-current?)\n" ++
  "  (append (if production-current?\n" ++
  "            (filter (lambda (module) (not (member module production))) modules)\n" ++
  "            modules)\n" ++
  "          tests source-consumers))\n"

theorem explicit_test_root_retained (production modules tests consumers : List String)
    (current : Bool) (root : String) (present : root ∈ tests) :
    root ∈ projectionRoots production modules tests consumers current := by
  cases current <;> simp [projectionRoots, present]

theorem explicit_source_root_retained (production modules tests consumers : List String)
    (current : Bool) (root : String) (present : root ∈ consumers) :
    root ∈ projectionRoots production modules tests consumers current := by
  cases current <;> simp [projectionRoots, present]

theorem support_root_retained (production modules tests consumers : List String)
    (current : Bool) (root : String) (present : root ∈ modules) (support : root ∉ production) :
    root ∈ projectionRoots production modules tests consumers current := by
  cases current <;> simp [projectionRoots, present, support]

theorem unadmitted_catalog_revisited (production modules tests consumers : List String) :
    projectionRoots production modules tests consumers false = modules ++ tests ++ consumers := rfl

-- The caller appends the complete original carrier list to the projected
-- dependencies. Root filtering must never be reused as a compiler input filter.
theorem declared_carrier_retained (modules projected : List String) (root : String)
    (present : root ∈ modules) : root ∈ modules ++ projected := by simp [present]

-- Weights come from concrete compiler/expander events, not a fixed number of
-- native invocations per module. A graph projection removes work only for
-- modules outside the demand closure. SDK graph completeness remains a premise.
def sourceWork (weight : String → Nat) : List String → Nat
  | [] => 0
  | path :: rest => weight path + sourceWork weight rest

theorem demanded_work_le_catalog (weight : String → Nat) (needed : String → Bool)
    (catalog : List String) :
    sourceWork weight (catalog.filter needed) ≤ sourceWork weight catalog := by
  induction catalog with
  | nil => simp [sourceWork]
  | cons path rest ih =>
    by_cases h : needed path = true
    · simp [List.filter_cons, h, sourceWork]
      omega
    · simp [List.filter_cons, h, sourceWork]
      omega

theorem sourceWork_append (weight : String → Nat) (left right : List String) :
    sourceWork weight (left ++ right) = sourceWork weight left + sourceWork weight right := by
  induction left with
  | nil => simp [sourceWork]
  | cons x xs ih => simp [sourceWork, ih, Nat.add_assoc]

-- Bounds explicit root requests only. Transitive expansion, cache state,
-- allocation and hardware latency do not have a fixed per-root cost here.
theorem projection_root_work_le_full (weight : String → Nat)
    (production modules tests consumers : List String) (current : Bool) :
    sourceWork weight (projectionRoots production modules tests consumers current) ≤
      sourceWork weight (modules ++ tests ++ consumers) := by
  cases current
  · simp [projectionRoots]
  · simp only [projectionRoots, Bool.true_eq, ↓reduceIte, sourceWork_append]
    have bound := demanded_work_le_catalog weight (fun m => !production.contains m) modules
    omega

-- gxtest imports every requested entry before running the harness. Its native
-- module registry retains the expanded contexts through VM exit. Isolating
-- entries bounds this retained entry footprint, but increases process starts.
inductive SourceGrouping where
  | batched
  | perModule
  deriving DecidableEq

def groupingArgument : SourceGrouping → String
  | .batched => "batched"
  | .perModule => "isolated"

def sourceGrouping : SourceGrouping := .batched

def runnerRecipeSource : String :=
  "        runner=({{ gxi_command }} {{ gerbil_test_runtime_options }} t/harness/test.ss " ++
  groupingArgument sourceGrouping ++ " \"{{ heap }}\")\n"

-- The implementation composes the existing native partitioner twice. It
-- neither adds workers nor invents option-compatibility rules. Native graph
-- and grouping correctness remain premises, not claimed SDK refinements.
def groupsSchemeSource : String :=
  "(def (preparation-refined-batches profiled compatible)\n" ++
  "  (apply append\n" ++
  "    (map (cut testing-interface-test-file-batches profiled <>)\n" ++
  "      (testing-interface-test-file-batches profiled\n" ++
  "        (striped-module-files compatible (testing-interface-worker-count (length compatible)))))))\n"

def refineBatches (split : List String → List (List String))
    (groups : List (List String)) : List (List String) := groups.flatMap split

theorem refined_entries_preserved (split : List String → List (List String))
    (groups : List (List String))
    (coverage : ∀ group ∈ groups, (split group).flatten = group) :
    (refineBatches split groups).flatten = groups.flatten := by
  induction groups with
  | nil => simp [refineBatches]
  | cons group groups ih =>
    have first := coverage group (by simp)
    have rest := ih (by intro g h; exact coverage g (by simp [h]))
    simp only [refineBatches, List.flatMap_cons, List.flatten_append, List.flatten_cons] at *
    rw [first, rest]

def isolatedEntryPeak (weight : String → Nat) : List String → Nat
  | [] => 0
  | path :: rest => max (weight path) (isolatedEntryPeak weight rest)

theorem isolated_entry_peak_le_batched (weight : String → Nat) (entries : List String) :
    isolatedEntryPeak weight entries ≤ sourceWork weight entries := by
  induction entries with
  | nil => simp [isolatedEntryPeak, sourceWork]
  | cons path rest ih =>
    simp only [isolatedEntryPeak, sourceWork]
    omega

theorem one_entry_per_isolated_batch (entries : List String) (batch : List String)
    (present : batch ∈ entries.map (fun entry => [entry])) : batch.length = 1 := by
  simp only [List.mem_map] at present
  obtain ⟨entry, _, rfl⟩ := present
  rfl

theorem isolated_process_starts (entries : List String) :
    (entries.map (fun entry => [entry])).length = entries.length := by simp

theorem isolated_entries_preserved (entries : List String) :
    (entries.map (fun entry => [entry])).flatten = entries := by
  induction entries with
  | nil => rfl
  | cons entry rest ih => simp [ih]

-- File contents, dependency generations, SDK/options and output presence all
-- participate in reuse. This is a cost precondition, not a claim that the SDK
-- timestamp cache or the untyped receipt decoder has been source-refined.
structure CompileKey where
  -- Exact expanded compiler-input digest, including generated timestamps.
  -- This is not a DSL digest or a byte count; the observer retains the bytes.
  source : String
  dependencies : String
  sdk : String
  options : String
  deriving DecidableEq, Repr

def reuse (stored requested : CompileKey) (outputPresent : Bool) : Bool :=
  decide (stored = requested) && outputPresent

theorem changed_input_requires_work (stored requested : CompileKey)
    (changed : stored ≠ requested) (outputPresent : Bool) :
    reuse stored requested outputPresent = false := by simp [reuse, changed]

theorem missing_output_requires_work (stored requested : CompileKey) :
    reuse stored requested false = false := by simp [reuse]

structure Work where
  jobs : Nat := 0
  inputBytes : Nat := 0
  deriving DecidableEq, Repr

def Work.plus (a b : Work) : Work :=
  ⟨a.jobs + b.jobs, a.inputBytes + b.inputBytes⟩

def total : List Work → Work
  | [] => ⟨0, 0⟩
  | x :: xs => x.plus (total xs)

theorem total_append (xs ys : List Work) :
    total (xs ++ ys) = (total xs).plus (total ys) := by
  induction xs with
  | nil => simp [total, Work.plus]
  | cons x xs ih => simp [total, ih, Work.plus, Nat.add_assoc]

-- Removing two observed GSC records retains every other record. A module
-- or logical compile-file job must not be assumed to correspond to two GSC
-- invocations; the actual SDK pipeline can use several processes per job.
theorem removed_two_observations (before after : List Work) (phase0 phase1 : Nat) :
    (total (before ++ [⟨1, phase0⟩, ⟨1, phase1⟩] ++ after)).jobs =
      (total (before ++ after)).jobs + 2 ∧
    (total (before ++ [⟨1, phase0⟩, ⟨1, phase1⟩] ++ after)).inputBytes =
      (total (before ++ after)).inputBytes + phase0 + phase1 := by
  simp [total_append, total, Work.plus]
  omega

-- Snapshot subtraction is valid for ordered observations. Nested inclusive
-- measurements are not inputs to this telescoping total.
theorem ordered_allocation_snapshots (start middle finish : Nat)
    (first : start ≤ middle) (second : middle ≤ finish) :
    (middle - start) + (finish - middle) = finish - start := by omega

theorem nested_inclusive_double_counts (outer inner : Nat) (positive : 0 < inner) :
    outer < outer + inner := by omega

-- Nat subtraction would silently turn this invalid interval into zero.
-- The observed counter must pass ordering before it can enter an allocation sum.
theorem decreasing_counter_rejected (start finish : Nat) (decreased : finish < start) :
    decide (start ≤ finish) = false := by simp; omega

-- CPU/work bounds do not establish wall bounds: queue/IO/descheduling time
-- is an independent nonnegative component and is not silently set to zero.
theorem work_reduction_does_not_bound_wait (work saved wait : Nat)
    (enough : saved ≤ work) (delay : saved < wait) :
    work < work - saved + wait := by omega

#print axioms explicit_test_root_retained
#print axioms explicit_source_root_retained
#print axioms support_root_retained
#print axioms unadmitted_catalog_revisited
#print axioms declared_carrier_retained
#print axioms sourceWork_append
#print axioms projection_root_work_le_full
#print axioms total_append
#print axioms performance_carriers_retained
#print axioms source_suite_not_compiled
#print axioms source_dependencies_retained
#print axioms explicit_source_not_compiled
#print axioms demanded_work_le_catalog
#print axioms refined_entries_preserved
#print axioms isolated_entry_peak_le_batched
#print axioms one_entry_per_isolated_batch
#print axioms isolated_process_starts
#print axioms isolated_entries_preserved
#print axioms changed_input_requires_work
#print axioms missing_output_requires_work
#print axioms module_data_avoids_package_declaration
#print axioms inactive_dependency_no_work
#print axioms removed_two_observations
#print axioms ordered_allocation_snapshots
#print axioms nested_inclusive_double_counts
#print axioms decreasing_counter_rejected
#print axioms work_reduction_does_not_bound_wait
end Ascent.PreparationWork
