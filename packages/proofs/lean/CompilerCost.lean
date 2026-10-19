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
  "  pure def compiler_input(is_c: bool, direct: bool): bool = is_c and direct\n" ++
  "  pure def source_attributed(expected: int, targets: List[int], arguments: Set[int]): bool =\n" ++
  "    targets == [expected] and arguments.contains(expected)\n" ++
  "  pure def single_host(labels: int, limit: int): bool = limit == 0 or labels <= limit\n" ++
  "  pure def ggc_complete(expected: int, reported: int, failed: int, changed: int, errors: int): bool =\n" ++
  "    0 < expected and expected == reported and failed == 0 and changed == 0 and errors == 0\n" ++
  "  pure def stale_modules(current: bool, production: Set[int], requested: Set[int], cached: Set[int]): Set[int] =\n" ++
  "    if (current) Set() else requested.union(cached).exclude(production)\n" ++
  "}\n"

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
