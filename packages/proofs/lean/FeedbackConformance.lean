-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ExecutionFeedback
import Lean

namespace Ascent.FeedbackConformance
def bit (id place : Nat) : Bool := (id / place) % 2 == 1
def actual (id : Nat) := id % 4
def expected (id : Nat) := (id / 4) % 4
def qualified (id : Nat) : Bool :=
  bit id 16 && bit id 32 &&
    (!bit id 64 || (bit id 128 && bit id 256 && bit id 512))
def grade (id : Nat) : List Nat :=
  if qualified id then
    let missing := Nat.land (expected id) (3 - actual id)
    let extra := Nat.land (actual id) (3 - expected id)
    [id, if missing == 0 && extra == 0 then 1 else 2, missing, extra]
  else [id, 0, 0, 0]
def rows (mask : Nat) (row : Fin 2) : Prop := bit mask (row.val + 1) = true

-- Kernel-checked finite correspondence with the extensional relation law.
-- No native_decide or new axioms; this proves only the stated finite domain.
set_option maxRecDepth 4096 in
theorem finite_match : ∀ id : Fin 1024,
    (grade id.val)[1]? = some 1 ↔
      qualified id.val = true ∧ ExecutionFeedback.Exact (rows (actual id.val)) (rows (expected id.val)) := by
  unfold ExecutionFeedback.Exact rows
  decide

def observation (id index : Nat) (row : Fin 2) : Prop :=
  bit ((grade id).getD index 0) (row.val + 1) = true

set_option maxRecDepth 4096 in
theorem finite_differences : ∀ id : Fin 1024, qualified id.val = true → ∀ row : Fin 2,
    (observation id.val 2 row ↔ ExecutionFeedback.Missing (rows (actual id.val)) (rows (expected id.val)) row) ∧
    (observation id.val 3 row ↔ ExecutionFeedback.Extra (rows (actual id.val)) (rows (expected id.val)) row) := by
  unfold observation ExecutionFeedback.Missing ExecutionFeedback.Extra rows
  decide

set_option maxRecDepth 4096 in
theorem finite_refusal : ∀ id : Fin 1024, qualified id.val = false →
    grade id.val = [id.val, 0, 0, 0] := by
  decide

def corpus : List (List Nat) := (List.range 1024).map grade
end Ascent.FeedbackConformance

def main (args : List String) : IO Unit := do
  unless args.length == 2 do
    throw (IO.userError "expected current Quint output and frozen corpus paths")
  let expected := Lean.toJson Ascent.FeedbackConformance.corpus
  for path in args do
    let text ← IO.FS.readFile path
    let parsed ← match Lean.Json.parse text with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"invalid corpus {path}: {message}")
    unless parsed == expected do
      throw (IO.userError s!"feedback conformance differs from Lean executable contract: {path}")
  IO.println "FEEDBACK-CONFORMANCE-LEAN-OK cases=1024"
