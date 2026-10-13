-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
/-! Trajectory observation semantics. Tokens are supplied by a trusted provider
adapter and correctness by an independent grader. These theorems neither prove
the grader nor reconstruct hidden model reasoning. -/
namespace Ascent.Trajectory
structure Ledger where
  generation : Nat := 0
  cost : Nat := 0
  first : Option Nat := none
  usageKnown : Bool := true
  referenceGeneration : Option Nat := none
  consumptionGeneration : Option Nat := none
  deriving DecidableEq, Repr

def call (s : Ledger) (tokens : Nat) : Ledger := { s with cost := s.cost + tokens }
def unknownCall (s : Ledger) : Ledger := { s with usageKnown := false }
def verify (s : Ledger) : Ledger :=
  { s with first := match s.first with | none => some s.cost | some n => some n }
def evidence (s : Ledger) : Ledger := { s with referenceGeneration := some s.generation }
def invalidate (s : Ledger) : Ledger := { generation := s.generation + 1 }
def reusable (s : Ledger) : Prop := s.referenceGeneration = some s.generation
def verifySubgoal (s : Ledger) : Ledger := s

-- accepted is the trusted closed-query kernel verdict, not model self-report.
def consume (s : Ledger) (accepted : Bool) : Ledger :=
  if accepted ∧ s.referenceGeneration = some s.generation then
    { s with consumptionGeneration := some s.generation }
  else s
def verifyConsumed (s : Ledger) : Ledger :=
  if s.consumptionGeneration = some s.generation then verify s else s

theorem rejected_intent_is_atomic (s : Ledger) : consume s false = s := by simp [consume]
theorem consumption_does_not_charge_tokens (s : Ledger) (accepted : Bool) :
    (consume s accepted).cost = s.cost := by simp [consume]; split <;> rfl
theorem unconsumed_path_cannot_freeze (s : Ledger)
    (h : s.consumptionGeneration ≠ some s.generation) :
    verifyConsumed s = s := by simp [verifyConsumed, h]
theorem invalidation_revokes_consumption (s : Ledger) :
    (invalidate s).consumptionGeneration = none := rfl
theorem admitted_consumption_keeps_entire_prefix (s : Ledger)
    (h : s.referenceGeneration = some s.generation) (first : s.first = none) :
    (verifyConsumed (consume s true)).first = some s.cost := by
  simp [consume, verifyConsumed, verify, h, first]

theorem subgoal_does_not_freeze_task (s : Ledger) :
    (verifySubgoal s).first = s.first := rfl

theorem missing_usage_is_unknown (s : Ledger) : (unknownCall s).usageKnown = false := rfl

theorem first_freezes (s : Ledger) (n tokens : Nat) (h : s.first = some n) :
    (call s tokens).first = some n := h

theorem failures_and_repairs_charged (s : Ledger) (failed repair : Nat) :
    (call (call s failed) repair).cost = s.cost + failed + repair := rfl

theorem first_captures_all_preceding_calls (s : Ledger) (h : s.first = none)
    (failed repair : Nat) :
    (verify (call (call s failed) repair)).first = some (s.cost + failed + repair) := by
  simp [verify, call, h]

theorem later_verdict_keeps_first (s : Ledger) (n : Nat) (h : s.first = some n) :
    (verify s).first = some n := by simp [verify, h]

theorem invalidation_revokes_reference (s : Ledger) : ¬ reusable (invalidate s) := by
  simp [reusable, invalidate]

theorem invalidation_starts_new_cost_epoch (s : Ledger) :
    (invalidate s).cost = 0 ∧ (invalidate s).first = none := by simp [invalidate]

theorem current_evidence_is_reusable (s : Ledger) : reusable (evidence s) := rfl

example : (verify (call (call {} 80) 30)).first = some 110 := by decide
example : (call (verify (call (call {} 80) 30)) 50).first = some 110 := by decide
end Ascent.Trajectory
