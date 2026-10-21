-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Compiler settings and scoped cost admission. Native GCC/Gambit code generation,
JSON/S-expression readers and allocator implementation remain explicit premises.
The source renderings below bind the deployed guards, not a proof of all SDK code. -/
namespace Ascent.CompilerCost

def hostLimit : Nat := 512
-- Exact predicate in the pinned gambit.h: downgrade iff limit > 0 && labels > limit.
def singleHost (labels limit : Nat) : Bool := limit == 0 || labels ≤ limit

theorem small_unit_unchanged (labels : Nat) (small : labels ≤ hostLimit) :
    singleHost labels hostLimit = singleHost labels 0 := by
  have bound : labels ≤ 512 := small
  simp [singleHost, hostLimit, bound]

theorem oversized_unit_split (labels : Nat) (large : hostLimit < labels) :
    singleHost labels hostLimit = false := by
  have bound : ¬ labels ≤ 512 := Nat.not_le.mpr large
  simp [singleHost, hostLimit, bound]

structure Profile where
  sdk : String
  root : String
  options : List String
  deriving DecidableEq

def profileCurrent (expected observed : Profile) : Bool := expected == observed

theorem changed_options_invalidate (sdk root : String) (a b : List String) (changed : a ≠ b) :
    profileCurrent ⟨sdk, root, a⟩ ⟨sdk, root, b⟩ = false := by simp [profileCurrent, changed]

theorem changed_root_invalidate (sdk a b : String) (options : List String) (changed : a ≠ b) :
    profileCurrent ⟨sdk, a, options⟩ ⟨sdk, b, options⟩ = false := by simp [profileCurrent, changed]

def staleModules (current : Bool) (production requested cached : List String) : List String :=
  if current then [] else (requested ++ cached).filter (fun m => !production.contains m)

theorem unchanged_options_no_clean (production requested cached : List String) :
    staleModules true production requested cached = [] := rfl

theorem production_never_cleaned (current : Bool) (production requested cached : List String)
    (m : String) (member : m ∈ production) :
    m ∉ staleModules current production requested cached := by
  cases current <;> simp [staleModules, member]

theorem stale_cached_unrequested_cleaned (production requested cached : List String)
    (m : String) (cachedMember : m ∈ cached) (notProduction : m ∉ production) :
    m ∈ staleModules false production requested cached := by
  simp [staleModules, cachedMember, notProduction]

-- An observed native counter is cumulative GGC allocation, never VM occupancy/RSS.
inductive AllocationScope where
  | gccGgc | schemeVm | resident
  deriving DecidableEq

def ggcValue (scope : AllocationScope) (totals : List Int) : Option Nat :=
  if scope == .gccGgc then
    match totals with
    | [n] => if 0 ≤ n then some n.toNat else none
    | _ => none
  else none

theorem gcc_exact_total (n : Nat) : ggcValue .gccGgc [Int.ofNat n] = some n := by simp [ggcValue]
theorem missing_total_rejected : ggcValue .gccGgc [] = none := rfl
theorem nested_passes_not_added (a b : Int) : ggcValue .gccGgc [a,b] = none := rfl
theorem vm_counter_not_promoted (totals : List Int) : ggcValue .schemeVm totals = none := rfl

def ggcComplete (expected reported failed changed errors : Nat) : Bool :=
  0 < expected && expected == reported && failed == 0 && changed == 0 && errors == 0

theorem changed_input_not_attributed (n reported failed errors : Nat) :
    ggcComplete n reported failed 1 errors = false := by simp [ggcComplete]
theorem partial_jobs_not_total (expected reported : Nat) (different : expected ≠ reported) :
    ggcComplete expected reported 0 0 0 = false := by simp [ggcComplete, different]

-- Normalized paths and decoded input roles are premises, not filesystem proofs.
def sourceAttributed (expected : String) (targets arguments : List String) : Bool :=
  targets == [expected] && arguments.contains expected

theorem attributed_source_is_unique (expected : String) (targets arguments : List String)
    (accepted : sourceAttributed expected targets arguments = true) :
    targets = [expected] ∧ expected ∈ arguments := by
  simpa [sourceAttributed] using accepted

def compilerInput (isC direct : Bool) : Bool := isC && direct

theorem metadata_only_is_not_compile (isC : Bool) : compilerInput isC false = false := by
  cases isC <;> rfl

-- Even eliminating an entire loading phase cannot eliminate independent compile work.
def preparationWall (loading compilation other : Nat) : Nat := loading + compilation + other

theorem compile_work_remains (loading compilation other : Nat) :
    preparationWall loading compilation other - loading = compilation + other := by
  simp [preparationWall]; omega

-- The containing process and normalized path matching are observed premises.
def uniqueParentInput (sameParent : Bool) (matchedInputs : Nat) : Bool :=
  sameParent && matchedInputs == 1

theorem unrelated_parent_rejected (matchedInputs : Nat) : uniqueParentInput false matchedInputs = false := by
  simp [uniqueParentInput]

theorem ambiguous_parent_input_rejected (same : Bool) (n : Nat) (notUnique : n ≠ 1) :
    uniqueParentInput same n = false := by simp [uniqueParentInput, notUnique]


-- Static C may be copied/renamed: bind observed content and producer order.
def producerEligible (success current ordered sameContent unique : Bool) : Bool :=
  success && current && ordered && sameContent && unique

theorem producer_admission_requires_every_link (a b c d e : Bool)
    (accepted : producerEligible a b c d e = true) :
    a = true ∧ b = true ∧ c = true ∧ d = true ∧ e = true := by
  simpa [producerEligible, Bool.and_eq_true, and_assoc] using accepted

def supportAdmitted (sameSources sameResources : Bool) : Bool := sameSources && sameResources

theorem changed_reference_resources_rejected (sources : Bool) :
    supportAdmitted sources false = false := by simp [supportAdmitted]

theorem changed_reference_sources_rejected (resources : Bool) :
    supportAdmitted false resources = false := by simp [supportAdmitted]

-- The pinned SDK counter includes live stack contribution. Unwinding can
-- decrease it without changing heap-event allocation or collecting garbage.
def netStackCounter (heap stack : Nat) : Nat := heap + stack

theorem stack_release_can_decrease_counter (heap stack released : Nat) (positive : 0 < released) :
    netStackCounter heap stack < netStackCounter heap (stack + released) := by
  simp only [netStackCounter]
  omega

def compilerSchemeSource : String :=
  ";; Existing SDK header policy; this limits C function size, not VM concurrency.\n" ++
  "(def gerbil-ascent-compiler-options '(\"-cc-options\" \"-D___SINGLE_HOST_LIMIT=512\"))\n"

def ggcPythonSource : String :=
  "    if len(totals) != 1 or type(totals[0]) is not int or totals[0] < 0:\n" ++
  "        raise ValueError('invalid GCC cumulative GGC total')\n"

def optionsSchemeSource : String :=
  "(def (artifact-compiler-options-current? file options)\n" ++
  "  (with-catch false\n" ++
  "    (lambda ()\n" ++
  "      (call-with-input-file file\n" ++
  "        (lambda (port)\n" ++
  "          (let (record (read port))\n" ++
  "            (and (eof-object? (read port))\n" ++
  "                 (equal? record (list \"ascent-compiler-options/v1\" (gerbil-home)\n" ++
  "                              (path-normalize (current-directory)) options)))))))))\n" ++
  "(def (artifact-record-compiler-options! file options)\n" ++
  "  (call-with-output-file [path: file truncate: #t]\n" ++
  "    (lambda (out)\n" ++
  "      (write (list \"ascent-compiler-options/v1\" (gerbil-home)\n" ++
  "                              (path-normalize (current-directory)) options) out)\n" ++
  "      (newline out))))\n"

def staleSchemeSource : String :=
  "(def (preparation-stale-compiler-modules current? production requested cached)\n" ++
  "  (if current? []\n" ++
  "    (filter (lambda (module) (not (member module production)))\n" ++
  "            (append requested cached))))\n"

def originPythonSource : String :=
  "    if actual != [expected] or expected not in arguments:\n" ++
  "        raise ValueError('GCC input attribution differs')\n"

def inputsPythonSource : String :=
  "def gcc_c_inputs(inputs, compiler_input_paths):\n" ++
  "    return [row for row in inputs if row['path'] in compiler_input_paths and Path(row['path']).suffix == '.c']\n"

def coveragePythonSource : String :=
  "def gcc_ggc_complete(expected, reported, failed, changed, errors):\n" ++
  "    return 0 < expected and expected == reported and failed == 0 and changed == 0 and errors == 0\n"

def quintSource : String :=
  "// Generated from CompilerCost.lean; formal CI checks exact source.\n" ++
  "module CompilerPolicy {\n" ++
  "  pure def producer_eligible(success: bool, current: bool, ordered: bool, same_content: bool, unique: bool): bool =\n" ++
  "    success and current and ordered and same_content and unique\n" ++
  "  pure def support_admitted(sources: bool, resources: bool): bool = sources and resources\n" ++
  "  pure def compiler_input(is_c: bool, direct: bool): bool = is_c and direct\n" ++
  "  pure def unique_parent_input(same: bool, matches: int): bool = same and matches == 1\n" ++
  "  pure def source_attributed(expected: int, targets: List[int], arguments: Set[int]): bool =\n" ++
  "    targets == [expected] and arguments.contains(expected)\n" ++
  "  pure def single_host(labels: int, limit: int): bool = limit == 0 or labels <= limit\n" ++
  "  pure def ggc_complete(expected: int, reported: int, failed: int, changed: int, errors: int): bool =\n" ++
  "    0 < expected and expected == reported and failed == 0 and changed == 0 and errors == 0\n" ++
  "  pure def stale_modules(current: bool, production: Set[int], requested: Set[int], cached: Set[int]): Set[int] =\n" ++
  "    if (current) Set() else requested.union(cached).exclude(production)\n" ++
  "}\n"

def parentPythonSource : String :=
  "# Paths are normalized by file_input; SDK code generation remains a premise.\ndef generated_scheme_input(helper, parent):\n    if helper.get('parent_gsc_observer') != str(parent.get('pid')):\n        return None\n    sources = gcc_c_inputs(helper['inputs'], helper.get('compiler_input_paths', []))\n    if len(sources) != 1:\n        return None\n    expected = str(Path(sources[0]['path']).with_suffix('.scm'))\n    matches = [item for item in parent['inputs'] if item['path'] == expected]\n    return matches[0] if len(matches) == 1 else None\n"

-- Cache identity includes SDK, compiler configuration and source inputs, while
-- the current observation controller still executes and admits those inputs.
def observedCacheIdentity (profile : Profile) (_controller : String) : Profile := profile

theorem observation_change_preserves_compiler_identity (profile : Profile) (a b : String) :
    observedCacheIdentity profile a = observedCacheIdentity profile b := rfl

-- Compatibility restores compiled resources; exact source/resource admission
-- still runs after restoring the current checkout. Runtime dispatch and the
-- observation controller do not change the compiler recipe.
def preparationCompatibilityInputs : List String :=
  ["build.ss", "build-modules.ss", "gerbil.pkg", "bindings",
   "t/harness/build.ss", "t/harness/artifact-admission.ss", "t/harness/library-spec.ss"]

theorem runtime_dispatch_not_compiler_recipe :
    "t/harness/test.ss" ∉ preparationCompatibilityInputs := by decide

theorem observation_workflow_not_compiler_recipe :
    ".github/workflows/build-cost.yml" ∉ preparationCompatibilityInputs := by decide

theorem cli_wrapper_not_compiler_recipe :
    "justfile" ∉ preparationCompatibilityInputs := by decide

def cacheInputsYamlSource : String :=
  "          compiler_inputs=\"$(git ls-files -s -- " ++ String.intercalate " " preparationCompatibilityInputs ++ " | sha256sum | cut -d ' ' -f 1)\"\n          printf 'compiler_inputs=%s\\n' \"$compiler_inputs\" >> \"$GITHUB_OUTPUT\"\n          source_inputs=\"$(git ls-files -s -- '*.ss' bindings/c gerbil.pkg justfile .github/workflows/build-cost.yml ':(exclude)manifest.ss' | sha256sum | cut -d ' ' -f 1)\"\n          printf 'source_inputs=%s\\n' \"$source_inputs\" >> \"$GITHUB_OUTPUT\"\n          echo 'source_bytes=${{ hashFiles('**/*.ss', 'bindings/c/**', '!manifest.ss', '!.gerbil/**', '!.ci/**', '!.cache/**', 'justfile', 'gerbil.pkg', '.github/workflows/build-cost.yml') }}' >> \"$GITHUB_OUTPUT\"\n"

def producerPythonSource : String :=
  "def producer_eligible(success, current, ordered, same_content, unique):\n    return success and current and ordered and same_content and unique\n"

-- Under the existing exclusive lane lock, skipping only the encoding of an
-- equal complete record preserves publication. Digest construction is eager.
def publishedCache (previous next : List String) : List String :=
  if previous == next then previous else next

theorem identical_cache_encoding_reuse (previous next : List String) :
    publishedCache previous next = next := by
  simp only [publishedCache]
  split <;> simp_all

def supportAdmissionSchemeSource : String :=
  "(def (artifact-support-admitted? sources recorded-sources resources recorded-resources)\n" ++
  "  (and (equal? (list-sort (lambda (a b) (string<? (car a) (car b))) (hash->list sources))\n" ++
  "               recorded-sources)\n" ++
  "       (equal? resources recorded-resources)))\n" ++
  "(def (artifact-record-support-cache! file sources library options selection modules (previous #f))\n" ++
  "  ;; The caller owns lane.lock. Recompute every resource digest after make;\n" ++
  "  ;; reuse only the encoding of an identical complete record, never its hashes.\n" ++
  "  (let ((next (list (artifact-support-profile options)\n" ++
  "                    (list-sort (lambda (a b) (string<? (car a) (car b))) (hash->list sources))\n" ++
  "                    (artifact-support-resources library) selection modules))\n" ++
  "        (pending (string-append file \".pending\")))\n" ++
  "    (if (and (equal? previous next) (file-exists? file))\n" ++
  "      (displayln \"BUILD-TEST-LIBRARY support-cache-write=0\")\n" ++
  "      (begin\n" ++
  "        (call-with-output-file [path: pending truncate: #t]\n" ++
  "          (lambda (port) (write next port) (newline port)))\n" ++
  "        (rename-file pending file #t)\n" ++
  "        (displayln \"BUILD-TEST-LIBRARY support-cache-write=1\")))))\n"


-- Restoring artifacts from another program is never execution authority.
-- Git restoration and hashing remain external premises; both guards run first.
def restoredProgramAdmitted (sameBytes cleanHead : Bool) : Bool := sameBytes && cleanHead

theorem stale_cache_cannot_admit_program (clean : Bool) :
    restoredProgramAdmitted false clean = false := by simp [restoredProgramAdmitted]

theorem dirty_checkout_cannot_admit_program (same : Bool) :
    restoredProgramAdmitted same false = false := by simp [restoredProgramAdmitted]

def restoreInputsYamlSource : String :=
  "          git diff --name-only HEAD -- '*.ss' bindings/c\n          git reset --hard HEAD\n          git clean -f -- '*.ss' bindings/c\n"

def cacheAdmissionYamlSource : String :=
  "          test \"$EXPECTED_SOURCE_BYTES\" = \"$RESTORED_SOURCE_BYTES\"\n          git diff --exit-code HEAD -- '*.ss' bindings/c gerbil.pkg justfile ':(exclude)manifest.ss'\n"


def cOutputTarget (isC flat : Bool) : Bool := isC && !flat

theorem other_codegen_target_not_c_output (flat : Bool) : cOutputTarget false flat = false := by
  cases flat <;> rfl

def nativeNodeCost (cost : Nat) (_inputEdges : List String) : Nat := cost

theorem link_edges_do_not_multiply_allocation (cost : Nat) (a b : List String) :
    nativeNodeCost cost a = nativeNodeCost cost b := rfl

def outputTargetPythonSource : String :=
  "def c_output_target(arguments):\n    return ('-target' not in arguments or arguments[arguments.index('-target') + 1] == 'C') and '-flat' not in arguments\n"

def jobAllocationPythonSource : String :=
  "def compiler_allocation_total(jobs):\n    return sum(job['gcc_ggc_bytes'] for job in jobs)\n"


def auditOrder (workOnly same : Bool) : List Bool :=
  if workOnly && same then [true] else [false, true, true, false]

theorem latency_controls_stay_abba (same : Bool) :
    auditOrder false same = [false, true, true, false] := by simp [auditOrder]

theorem distinct_program_controls_stay_abba (work : Bool) :
    auditOrder work false = [false, true, true, false] := by simp [auditOrder]

def auditOrderPythonSource : String :=
  "def control_order(work_only, baseline, candidate):\n    return ['candidate'] if work_only and baseline == candidate else ['baseline', 'candidate', 'candidate', 'baseline']\n"


def projectionReuse (current sameRoots complete : Bool) : Bool := current && sameRoots && complete

theorem changed_roots_do_not_skip_expansion (current complete : Bool) :
    projectionReuse current false complete = false := by simp [projectionReuse]

theorem incomplete_projection_not_reused (current same : Bool) :
    projectionReuse current same false = false := by simp [projectionReuse]

-- Hash membership agrees with the former list scan for arbitrary module lists,
-- including duplicate strings. Native hash equality remains a host premise.
def projectionIndex (modules : List String) : Std.HashSet String := .ofList modules

theorem projection_membership_exact (modules : List String) (module : String) :
    (projectionIndex modules).contains module = modules.contains module := by
  simp [projectionIndex, Std.HashSet.contains_ofList]

theorem projection_completeness_exact (modules required : List String) :
    required.all (fun m => (projectionIndex modules).contains m) =
      required.all (fun m => modules.contains m) := by
  simp only [projection_membership_exact]

-- Source operations, not allocator bytes or a collision/latency theorem.
def projectionIndexEntries (modules : List String) : Nat := modules.length
def projectionProbeRequests (required : List String) : Nat := required.length

def projectionCacheSchemeSource : String :=
  "(def (artifact-support-projection record selection required)\n" ++
  "  (and record (equal? selection (cadddr record))\n" ++
  "       (let* ((modules (car (cddddr record)))\n" ++
  "              (present (list->hash-table (map (lambda (module) (cons module #t)) modules))))\n" ++
  "         (and (andmap (lambda (module) (hash-key? present module)) required)\n" ++
  "              modules))))\n"


def orderedPublication (samePath disjoint unique : Bool) : Bool := samePath && disjoint && unique

theorem copied_candidates_do_not_gain_time_authority (disjoint unique : Bool) :
    orderedPublication false disjoint unique = false := by simp [orderedPublication]

theorem overlapping_writers_not_selected (same unique : Bool) :
    orderedPublication same false unique = false := by simp [orderedPublication]

def outputPublicationPythonSource : String :=
  "def ordered_publication_eligible(same_path, disjoint, unique_latest):\n    return same_path and disjoint and unique_latest\n"


def sourceCostCoverage (expected attributed : Nat) : Bool := expected == attributed

theorem missing_source_cost_not_complete (expected attributed : Nat) (different : expected ≠ attributed) :
    sourceCostCoverage expected attributed = false := by simp [sourceCostCoverage, different]

def sourceCoveragePythonSource : String :=
  "def source_cost_coverage(expected, attributed):\n    return expected == attributed\n"


def modulesCurrent (sources modules : List String) : Bool :=
  modules.all (fun name => sources.contains (name ++ ".ss"))

theorem foreign_singleton_module_rejected (sources : List String) (name : String)
    (unknown : name ++ ".ss" ∉ sources) : modulesCurrent sources [name] = false := by
  simp [modulesCurrent, unknown]

def modulesCurrentSchemeSource : String :=
  "(def (artifact-support-modules-current? sources modules)\n  (and (list? modules)\n       (andmap (lambda (module)\n                 (and (string? module) (hash-key? sources (string-append module \".ss\")))) modules)))\n"

-- Missing observation is not evidence of an empty SDK option list.
def ccOptionsObserved (options : Option String) : Bool := options.isSome

theorem missing_options_not_default : ccOptionsObserved none = false := rfl

theorem observed_empty_options_are_known : ccOptionsObserved (some "") = true := rfl

def ccObservedPythonSource : String :=
  "def cc_options_observed(options):\n    return isinstance(options, str)\n"

end Ascent.CompilerCost
#print axioms Ascent.CompilerCost.small_unit_unchanged
#print axioms Ascent.CompilerCost.oversized_unit_split
#print axioms Ascent.CompilerCost.changed_options_invalidate
#print axioms Ascent.CompilerCost.unchanged_options_no_clean
#print axioms Ascent.CompilerCost.production_never_cleaned
#print axioms Ascent.CompilerCost.stale_cached_unrequested_cleaned
#print axioms Ascent.CompilerCost.gcc_exact_total
#print axioms Ascent.CompilerCost.missing_total_rejected
#print axioms Ascent.CompilerCost.nested_passes_not_added
#print axioms Ascent.CompilerCost.vm_counter_not_promoted
#print axioms Ascent.CompilerCost.changed_input_not_attributed
#print axioms Ascent.CompilerCost.partial_jobs_not_total
#print axioms Ascent.CompilerCost.compile_work_remains

#print axioms Ascent.CompilerCost.changed_root_invalidate

#print axioms Ascent.CompilerCost.attributed_source_is_unique
#print axioms Ascent.CompilerCost.metadata_only_is_not_compile

#print axioms Ascent.CompilerCost.unrelated_parent_rejected
#print axioms Ascent.CompilerCost.ambiguous_parent_input_rejected

#print axioms Ascent.CompilerCost.observation_change_preserves_compiler_identity

#print axioms Ascent.CompilerCost.producer_admission_requires_every_link
#print axioms Ascent.CompilerCost.changed_reference_sources_rejected
#print axioms Ascent.CompilerCost.changed_reference_resources_rejected

#print axioms Ascent.CompilerCost.stack_release_can_decrease_counter

#print axioms Ascent.CompilerCost.stale_cache_cannot_admit_program
#print axioms Ascent.CompilerCost.dirty_checkout_cannot_admit_program

#print axioms Ascent.CompilerCost.other_codegen_target_not_c_output
#print axioms Ascent.CompilerCost.link_edges_do_not_multiply_allocation

#print axioms Ascent.CompilerCost.latency_controls_stay_abba
#print axioms Ascent.CompilerCost.distinct_program_controls_stay_abba

#print axioms Ascent.CompilerCost.changed_roots_do_not_skip_expansion
#print axioms Ascent.CompilerCost.incomplete_projection_not_reused

#print axioms Ascent.CompilerCost.copied_candidates_do_not_gain_time_authority
#print axioms Ascent.CompilerCost.overlapping_writers_not_selected

#print axioms Ascent.CompilerCost.missing_source_cost_not_complete

#print axioms Ascent.CompilerCost.foreign_singleton_module_rejected

#print axioms Ascent.CompilerCost.missing_options_not_default
#print axioms Ascent.CompilerCost.observed_empty_options_are_known

#print axioms Ascent.CompilerCost.projection_membership_exact
#print axioms Ascent.CompilerCost.projection_completeness_exact

#print axioms Ascent.CompilerCost.identical_cache_encoding_reuse

#print axioms Ascent.CompilerCost.runtime_dispatch_not_compiler_recipe
#print axioms Ascent.CompilerCost.observation_workflow_not_compiler_recipe
#print axioms Ascent.CompilerCost.cli_wrapper_not_compiler_recipe
