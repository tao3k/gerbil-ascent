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
  "        (only-in \"../../build-modules.ss\" gerbil-ascent-library-modules gerbil-ascent-build-input-modules gerbil-ascent-compiler-options)\n"

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
  "          tests source-consumers))\n" ++
  "(def (preparation-support-roots source-suites? base requested cached)\n" ++
  "  (append (if source-suites? [] base) requested cached))\n"

-- This dispatch is only active after the existing source/SDK receipt check.
-- It changes an admitted producer's input path, not source-Suite execution.
-- Native normalization/expansion and receipt decoding remain explicit premises.
def interfaceSelected (admitted reload compiling producer present : Bool) : Bool :=
  admitted && !reload && !compiling && producer && present

theorem invalidated_producer_uses_source (reload compiling producer present : Bool) :
    interfaceSelected false reload compiling producer present = false := by simp [interfaceSelected]
theorem reload_uses_source (admitted compiling producer present : Bool) :
    interfaceSelected admitted true compiling producer present = false := by simp [interfaceSelected]
theorem compiling_uses_source (admitted reload producer present : Bool) :
    interfaceSelected admitted reload true producer present = false := by simp [interfaceSelected]
theorem consumer_uses_source (admitted reload compiling present : Bool) :
    interfaceSelected admitted reload compiling false present = false := by simp [interfaceSelected]
theorem missing_interface_uses_source (admitted reload compiling producer : Bool) :
    interfaceSelected admitted reload compiling producer false = false := by simp [interfaceSelected]
theorem admitted_producer_uses_interface : interfaceSelected true false false true true = true := rfl

-- The SDK decodes qualified syntax to the same interned symbol as a bare
-- library identifier. Unknown forms are forwarded untouched; normalization
-- and syntax identity are SDK premises, not a proof of its whole expander.
inductive InterfaceRequest where
  | source | library | syntaxLibrary | other
  deriving DecidableEq

def requestSupported : InterfaceRequest → Bool
  | .source | .library | .syntaxLibrary => true
  | .other => false

def requestInterfaceSelected (request : InterfaceRequest)
    (admitted reload compiling producer present : Bool) : Bool :=
  requestSupported request && interfaceSelected admitted reload compiling producer present

theorem qualified_request_same_as_source (admitted reload compiling producer present : Bool) :
    requestInterfaceSelected .library admitted reload compiling producer present =
      requestInterfaceSelected .source admitted reload compiling producer present := rfl

theorem syntax_request_same_as_source (admitted reload compiling producer present : Bool) :
    requestInterfaceSelected .syntaxLibrary admitted reload compiling producer present =
      requestInterfaceSelected .source admitted reload compiling producer present := rfl

theorem unknown_request_forwarded (admitted reload compiling producer present : Bool) :
    requestInterfaceSelected .other admitted reload compiling producer present = false := by
  simp [requestInterfaceSelected, requestSupported]

-- Count actual source-body completions separately from interface completions.
-- These event weights do not assert a latency or cumulative-allocation bound.
def sourceCompletion (interface : Bool) : Nat := if interface then 0 else 1
theorem admitted_source_completion_avoided :
    sourceCompletion (interfaceSelected true false false true true) = 0 := rfl

-- Gerbil's list->hash-table inserts left to right. Reversing the entry list
-- therefore preserves assoc's FIRST match, including duplicate normalized aliases.
-- Std.HashMap discharges this data-structure lemma; the Gerbil hash implementation
-- and SDK path/syntax normalization remain explicit host assumptions.
def interfaceIndex {α : Type} [BEq α] [Hashable α] : List (α × String) → Std.HashMap α String
  | [] => ∅
  | (key, value) :: rest => (interfaceIndex rest).insert key value

def interfaceAssoc {α : Type} [BEq α] (entries : List (α × String)) (key : α) : Option String :=
  match entries with
  | [] => none
  | (candidate, value) :: rest =>
    if candidate == key then some value else interfaceAssoc rest key

theorem indexed_interface_equals_first_assoc {α : Type} [BEq α] [Hashable α]
    [EquivBEq α] [LawfulHashable α] (entries : List (α × String)) (key : α) :
    (interfaceIndex entries)[key]? = interfaceAssoc entries key := by
  induction entries with
  | nil => simp [interfaceIndex, interfaceAssoc]
  | cons entry rest ih =>
    rcases entry with ⟨candidate, value⟩
    simp only [interfaceIndex, Std.HashMap.getElem?_insert, interfaceAssoc, ih]

-- Number of key comparisons performed by the former source-loaded assoc.
-- Hash-table probe complexity is not claimed: collisions belong to the host.
def interfaceAssocComparisons {α : Type} [BEq α] (entries : List (α × String)) (key : α) : Nat :=
  match entries with
  | [] => 0
  | (candidate, _) :: rest =>
    1 + if candidate == key then 0 else interfaceAssocComparisons rest key

theorem assoc_missing_traverses_catalog {α : Type} [BEq α]
    (entries : List (α × String)) (key : α)
    (missing : ∀ entry ∈ entries, (entry.1 == key) = false) :
    interfaceAssocComparisons entries key = entries.length := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
    rcases entry with ⟨candidate, value⟩
    have ne : (candidate == key) = false := missing (candidate, value) (by simp)
    simp [interfaceAssocComparisons, ne, ih (fun e h => missing e (by simp [h])), Nat.add_comm]

def interfacesQuintSource : String :=
  "// Generated from PreparationWork.lean; formal CI checks exact source.\n" ++
  "module PreparationInterfaces {\n" ++
  "  pure def interface_selected(admitted: bool, reload: bool, compiling: bool, producer: bool, present: bool): bool =\n" ++
  "    admitted and not(reload) and not(compiling) and producer and present\n" ++
  "  pure def request_interface_selected(request: int, admitted: bool, reload: bool, compiling: bool, producer: bool, present: bool): bool =\n" ++
  "    Set(0, 1, 2).contains(request) and interface_selected(admitted, reload, compiling, producer, present)\n" ++
  "  // Two possibly aliased entries: reverse insertion must retain the first.\n" ++
  "  pure def first_alias(k0: int, v0: int, k1: int, v1: int, key: int): int =\n" ++
  "    if (k0 == key) v0 else if (k1 == key) v1 else -1\n" ++
  "  pure def batch_width(entries: int, workers: int): int =\n" ++
  "    if (entries == 0) 0 else (entries - 1) / workers + 1\n" ++
  "}\n"

def interfacesSchemeSource : String :=
  ";; Gerbil still owns syntax decoding, path normalization, caching and expansion.\n" ++
  "(def (call-with-preparation-production-interfaces admitted? library production thunk)\n" ++
  "  (let* ((original (current-expander-module-import))\n" ++
  "        (entries\n" ++
  "          (if admitted?\n" ++
  "            (apply append (map\n" ++
  "              (lambda (module)\n" ++
  "                (let (target (path-expand (string-append \"gerbil-ascent/\" module \".ssi\") library))\n" ++
  "                  (if (file-exists? target)\n" ++
  "                    (list (cons (path-normalize (string-append module \".ss\")) target)\n" ++
  "                          (cons (string->symbol (string-append \":gerbil-ascent/\" module)) target))\n" ++
  "                    [])))\n" ++
  "              production))\n" ++
  "            []))\n" ++
  "         ;; Reverse insertion retains the first matching alias.\n" ++
  "         (interfaces (list->hash-table (reverse entries))))\n" ++
  "    (parameterize\n" ++
  "      ((current-expander-module-import\n" ++
  "         (lambda (path reload?)\n" ++
  "           (let (entry\n" ++
  "                  (and (not reload?) (not (current-compile-context))\n" ++
  "                       (let (key (cond ((string? path) (path-normalize path))\n" ++
  "                                        ((core-library-module-path? path) (stx-e path))\n" ++
  "                                        (else #f)))\n" ++
  "                         (and key (hash-get interfaces key)))))\n" ++
  "             (original (or entry path) reload?)))))\n" ++
  "      (thunk))))\n"

-- Source Suites name their own imports. CLI-only fixture drivers are not
-- implicit roots. Previously compiled fixtures still need ABI refresh.
def supportRoots (sourceSuites : Bool) (base requested cached : List String) : List String :=
  (if sourceSuites then [] else base) ++ requested ++ cached

def supportQuintSource : String :=
  "// Generated from PreparationWork.lean; formal CI checks exact source.\n" ++
  "module PreparationSupport {\n" ++
  "  pure def support_roots(source_suites: bool, base: List[str], requested: List[str], cached: List[str]): List[str] =\n" ++
  "    (if (source_suites) List() else base).concat(requested).concat(cached)\n}\n"

theorem requested_support_retained (sourceSuites : Bool) (base requested cached : List String)
    (path : String) (present : path ∈ requested) :
    path ∈ supportRoots sourceSuites base requested cached := by
  cases sourceSuites <;> simp [supportRoots, present]

theorem cached_support_retained (sourceSuites : Bool) (base requested cached : List String)
    (path : String) (present : path ∈ cached) :
    path ∈ supportRoots sourceSuites base requested cached := by
  cases sourceSuites <;> simp [supportRoots, present]

theorem source_roots_exclude_unrequested_catalog (base requested cached : List String)
    (path : String) (unrequested : path ∉ requested) (uncached : path ∉ cached) :
    path ∉ supportRoots true base requested cached := by
  simp [supportRoots, unrequested, uncached]

theorem compiled_base_retained (base requested cached : List String)
    (path : String) (present : path ∈ base) :
    path ∈ supportRoots false base requested cached := by simp [supportRoots, present]

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

-- The SDK eagerly prepares every module in one GxTest batch. Two native
-- partitions trade extra starts for a smaller retained source-entry set.
def groupsSchemeSource : String :=
  "(def (preparation-refined-batches profiled compatible)\n" ++
  "  (apply append\n" ++
  "    (map (cut testing-interface-test-file-batches profiled <>)\n" ++
  "      (testing-interface-test-file-batches profiled\n" ++
  "        (striped-module-files compatible (testing-interface-worker-count (length compatible)))))))\n" ++
  "(def (preparation-batch-width entries workers)\n" ++
  "  (if (zero? entries) 0 (+ 1 (quotient (- entries 1) workers))))\n" ++
  "(def (preparation-batches-bounded? batches entries workers)\n" ++
  "  (let (bound (preparation-batch-width (preparation-batch-width entries workers) workers))\n" ++
  "    (andmap (lambda (batch) (<= (length batch) bound)) batches)))\n" ++
  "(def (single-thread-vm-command command)\n" ++
  "  (let wrap ((arguments command))\n" ++
  "    (cond\n" ++
  "      ((null? arguments) (error \"native test command has no expression\" command))\n" ++
  "      ((equal? (car arguments) \"-e\")\n" ++
  "       (cons \"-e\" (cons\n" ++
  "         (string-append\n" ++
  "           \"(let (n (##current-vm-processor-count)) (unless (= n 1) (error \\\"expected one processor per test VM\\\" n)) (displayln \\\"VM-RUNTIME processors=\\\" n)) \"\n" ++
  "           (cadr arguments))\n" ++
  "         (cddr arguments))))\n" ++
  "      (else (cons (car arguments) (wrap (cdr arguments)))))))\n" ++
  "(def (source-test-batches profiled files mode)\n" ++
  "  (let (batches\n" ++
  "    (if (string=? mode \"batched\")\n" ++
  "      (let-values (((isolated compatible)\n" ++
  "                    (partition (lambda (file) (testing-interface-test-file-isolated? profiled file)) files)))\n" ++
  "        (append (map list isolated) (preparation-refined-batches profiled compatible)))\n" ++
  "      (testing-interface-test-file-batches profiled files)))\n" ++
  "    (unless (or (null? files)\n" ++
  "                (preparation-batches-bounded? batches (length files)\n" ++
  "                  (testing-interface-worker-count (length files))))\n" ++
  "      (error \"source batch retains too many entry modules\"))\n" ++
  "    batches))\n"

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

-- Every compatible native batch launches a fresh VM. Counting starts is
-- distinct from concurrent capacity, elapsed time and cumulative allocation.
def batchStartupUnits (groups : List (List String)) : Nat := groups.length

theorem second_partition_never_fewer_starts
    (split : List String → List (List String)) (groups : List (List String))
    (nonempty : ∀ group ∈ groups, 1 ≤ (split group).length) :
    batchStartupUnits groups ≤ batchStartupUnits (refineBatches split groups) := by
  induction groups with
  | nil => simp [batchStartupUnits, refineBatches]
  | cons group groups ih =>
    have first := nonempty group (by simp)
    have rest := ih (by intro g h; exact nonempty g (by simp [h]))
    simp only [batchStartupUnits, refineBatches, List.flatMap_cons, List.length_append,
      List.length_cons] at *
    omega

-- Ceiling width of a balanced native group. Native partition balance and
-- compatibility remain SDK premises; the source controller checks actual width.
def nativeBatchWidth (entries workers : Nat) : Nat :=
  if entries = 0 then 0 else (entries - 1) / workers + 1

def batchWidthPythonSource : String :=
  "def source_batch_width(entries, workers):\n" ++
  "    return 0 if entries == 0 else (entries - 1) // workers + 1\n"

theorem native_batch_width_le_entries (entries workers : Nat) :
    nativeBatchWidth entries workers ≤ entries := by
  unfold nativeBatchWidth
  split
  · omega
  · have h := Nat.div_le_self (entries - 1) workers
    omega

theorem native_refinement_retained_width (entries workers : Nat) :
    nativeBatchWidth (nativeBatchWidth entries workers) workers ≤
      nativeBatchWidth entries workers := native_batch_width_le_entries _ _

def batchesBounded (groups : List (List String)) (entries workers : Nat) : Bool :=
  groups.all (fun group => group.length ≤ nativeBatchWidth (nativeBatchWidth entries workers) workers)

theorem oversized_batch_refused (groups : List (List String)) (entries workers : Nat)
    (group : List String) (present : group ∈ groups)
    (oversized : nativeBatchWidth (nativeBatchWidth entries workers) workers < group.length) :
    batchesBounded groups entries workers = false := by
  cases h : batchesBounded groups entries workers with
  | false => rfl
  | true =>
    have bound := (List.all_eq_true.mp h) group present
    simp only [decide_eq_true_eq] at bound
    omega

theorem complete_source_batch_width : nativeBatchWidth (nativeBatchWidth 174 12) 12 = 2 := by decide

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

-- std/make's build? compares every direct input timestamp with its outputs.
-- An exact cache key does not prevent a fresh checkout timestamp from making
-- the same bytes newer. Restoring the matching source/product snapshot keeps
-- that native check effective; changed bytes still fail the Git admission.
def directInputNewer (source output : Nat) : Bool := decide (output < source)

theorem fresh_checkout_requires_rebuild (cached checkout output : Nat)
    (_previous : cached ≤ output) (fresh : output < checkout) :
    directInputNewer checkout output = true := by simp [directInputNewer, fresh]

theorem restored_source_avoids_timestamp_rebuild (cached output : Nat)
    (compiled : cached ≤ output) : directInputNewer cached output = false := by
  simp [directInputNewer]; omega

-- A CI cache entry is not just its compiled interfaces. The existing producer
-- guard reads the payload and content receipt before native make can reuse it.
-- Presence is necessary, never sufficient: reuse still requires the exact key.
def bundleReuse (stored requested : CompileKey)
    (interfaces payload receipt : Bool) : Bool :=
  reuse stored requested (interfaces && payload && receipt)

theorem missing_payload_requires_work (stored requested : CompileKey)
    (interfaces receipt : Bool) : bundleReuse stored requested interfaces false receipt = false := by
  simp [bundleReuse, reuse]

theorem missing_receipt_requires_work (stored requested : CompileKey)
    (interfaces payload : Bool) : bundleReuse stored requested interfaces payload false = false := by
  simp [bundleReuse, reuse]

theorem bundle_requires_current_inputs (stored requested : CompileKey)
    (changed : stored ≠ requested) (interfaces payload receipt : Bool) :
    bundleReuse stored requested interfaces payload receipt = false := by
  simp [bundleReuse, reuse, changed]

-- Commit labels do not change compiler inputs or authorize reuse. The cache
-- namespace keeps toolchain/platform identity; its suffix hashes input bytes.
def cargoIdentity (inputs : CompileKey) (_commit : String) : CompileKey := inputs

-- The unused package version manifest is a CLI output, not a compiler source.
def cargoSourceIdentity (inputs : CompileKey) (_versionManifest : String) : CompileKey := inputs

theorem generated_manifest_does_not_invalidate (inputs : CompileKey) (before after : String) :
    cargoSourceIdentity inputs before = cargoSourceIdentity inputs after := rfl

theorem equal_content_cross_commit_key (inputs : CompileKey) (before after : String) :
    cargoIdentity inputs before = cargoIdentity inputs after := rfl

theorem changed_content_cross_commit_rejected (stored requested : CompileKey)
    (changed : stored ≠ requested) (before after : String) (present : Bool) :
    reuse (cargoIdentity stored before) (cargoIdentity requested after) present = false := by
  simp [cargoIdentity, reuse, changed]

-- Exact CI key source. Generated resources are outputs, never key inputs.
def cargoCacheSchemeSource : String :=
  "          key: ascent-cargo-products-v4-${{ runner.os }}-${{ runner.arch }}-${{ steps.rust.outputs.compiler }}-${{ steps.capacity.outputs.toolchain }}-${{ hashFiles('rust/**/*.rs', 'rust/**/Cargo.toml', 'rust/Cargo.lock', '.cargo/**', 'python/pyproject.toml', 'python/src/ascent/**', '**/*.ss', 'bindings/**', 'gerbil.pkg', 'justfile', '.github/workflows/ci.yml', '!manifest.ss', '!rust/**/target/**', '!.gerbil/**', '!.ci/**', '!.cache/**', '!python/src/ascent/_sources/**', '!python/src/ascent/.gerbil-resources.json') }}\n"

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

-- preparation_work.execute_gsc reads RUSAGE_CHILDREN after waiting for GSC.
-- Its helper observer reads the same statistic for GSC's native child only.
-- Parent identity must be retained; disjoint parents cannot share a child.
-- The OS accounting/decoder are premises, not source-refined by this lemma.
def compilerCpuResidual (inclusive nested : Nat) : Option Nat :=
  if nested ≤ inclusive then some (inclusive - nested) else none

theorem compiler_cpu_partition (inclusive nested residual : Nat)
    (accepted : compilerCpuResidual inclusive nested = some residual) :
    residual + nested = inclusive := by
  unfold compilerCpuResidual at accepted
  split at accepted
  · simp only [Option.some.injEq] at accepted
    omega
  · contradiction

theorem excessive_child_cpu_rejected (inclusive nested : Nat)
    (invalid : inclusive < nested) : compilerCpuResidual inclusive nested = none := by
  simp [compilerCpuResidual]; omega


-- Nat subtraction would silently turn this invalid interval into zero.
-- The observed counter must pass ordering before it can enter an allocation sum.
theorem decreasing_counter_rejected (start finish : Nat) (decreased : finish < start) :
    decide (start ≤ finish) = false := by simp; omega

-- The pinned SDK's mem.c ___bytes_allocated adds current still-object
-- occupancy to processor accounting. _repl.scm ##exec-stats then subtracts
-- the interpreted frame and statistics-vector corrections. This signed
-- arithmetic models that formula, not a cumulative allocator event counter.
def sdkCounter (processorAccounting stillOccupancy : Int) : Int :=
  processorAccounting + stillOccupancy

def sdkEstimate (start finish frameCorrection structureCorrection : Int) : Int :=
  finish - start - (frameCorrection + structureCorrection)

theorem still_release_can_decrease_counter (accounting still growth : Int)
    (released : growth < still) :
    sdkCounter (accounting + growth) 0 < sdkCounter accounting still := by
  simp only [sdkCounter]; omega

theorem negative_estimate_iff (start finish frame correction : Int) :
    sdkEstimate start finish frame correction < 0 ↔ finish - start < frame + correction := by
  simp only [sdkEstimate]; omega

-- A raw decrease cannot become admitted by a positive corrected estimate.
def allocationObservationValid (rawStart rawFinish corrected : Int) : Bool :=
  decide (0 ≤ rawStart ∧ rawStart ≤ rawFinish ∧ 0 ≤ corrected)

theorem raw_counter_drop_rejected (start finish corrected : Int)
    (decreased : finish < start) :
    allocationObservationValid start finish corrected = false := by
  simp [allocationObservationValid]; omega

theorem negative_raw_counter_rejected (start finish corrected : Int)
    (negative : start < 0) : allocationObservationValid start finish corrected = false := by
  simp [allocationObservationValid]; omega

-- The released SDK's adjust_heap uses division before multiplication.
-- resize_heap retains a separate maximum section bound; the live-ratio policy
-- never changes that bound. These lemmas describe that arithmetic, not RSS,
-- GC latency, or the complete native resize/overflow implementation.
def preparationHeapGiB : Nat := 3
def preparationLiveRatio : Nat := 50

def heapRecipeSource : String :=
  "preparation_runtime_options := \"-:max-heap=" ++ toString preparationHeapGiB ++
  "G,live-ratio=" ++ toString preparationLiveRatio ++ ",debug=q\"\n"

def adjustedHeapWords (live minimum ratio : Nat) : Nat :=
  max (live / ratio * 100) minimum

def resizedSections (target lower upper : Nat) : Nat :=
  min (max target lower) upper

theorem resized_sections_preserve_maximum (target lower upper : Nat) :
    resizedSections target lower upper ≤ upper := Nat.min_le_right _ _

theorem preparation_heap_policy_is_bounded :
    preparationHeapGiB = 3 ∧ 0 < preparationLiveRatio ∧ preparationLiveRatio ≤ 100 := by
  decide

-- mem.c updates current still occupancy on allocation and release. The
-- existing counter exposes its endpoint, not the history of those events.
-- Thus even exact endpoint arithmetic cannot recover cumulative still bytes.
inductive StillEvent where
  | allocate (bytes : Int) | release (bytes : Int)

def stillEndpoint : List StillEvent → Int
  | [] => 0
  | .allocate n :: rest => n + stillEndpoint rest
  | .release n :: rest => -n + stillEndpoint rest

def stillAllocated : List StillEvent → Int
  | [] => 0
  | .allocate n :: rest => n + stillAllocated rest
  | .release _ :: rest => stillAllocated rest

theorem equal_still_endpoints_do_not_identify_allocation (bytes : Int) (positive : 0 < bytes) :
    stillEndpoint [.allocate bytes, .release bytes] = stillEndpoint [] ∧
    stillAllocated [.allocate bytes, .release bytes] ≠ stillAllocated [] := by
  simp [stillEndpoint, stillAllocated]
  omega

-- Valid only for exact integer observations of the SDK's floating counters.
-- This separates the observed processor and still-occupancy components; it
-- does not promote either into a full allocator-event stream.
theorem sdk_counter_component_difference (processorBefore processorAfter stillBefore stillAfter : Int) :
    sdkCounter processorAfter stillAfter - sdkCounter processorBefore stillBefore =
    (processorAfter - processorBefore) + (stillAfter - stillBefore) := by
  simp [sdkCounter]; omega

-- The SDK inserts path and id aliases only after core-expand-module-begin
-- and code assignment. The observer indexes context identity, not registry keys.
-- This list model specifies that boundary; the SDK hash-table implementation,
-- failed expansions, and work before observer installation remain premises.
def completedContexts (before after : List Nat) : List Nat :=
  (after.filter (fun identity => !before.contains identity)).eraseDups

theorem completed_context_not_preexisting (before after : List Nat) (identity : Nat)
    (present : identity ∈ completedContexts before after) : identity ∉ before := by
  have filtered := List.mem_filter.mp (List.mem_eraseDups.mp present)
  simpa using filtered.2

theorem resident_context_scan_has_no_new_work (contexts : List Nat) :
    completedContexts contexts contexts = [] := by
  have empty : contexts.filter (fun identity => !contexts.contains identity) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro identity present
    simp [present]
  rw [completedContexts, empty]
  rfl

-- Even a nonnegative occupancy interval is not a cumulative allocation stream.
-- Cumulative events are a separate capability, never inferred from its sign.
inductive AllocationMetric where
  | occupancyEstimate | cumulativeEvents
  deriving DecidableEq

def cumulativeAdmitted (metric : AllocationMetric) : Bool :=
  metric == .cumulativeEvents

theorem occupancy_never_admits_cumulative :
    cumulativeAdmitted .occupancyEstimate = false := by rfl

-- CPU/work bounds do not establish wall bounds: queue/IO/descheduling time
-- is an independent component.
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
#print axioms equal_content_cross_commit_key
#print axioms changed_content_cross_commit_rejected
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
#print axioms fresh_checkout_requires_rebuild
#print axioms restored_source_avoids_timestamp_rebuild
#print axioms missing_payload_requires_work
#print axioms missing_receipt_requires_work
#print axioms bundle_requires_current_inputs
#print axioms module_data_avoids_package_declaration
#print axioms inactive_dependency_no_work
#print axioms removed_two_observations
#print axioms ordered_allocation_snapshots
#print axioms nested_inclusive_double_counts
#print axioms compiler_cpu_partition
#print axioms excessive_child_cpu_rejected
#print axioms decreasing_counter_rejected
#print axioms work_reduction_does_not_bound_wait
#print axioms still_release_can_decrease_counter
#print axioms negative_estimate_iff
#print axioms raw_counter_drop_rejected
#print axioms negative_raw_counter_rejected
#print axioms completed_context_not_preexisting
#print axioms resident_context_scan_has_no_new_work
#print axioms occupancy_never_admits_cumulative

#print axioms resized_sections_preserve_maximum
#print axioms preparation_heap_policy_is_bounded
#print axioms equal_still_endpoints_do_not_identify_allocation
#print axioms sdk_counter_component_difference
end Ascent.PreparationWork

#print axioms Ascent.PreparationWork.invalidated_producer_uses_source
#print axioms Ascent.PreparationWork.reload_uses_source
#print axioms Ascent.PreparationWork.consumer_uses_source
#print axioms Ascent.PreparationWork.missing_interface_uses_source
#print axioms Ascent.PreparationWork.admitted_producer_uses_interface
#print axioms Ascent.PreparationWork.admitted_source_completion_avoided

#print axioms Ascent.PreparationWork.compiling_uses_source
#print axioms Ascent.PreparationWork.qualified_request_same_as_source
#print axioms Ascent.PreparationWork.syntax_request_same_as_source
#print axioms Ascent.PreparationWork.unknown_request_forwarded

#print axioms Ascent.PreparationWork.indexed_interface_equals_first_assoc
#print axioms Ascent.PreparationWork.assoc_missing_traverses_catalog

#print axioms Ascent.PreparationWork.second_partition_never_fewer_starts

#print axioms Ascent.PreparationWork.native_batch_width_le_entries
#print axioms Ascent.PreparationWork.native_refinement_retained_width
#print axioms Ascent.PreparationWork.complete_source_batch_width

#print axioms Ascent.PreparationWork.oversized_batch_refused
