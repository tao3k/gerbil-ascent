-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DescriptorKernel

/-! Rust patterns intentionally erase fresh/bound tags. Decode them using the
checker's own preceding symbol map, never the compiler's map. Constructor
mismatches remain rejected. `Value` is the result of the Rust scalar accessor;
its faithfulness and finite-map operations are the primitive boundary. -/
namespace Ascent.RustDescriptor
open AtomicBinding PositiveSlots DescriptorStream DescriptorKernel

inductive Pattern (Value : Type) where
  | variable (slot : Nat)
  | literal (value : Value)
  | wildcard
  deriving DecidableEq

def erase : Action Value → Pattern Value
  | .fresh slot | .bound slot => .variable slot
  | .literal value => .literal value
  | .wildcard => .wildcard

def decodePattern (term : Term Value) (pattern : Pattern Value) (symbols : Symbols) : EncodedAction Value :=
  match term, pattern with
  | .variable name, .variable slot =>
    if (symbols.find name).isSome then .bound slot else .fresh slot
  | .literal _, .literal value => .literal value
  | .wildcard, .wildcard => .wildcard
  | _, _ => .invalid

def step [DecidableEq Value] (code : Code) (head : Bool) (term : Term Value)
    (pattern : Pattern Value) (symbols : Symbols) : Option Symbols :=
  executeOne code head term (decodePattern term pattern symbols) symbols

theorem step_exact [DecidableEq Value] (term : Term Value) (pattern : Pattern Value)
    (symbols : Symbols) :
    step variableCode false term pattern symbols =
      if pattern = erase (lowerMap term symbols).1 then some (lowerMap term symbols).2 else none := by
  cases term with
  | literal value => cases pattern <;>
      simp [step, executeOne, decodePattern, decode, checkOne, lowerMap, erase]
  | wildcard => cases pattern <;>
      simp [step, executeOne, decodePattern, decode, checkOne, lowerMap, erase]
  | «variable» name =>
    cases found : symbols.find name <;> cases pattern <;>
      simp [step, executeOne, decodePattern, applyMove, DescriptorKernel.run, variableCode, test,
        lowerMap, erase, found, beq_iff_eq]
    all_goals split <;> simp_all
    all_goals split at * <;> simp_all

/-- Head descriptors may read existing slots, but must never create a slot. -/
theorem head_exact [DecidableEq Value] (name : Nat) (pattern : Pattern Value) (symbols : Symbols) :
    step variableCode true (.variable name) pattern symbols =
      match symbols.find name, pattern with
      | some expected, .variable actual => if actual = expected then some symbols else none
      | _, _ => none := by
  cases found : symbols.find name <;> cases pattern <;>
    simp [step, executeOne, decodePattern, applyMove, DescriptorKernel.run, variableCode,
      test, found, beq_iff_eq]
  all_goals split <;> simp_all
  all_goals split at * <;> simp_all

def execute [DecidableEq Value] (code : Code) (head : Bool) :
    List (Term Value) → List (Pattern Value) → Symbols → Option Symbols
  | [], [], symbols => some symbols
  | term :: terms, pattern :: patterns, symbols =>
      (step code head term pattern symbols).bind (fun next => execute code head terms patterns next)
  | _, _, _ => none

theorem stream_exact [DecidableEq Value] (terms : List (Term Value))
    (patterns : List (Pattern Value)) (names : List Nat) :
    execute variableCode false terms patterns (canonical names) =
      if patterns = ((compile terms names).1.map erase)
      then some (canonical (compile terms names).2) else none := by
  induction terms generalizing patterns names with
  | nil => cases patterns <;> simp [execute, compile]
  | cons term terms ih =>
    cases patterns with
    | nil => simp [execute, compile]
    | cons pattern patterns =>
      simp only [execute, step_exact, lower_map_refines]
      by_cases same : pattern = erase (lower term names).1
      · simp [same, ih, compile]
      · simp [same, compile]

end Ascent.RustDescriptor
