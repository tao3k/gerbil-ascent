-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
import Lean.Data.Json
import PreparationWork
import CompilerCost
import LookupCost
import ClosedDslLowering

/-! Executable control definitions shared by Scheme and Rust. The checked-in
renderings are regenerated and compared during formal CI. This removes the
previous handwritten copies of these decisions; it does not verify the host
compiler, hash implementation, mailbox or memory model. -/
namespace Ascent.ExecutionPolicy

inductive Number where
  | variable (name : String)
  | zero
  deriving Repr, DecidableEq
instance : Coe String Number := ⟨Number.variable⟩
def Number.value (numbers : String → Nat) : Number → Nat
  | .variable name => numbers name
  | .zero => 0

inductive Predicate where
  | flag (name : String)
  | less (left right : Number)
  | equal (left right : Number)
  | both (left right : Predicate)
  | either (left right : Predicate)
  | negate (value : Predicate)
  deriving Repr, DecidableEq

def eval (numbers : String → Nat) (flags : String → Bool) : Predicate → Bool
  | .flag name => flags name
  | .less left right => left.value numbers < right.value numbers
  | .equal left right => left.value numbers == right.value numbers
  | .both left right => eval numbers flags left && eval numbers flags right
  | .either left right => eval numbers flags left || eval numbers flags right
  | .negate value => !(eval numbers flags value)

def oldLane : Predicate := .both (.flag "has_pivot")
  (.both (.flag "set_relation") (.less "position" "pivot"))
def deltaLane : Predicate := .both (.flag "has_pivot") (.equal "position" "pivot")
def readableKey : Predicate := .either (.flag "literal")
  (.both (.flag "bound") (.less "slot" "prior"))
def actorComplete : Predicate := .both (.negate (.flag "failed")) (.flag "finished")
def componentReady : Predicate := .equal "remaining" .zero
def roundContinue : Predicate := .both (.flag "healthy") (.less .zero "admitted")
def joinedRound : Predicate := .both (.negate (.flag "failed"))
  (.both (.flag "joined") (.both (.equal "assigned" "completed")
    (.both (.equal "active" .zero) (.equal "pending" .zero))))

theorem old_lane_exact (numbers : String → Nat) (flags : String → Bool) :
    eval numbers flags oldLane = true ↔
      flags "has_pivot" = true ∧ flags "set_relation" = true ∧
      numbers "position" < numbers "pivot" := by
  change (flags "has_pivot" && (flags "set_relation" &&
    decide (numbers "position" < numbers "pivot"))) = true ↔ _
  simp

theorem delta_lane_exact (numbers : String → Nat) (flags : String → Bool) :
    eval numbers flags deltaLane = true ↔
      flags "has_pivot" = true ∧ numbers "position" = numbers "pivot" := by
  simp [eval, deltaLane, Number.value]

theorem lane_partition (numbers : String → Nat) (flags : String → Bool)
    (present : flags "has_pivot" = true) (sets : flags "set_relation" = true) :
    (eval numbers flags oldLane = true ∧ eval numbers flags deltaLane = false) ∨
    (eval numbers flags oldLane = false ∧ eval numbers flags deltaLane = true) ∨
    (eval numbers flags oldLane = false ∧ eval numbers flags deltaLane = false) := by
  simp only [eval, Number.value, oldLane, deltaLane, present, sets, Bool.true_and]
  by_cases less : numbers "position" < numbers "pivot"
  · simp [less, Nat.ne_of_lt less]
  · by_cases same : numbers "position" = numbers "pivot" <;> simp [less, same]

theorem no_failed_completion (numbers : String → Nat) (flags : String → Bool)
    (failed : flags "failed" = true) : eval numbers flags actorComplete = false := by
  simp [eval, actorComplete, failed]

theorem no_refused_continuation (numbers : String → Nat) (flags : String → Bool)
    (refused : flags "healthy" = false) : eval numbers flags roundContinue = false := by
  simp [eval, roundContinue, refused]

theorem key_before_row (numbers : String → Nat) (flags : String → Bool)
    (notLiteral : flags "literal" = false) (accepted : eval numbers flags readableKey = true) :
    flags "bound" = true ∧ numbers "slot" < numbers "prior" := by
  change (flags "literal" || (flags "bound" &&
    decide (numbers "slot" < numbers "prior"))) = true at accepted
  simpa [notLiteral] using accepted

theorem joined_round_exact (numbers : String → Nat) (flags : String → Bool) :
    eval numbers flags joinedRound = true ↔
      flags "failed" = false ∧ flags "joined" = true ∧
      numbers "assigned" = numbers "completed" ∧
      numbers "active" = 0 ∧ numbers "pending" = 0 := by
  simp [eval, joinedRound, Number.value]

structure Definition where
  name : String
  numbers : List String
  flags : List String
  body : Predicate

def definitions : List Definition := [
  ⟨"old_lane", ["position", "pivot"], ["has_pivot", "set_relation"], oldLane⟩,
  ⟨"delta_lane", ["position", "pivot"], ["has_pivot"], deltaLane⟩,
  ⟨"readable_key", ["slot", "prior"], ["literal", "bound"], readableKey⟩,
  ⟨"actor_complete", [], ["failed", "finished"], actorComplete⟩,
  ⟨"component_ready", ["remaining"], [], componentReady⟩,
  ⟨"round_continue", ["admitted"], ["healthy"], roundContinue⟩,
  ⟨"joined_round", ["assigned", "completed", "active", "pending"], ["failed", "joined"], joinedRound⟩]

def schemeName (name : String) : String := String.ofList (name.toList.map fun c => if c == '_' then '-' else c)
def boundName (name : String) : String := "policy-" ++ schemeName name
def schemeNumber : Number → String
  | .variable name => boundName name
  | .zero => "0"
def infixNumber : Number → String
  | .variable name => name
  | .zero => "0"
def scheme : Predicate → String
  | .flag name => boundName name
  | .less left right => s!"(< {schemeNumber left} {schemeNumber right})"
  | .equal left right => s!"(= {schemeNumber left} {schemeNumber right})"
  | .both left right => s!"(and {scheme left} {scheme right})"
  | .either left right => s!"(or {scheme left} {scheme right})"
  | .negate value => s!"(not {scheme value})"
def rust : Predicate → String
  | .flag name => name
  | .less left right => s!"({infixNumber left} < {infixNumber right})"
  | .equal left right => s!"({infixNumber left} == {infixNumber right})"
  | .both left right => s!"({rust left} && {rust right})"
  | .either left right => s!"({rust left} || {rust right})"
  | .negate value => s!"(!{rust value})"

def schemeSource : String :=
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Generated by ExecutionPolicy.lean; edit the proved definitions there.\n" ++
  "(export " ++ String.intercalate " " (definitions.map fun d => "gerbil-ascent-" ++ schemeName d.name) ++ ")\n" ++
  String.join (definitions.map fun d =>
    let parameters := d.numbers ++ d.flags
    let bindings := parameters.map (fun name => s!"({boundName name} {schemeName name})")
    s!"(defrule (gerbil-ascent-{schemeName d.name} {String.intercalate " " (parameters.map schemeName)})\n  (let* ({String.intercalate " " bindings})\n    {scheme d.body}))\n")

def rustSource : String :=
  "// SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n// Generated by ExecutionPolicy.lean; edit the proved definitions there.\n// Some policies belong only to the Scheme owner.\n#![allow(dead_code, unused_parens)]\n" ++
  String.join (definitions.map fun d =>
    let parameters := d.numbers.map (· ++ ": usize") ++ d.flags.map (· ++ ": bool")
    s!"#[rustfmt::skip]\n#[inline]\npub(crate) fn {d.name}({String.intercalate ", " parameters}) -> bool \{\n    {rust d.body}\n}\n")

def quint : Predicate → String
  | .flag name => name
  | .less left right => s!"({infixNumber left} < {infixNumber right})"
  | .equal left right => s!"({infixNumber left} == {infixNumber right})"
  | .both left right => s!"({quint left} and {quint right})"
  | .either left right => s!"({quint left} or {quint right})"
  | .negate value => s!"not({quint value})"

def quintSource : String :=
  "// SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n// Generated by ExecutionPolicy.lean; edit the proved definitions there.\nmodule ExecutionPolicy {\n" ++
  String.join (definitions.map fun d =>
    let parameters := d.numbers.map (· ++ ": int") ++ d.flags.map (· ++ ": bool")
    s!"  pure def {d.name}({String.intercalate ", " parameters}): bool = {quint d.body}\n") ++ "}\n"

end Ascent.ExecutionPolicy

/-! The executable admission decision, not a model of elapsed-time prediction.
Nanosecond totals are observations. Missing phase-cost observations and unresolved
negative controls prevent admission even when a later observation is faster.
The existing predicate AST is rendered into the actual Python and Quint code.
Host timing, process attribution and compiler implementations remain boundaries. -/
namespace Ascent.PreparationPolicy
open Ascent.ExecutionPolicy

def nonRegression : Predicate := .negate (.less "baseline_ns" "candidate_ns")
def latchFailure : Predicate := .either (.flag "prior_failure") (.flag "new_failure")
def admission : Predicate := .both (.flag "matched")
  (.both (.flag "complete") (.both (.flag "cost_accounted")
    (.both (.equal "warm_rebuilds" .zero)
      (.both (.equal "unresolved" .zero) nonRegression))))

theorem non_regression_exact (numbers : String → Nat) (flags : String → Bool) :
    eval numbers flags nonRegression = true ↔ numbers "candidate_ns" ≤ numbers "baseline_ns" := by
  by_cases h : numbers "baseline_ns" < numbers "candidate_ns"
  · have denied := Nat.not_le_of_gt h
    simp [nonRegression, eval, Number.value, h, denied]
  · have allowed := Nat.le_of_not_gt h
    simp [nonRegression, eval, Number.value, h, allowed]

theorem regression_rejected (numbers : String → Nat) (flags : String → Bool)
    (worse : numbers "baseline_ns" < numbers "candidate_ns") :
    eval numbers flags admission = false := by
  simp [admission, nonRegression, eval, Number.value, worse]

theorem unresolved_rejected (numbers : String → Nat) (flags : String → Bool)
    (pending : numbers "unresolved" ≠ 0) : eval numbers flags admission = false := by
  simp [admission, eval, Number.value, pending]

theorem faster_does_not_clear_failure (numbers : String → Nat) (flags : String → Bool)
    (prior : flags "prior_failure" = true) : eval numbers flags latchFailure = true := by
  simp [latchFailure, eval, prior]

theorem accepted_current_complete_accounted (numbers : String → Nat) (flags : String → Bool)
    (accepted : eval numbers flags admission = true) :
    flags "matched" = true ∧ flags "complete" = true ∧ flags "cost_accounted" = true ∧
    numbers "warm_rebuilds" = 0 ∧ numbers "unresolved" = 0 ∧
    numbers "candidate_ns" ≤ numbers "baseline_ns" := by
  by_cases h : numbers "baseline_ns" < numbers "candidate_ns"
  · simp [admission, nonRegression, eval, Number.value, h] at accepted
  · have allowed := Nat.le_of_not_gt h
    simpa [admission, nonRegression, eval, Number.value, h, allowed] using accepted


def failedAfter (prior : Bool) : List Bool → Bool
  | [] => prior
  | next :: rest => failedAfter (prior || next) rest

theorem arbitrary_later_observations_preserve_failure (observations : List Bool) :
    failedAfter true observations = true := by
  induction observations with
  | nil => rfl
  | cons next rest ih => simpa [failedAfter] using ih


-- The actual collector uses this decision for both GSC and SDK helper records.
-- Blob decoding and observer coverage are still host-side proof obligations.
def observationComplete : Predicate :=
  .both (.flag "observer_ran")
    (.both (.equal "failed_jobs" .zero)
      (.both (.equal "changed_inputs" .zero) (.equal "negative_allocations" .zero)))

theorem observation_complete_exact (numbers : String → Nat) (flags : String → Bool) :
    eval numbers flags observationComplete = true ↔
      flags "observer_ran" = true ∧ numbers "failed_jobs" = 0 ∧
      numbers "changed_inputs" = 0 ∧ numbers "negative_allocations" = 0 := by
  simp [observationComplete, eval, Number.value]

def definitions : List Definition := [
  ⟨"preparation_observation_complete", ["failed_jobs", "changed_inputs", "negative_allocations"],
     ["observer_ran"], observationComplete⟩,
  ⟨"preparation_non_regression", ["baseline_ns", "candidate_ns"], [], nonRegression⟩,
  ⟨"preparation_latch_failure", [], ["prior_failure", "new_failure"], latchFailure⟩,
  ⟨"preparation_admitted", ["baseline_ns", "candidate_ns", "warm_rebuilds", "unresolved"],
     ["matched", "complete", "cost_accounted"], admission⟩]

def pythonNumber : Number → String
  | .zero => "0"
  | .variable name => name

def python : Predicate → String
  | .flag name => name
  | .less left right => s!"({pythonNumber left} < {pythonNumber right})"
  | .equal left right => s!"({pythonNumber left} == {pythonNumber right})"
  | .both left right => s!"({python left} and {python right})"
  | .either left right => s!"({python left} or {python right})"
  | .negate value => s!"(not {python value})"

def pythonSource : String :=
  "# SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n" ++
  "# SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n" ++
  "# Generated from ExecutionPolicy.lean (PreparationPolicy); formal CI checks exact rendering.\n" ++
  String.join (definitions.map fun d =>
    s!"\ndef {d.name}({String.intercalate ", " (d.numbers ++ d.flags)}):\n    return {python d.body}\n")

def quintSource : String :=
  "// SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n" ++
  "// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n" ++
  "// Generated from ExecutionPolicy.lean (PreparationPolicy); formal CI checks exact rendering.\nmodule PreparationPolicy {\n" ++
  String.join (definitions.map fun d =>
    let params := d.numbers.map (fun n => n ++ ": int") ++ d.flags.map (fun n => n ++ ": bool")
    s!"  pure def {d.name}({String.intercalate ", " params}): bool = {Ascent.ExecutionPolicy.quint d.body}\n") ++ "}\n"
end Ascent.PreparationPolicy

/-! Actual upstream archive event decoding and receipt admission. The Rust
consumer and Quint protocol import these exact generated decisions. Compiler
operation durations are worker observations, not a serial latency prediction. -/
namespace Ascent.ArchivePolicy
open Ascent.ExecutionPolicy

def cacheLevels : Nat := 4
def cacheNamespace : String := "ascent-program-v1"
def sharedTarget (path : List String) : List String := (path.reverse.drop cacheLevels).reverse

theorem profiles_select_same_target (target : List String) (profile package otherProfile otherPackage : String) :
    sharedTarget (target ++ [profile, "build", package, "out"]) =
      sharedTarget (target ++ [otherProfile, "build", otherPackage, "out"]) := by
  simp [sharedTarget, cacheLevels, List.reverse_append]

def rules : List (String × Bool × Bool × Nat) :=
  [("start", false, false, 0), ("start", false, true, 0),
   ("complete", true, false, 1), ("complete", true, true, 1),
   ("cached", false, false, 2), ("cached", false, true, 2),
   ("failed", true, false, 3), ("failed", true, true, 3),
   ("complete", false, true, 4)]

def decode (state : String) (timed plan : Bool) : Option Nat :=
  (rules.find? (fun r => r.1 == state && r.2.1 == timed && r.2.2.1 == plan)).map (·.2.2.2)

def decodePhase (state : String) (timed : Bool) (phase : String) : Option Nat :=
  decode state timed (phase == "program-plan")

theorem phase_decoder_exact (state : String) (timed : Bool) (phase : String) :
    decodePhase state timed phase = decode state timed (phase == "program-plan") := rfl

theorem cached_is_not_compiled (plan : Bool) : decode "cached" false plan = some 2 := by
  cases plan <;> decide

theorem untimed_worker_complete_rejected : decode "complete" false false = none := by decide

theorem unknown_event_rejected (timed plan : Bool) : decode "unknown" timed plan = none := by
  cases timed <;> cases plan <;> decide

def compilationUnits (phase : String) (kind : Nat) : Nat :=
  if phase == "native-object" && kind == 0 then 1 else 0

theorem cache_hit_has_no_compilation (phase : String) : compilationUnits phase 2 = 0 := by
  simp [compilationUnits]

theorem native_start_has_one_compilation : compilationUnits "native-object" 0 = 1 := by decide

def admission : Predicate :=
  .both (.flag "builder_ok") (.both (.flag "graph_ok")
    (.both (.equal "starts" "completed") (.both (.equal "pending" .zero)
      (.both (.equal "failed" .zero) (.both (.equal "invalid" .zero)
        (.both (.equal "changed" .zero) (.less .zero "sources")))))))

theorem complete_exact (numbers : String → Nat) (flags : String → Bool) :
    eval numbers flags admission = true ↔
      flags "builder_ok" = true ∧ flags "graph_ok" = true ∧
      numbers "starts" = numbers "completed" ∧ numbers "pending" = 0 ∧
      numbers "failed" = 0 ∧ numbers "invalid" = 0 ∧ numbers "changed" = 0 ∧
      0 < numbers "sources" := by
  simp [admission, eval, Number.value]
  intro _ _ _ _ _ _ _
  exact ⟨of_decide_eq_true, fun h => decide_eq_true h⟩

theorem changed_source_rejected (numbers : String → Nat) (flags : String → Bool)
    (changed : numbers "changed" ≠ 0) : eval numbers flags admission = false := by
  simp [admission, eval, Number.value, changed]

def fields := ["starts", "completed", "pending", "failed", "invalid", "changed", "sources"]
def flags := ["builder_ok", "graph_ok"]
def number : Number → String
  | .zero => "0"
  | .variable name => "m." ++ name

def rustBody : Predicate → String
  | .flag name => "m." ++ name
  | .less a b => number a ++ " < " ++ number b
  | .equal a b => number a ++ " == " ++ number b
  | .both a b => rustBody a ++ " && " ++ rustBody b
  | .either a b => "(" ++ rustBody a ++ " || " ++ rustBody b ++ ")"
  | .negate a => "!(" ++ rustBody a ++ ")"

def rustSource : String :=
  "// Generated from ExecutionPolicy.lean (ArchivePolicy); formal CI checks exact source.\n" ++
  s!"pub const CACHE_PARENT_LEVELS: usize = {cacheLevels};\npub const CACHE_NAMESPACE: &str = \"{cacheNamespace}\";\n" ++
  "#[derive(Default)]\npub struct Metrics {\n" ++
  String.join (fields.map (fun f => s!"    pub {f}: usize,\n")) ++
  String.join (flags.map (fun f => s!"    pub {f}: bool,\n")) ++ "}\n" ++
  "#[rustfmt::skip]\npub fn decode(state: &str, timed: bool, phase: &str) -> Option<usize> {\n    match (state, timed, phase == \"program-plan\") {\n" ++
  String.join ((rules.map (·.2.2.2)).eraseDups.map (fun kind =>
    let members := rules.filter (fun r => r.2.2.2 == kind)
    let patterns := (members.map (fun r => (r.1, r.2.1))).eraseDups.map (fun (state, timed) =>
      let plans := (members.filter (fun r => r.1 == state && r.2.1 == timed)).map (·.2.2.1)
      let pattern := if plans.contains false && plans.contains true then "_"
        else String.intercalate " | " (plans.map (fun p => s!"{p}"))
      s!"(\"{state}\", {timed}, {pattern})")
    s!"        {String.intercalate " | " patterns} => Some({kind}),\n")) ++
  "        _ => None,\n    }\n}\n#[rustfmt::skip]\npub fn compilation_units(phase: &str, kind: usize) -> usize {\n    usize::from(phase == \"native-object\" && kind == 0)\n}\n#[rustfmt::skip]\npub fn complete(m: &Metrics) -> bool {\n    " ++ rustBody admission ++ "\n}\n"

def quintSource : String :=
  "// Generated from ExecutionPolicy.lean (ArchivePolicy); formal CI checks exact source.\nmodule ArchivePolicy {\n" ++
  "  pure def archive_complete(" ++ String.intercalate ", "
    (fields.map (· ++ ": int") ++ flags.map (· ++ ": bool")) ++ "): bool = " ++
    Ascent.ExecutionPolicy.quint admission ++ "\n}\n"

def ciSource : String :=
  "      - name: Restore compiler-owned archive work across Cargo configurations\n        uses: actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0\n        with:\n          path: rust/target/" ++ cacheNamespace ++
  "\n          # No source-different fallback; the upstream builder still checks every object fingerprint.\n          key: " ++ cacheNamespace ++
  "-${{ runner.os }}-${{ runner.arch }}-${{ steps.capacity.outputs.toolchain }}-${{ hashFiles('**/*.ss', 'rust/Cargo.toml', 'rust/Cargo.lock', 'rust/ascent-scheme/build.rs', 'rust/ascent-build/**', 'bindings/**', 'gerbil.pkg', '.github/workflows/ci.yml', '!manifest.ss', '!.gerbil/**', '!.ci/**', '!.cache/**', '!rust/target/**', '!python/src/ascent/_sources/**') }}\n"

end Ascent.ArchivePolicy

def renderedSource (name : String) : IO String := do
  match name with
  | "archive-rust" => pure Ascent.ArchivePolicy.rustSource
  | "archive-cache" => pure Ascent.ArchivePolicy.ciSource
  | "archive-quint" => pure Ascent.ArchivePolicy.quintSource
  | "scheme" => pure Ascent.ExecutionPolicy.schemeSource
  | "rust" => pure Ascent.ExecutionPolicy.rustSource
  | "quint" => pure Ascent.ExecutionPolicy.quintSource
  | "preparation-python" => pure Ascent.PreparationPolicy.pythonSource
  | "preparation-quint" => pure Ascent.PreparationPolicy.quintSource
  | "preparation-selection" => pure Ascent.PreparationWork.selectionSchemeSource
  | "preparation-interface-quint" => pure Ascent.PreparationWork.interfacesQuintSource
  | "preparation-interfaces" => pure Ascent.PreparationWork.interfacesSchemeSource
  | "lookup-materialization" => pure Ascent.LookupCost.materializationSchemeSource
  | "lookup-admission" => pure Ascent.LookupCost.admissionSchemeSource
  | "lookup-study-profile" => pure Ascent.LookupCost.studyProfileSchemeSource
  | "preparation-cc-observed" => pure Ascent.CompilerCost.ccObservedPythonSource
  | "preparation-compiler" => pure Ascent.CompilerCost.compilerSchemeSource
  | "preparation-options" => pure Ascent.CompilerCost.optionsSchemeSource
  | "compiler-quint" => pure Ascent.CompilerCost.quintSource
  | "preparation-stale" => pure Ascent.CompilerCost.staleSchemeSource
  | "preparation-coverage" => pure Ascent.CompilerCost.coveragePythonSource
  | "preparation-ggc" => pure Ascent.CompilerCost.ggcPythonSource
  | "preparation-restore-inputs" => pure Ascent.CompilerCost.restoreInputsYamlSource
  | "preparation-cache-admission" => pure Ascent.CompilerCost.cacheAdmissionYamlSource
  | "preparation-cache-inputs" => pure Ascent.CompilerCost.cacheInputsYamlSource
  | "preparation-producer" => pure Ascent.CompilerCost.producerPythonSource
  | "preparation-support-admission" => pure Ascent.CompilerCost.supportAdmissionSchemeSource
  | "preparation-output-target" => pure Ascent.CompilerCost.outputTargetPythonSource
  | "preparation-job-allocation" => pure Ascent.CompilerCost.jobAllocationPythonSource
  | "preparation-audit-order" => pure Ascent.CompilerCost.auditOrderPythonSource
  | "preparation-projection-cache" => pure Ascent.CompilerCost.projectionCacheSchemeSource
  | "preparation-output-publication" => pure Ascent.CompilerCost.outputPublicationPythonSource
  | "preparation-source-coverage" => pure Ascent.CompilerCost.sourceCoveragePythonSource
  | "preparation-modules-current" => pure Ascent.CompilerCost.modulesCurrentSchemeSource
  | "preparation-parent" => pure Ascent.CompilerCost.parentPythonSource
  | "preparation-origin" => pure Ascent.CompilerCost.originPythonSource
  | "preparation-inputs" => pure Ascent.CompilerCost.inputsPythonSource
  | "preparation-import" => pure Ascent.PreparationWork.inventoryImportSchemeSource
  | "preparation-source" => pure Ascent.PreparationWork.sourceSchemeSource
  | "preparation-cargo-cache" => pure Ascent.PreparationWork.cargoCacheSchemeSource
  | "preparation-roots" => pure Ascent.PreparationWork.rootsSchemeSource
  | "preparation-support" => pure Ascent.PreparationWork.supportQuintSource
  | "preparation-batch-width" => pure Ascent.PreparationWork.batchWidthPythonSource
  | "snapshot" => pure Ascent.ClosedDslLowering.snapshotSchemeSource
  | "snapshot-quint" => pure Ascent.ClosedDslLowering.snapshotQuintSource
  | "dsl-select" => pure Ascent.ClosedDslLowering.selectorSchemeSource
  | "dsl-root" => pure Ascent.ClosedDslLowering.rootSchemeSource
  | "dsl-owned" => pure Ascent.ClosedDslLowering.ownedMacroSchemeSource
  | "dsl-workload" => pure Ascent.ClosedDslLowering.workloadSchemeSource
  | "preparation-groups" => pure Ascent.PreparationWork.groupsSchemeSource
  | "preparation-heap" => pure Ascent.PreparationWork.heapRecipeSource
  | "preparation-runner" => pure Ascent.PreparationWork.runnerRecipeSource
  | _ => throw (IO.userError "expected scheme, rust, quint, preparation-python, preparation-quint, preparation-selection, preparation-import, preparation-source or preparation-runner")


def main (args : List String) : IO Unit := do
  match args with
  | "batch" :: names =>
      let rows ← names.mapM fun name => do
        let source ← renderedSource name
        pure (Lean.Json.arr #[Lean.Json.str name, Lean.Json.str source])
      IO.println ((Lean.Json.arr rows.toArray).compress)
  | [name] => IO.print (← renderedSource name)
  | _ => throw (IO.userError "expected one source rendering or batch followed by source names")
