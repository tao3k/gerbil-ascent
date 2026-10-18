-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

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

def main (args : List String) : IO Unit := do
  match args with
  | ["scheme"] => IO.print Ascent.ExecutionPolicy.schemeSource
  | ["rust"] => IO.print Ascent.ExecutionPolicy.rustSource
  | ["quint"] => IO.print Ascent.ExecutionPolicy.quintSource
  | _ => throw (IO.userError "expected scheme, rust or quint")
