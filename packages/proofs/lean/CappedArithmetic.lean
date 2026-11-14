/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Natural budget saturation for program/finite-arithmetic.ss. Arithmetic
preservation does not establish compiler type-bound completeness.
-/
import Std
namespace Ascent
theorem cap_mul_left (cap a b : Nat) :
    min cap (min cap a * b) = min cap (a * b) := by
  by_cases hb : b = 0
  · simp [hb]
  by_cases ha : a ≤ cap
  · simp [Nat.min_eq_right ha]
  · have hca : cap ≤ a := by omega
    have hcb : cap ≤ cap * b := Nat.le_mul_of_pos_right cap (by omega)
    have hab : cap ≤ a * b := Nat.le_trans hca (Nat.le_mul_of_pos_right a (by omega))
    simp [Nat.min_eq_left hca, Nat.min_eq_left hcb, Nat.min_eq_left hab]
theorem cap_mul (cap a b : Nat) :
    min cap (min cap a * min cap b) = min cap (a * b) := by
  rw [cap_mul_left, Nat.mul_comm a, cap_mul_left, Nat.mul_comm b]
 def cappedPowerFrom (cap base : Nat) : Nat → Nat → Nat
  | 0, acc => min cap acc
  | n + 1, acc => cappedPowerFrom cap base n (min cap (acc * base))
theorem capped_power_from_exact (cap base exponent acc : Nat) :
    cappedPowerFrom cap base exponent acc = min cap (acc * base ^ exponent) := by
  induction exponent generalizing acc with
  | zero => simp [cappedPowerFrom]
  | succ n ih =>
    rw [cappedPowerFrom, ih, cap_mul_left, Nat.pow_succ]
    congr 1
    simp [Nat.mul_assoc, Nat.mul_comm, Nat.mul_left_comm]
theorem capped_power_inputs (cap base exponent acc : Nat) :
    cappedPowerFrom cap (min cap base) exponent (min cap acc) =
      cappedPowerFrom cap base exponent acc := by
  induction exponent generalizing acc with
  | zero => simp [cappedPowerFrom]
  | succ n ih =>
    rw [cappedPowerFrom, cap_mul, ih, cappedPowerFrom]
    simp only [capped_power_from_exact, cap_mul_left]

theorem capped_power_zero_cap (base exponent acc : Nat) :
    cappedPowerFrom 0 base exponent acc = 0 := by
  simp [capped_power_from_exact]

theorem capped_power_zero_base (cap exponent acc : Nat) :
    cappedPowerFrom cap 0 (exponent + 1) acc = 0 := by
  simp [capped_power_from_exact]

theorem capped_power_one_base (cap exponent acc : Nat) :
    cappedPowerFrom cap 1 exponent acc = min cap acc := by
  simp [capped_power_from_exact]

theorem capped_power_stop (cap base exponent acc : Nat)
    (positive : 0 < base) (saturated : cap ≤ acc) :
    cappedPowerFrom cap base exponent acc = cap := by
  rw [capped_power_from_exact]
  exact Nat.min_eq_left (Nat.le_trans saturated
    (Nat.le_mul_of_pos_right acc (Nat.pow_pos positive)))

theorem capped_power_exact (cap base exponent : Nat) :
    cappedPowerFrom cap (min cap base) exponent (min cap 1) =
      min cap (base ^ exponent) := by
  rw [capped_power_inputs, capped_power_from_exact]
  simp

theorem natural_power_grows (base exponent : Nat) (large : 2 ≤ base) :
    exponent + 1 ≤ base ^ exponent := by
  induction exponent with
  | zero => simp
  | succ n ih =>
    rw [Nat.pow_succ]
    have h := Nat.mul_le_mul ih large
    omega

theorem capped_exponent_exact (cap base exponent : Nat) :
    min cap (base ^ min cap exponent) = min cap (base ^ exponent) := by
  by_cases hc : cap = 0
  · simp [hc]
  by_cases he : exponent ≤ cap
  · simp [Nat.min_eq_right he]
  have hce : cap ≤ exponent := by omega
  by_cases hb : base = 0
  · simp [hb, Nat.min_eq_left hce, Nat.zero_pow (by omega : 0 < cap),
      Nat.zero_pow (by omega : 0 < exponent)]
  by_cases hb1 : base = 1
  · simp [hb1]
  have hbc : cap ≤ base ^ cap := by
    have h := natural_power_grows base cap (by omega)
    omega
  have hbe : cap ≤ base ^ exponent :=
    Nat.le_trans hbc (Nat.pow_le_pow_right (by omega) hce)
  simp [Nat.min_eq_left hce, Nat.min_eq_left hbc, Nat.min_eq_left hbe]

theorem capped_base_exact (cap base exponent : Nat) :
    min cap ((min cap base) ^ exponent) = min cap (base ^ exponent) := by
  have h := capped_power_exact cap base exponent
  rw [capped_power_from_exact, cap_mul_left] at h
  simpa using h

inductive BudgetExpression where
  | literal : Nat → BudgetExpression
  | product : BudgetExpression → BudgetExpression → BudgetExpression
  | power : BudgetExpression → BudgetExpression → BudgetExpression

def exactBudget : BudgetExpression → Nat
  | .literal n => n
  | .product a b => exactBudget a * exactBudget b
  | .power a b => exactBudget a ^ exactBudget b

def cappedBudget (cap : Nat) : BudgetExpression → Nat
  | .literal n => min cap n
  | .product a b => min cap (cappedBudget cap a * cappedBudget cap b)
  | .power a b => min cap (cappedBudget cap a ^ cappedBudget cap b)

theorem capped_budget_exact (cap : Nat) (expression : BudgetExpression) :
    cappedBudget cap expression = min cap (exactBudget expression) := by
  induction expression with
  | literal n => rfl
  | product a b ia ib =>
    simp only [cappedBudget, exactBudget, ia, ib, cap_mul]
  | power a b ia ib =>
    simp only [cappedBudget, exactBudget, ia, ib,
      capped_base_exact, capped_exponent_exact]

/-- Cardinality is the conservative all-functions bound, not a claim that
    every mathematical function is admitted as a monotone descriptor. -/
inductive BudgetSignature where
  | relation : Nat → Nat → BudgetSignature
  | arrow : BudgetSignature → BudgetSignature → BudgetSignature

def cardinalityExpression : BudgetSignature → BudgetExpression
  | .relation width atoms => .power (.literal 2) (.power (.literal atoms) (.literal width))
  | .arrow domain codomain => .power (cardinalityExpression codomain) (cardinalityExpression domain)

def heightExpression : BudgetSignature → BudgetExpression
  | .relation width atoms => .power (.literal atoms) (.literal width)
  | .arrow domain codomain => .product (cardinalityExpression domain) (heightExpression codomain)

theorem capped_cardinality_exact (cap : Nat) (signature : BudgetSignature) :
    cappedBudget cap (cardinalityExpression signature) =
      min cap (exactBudget (cardinalityExpression signature)) :=
  capped_budget_exact cap _

theorem capped_height_exact (cap : Nat) (signature : BudgetSignature) :
    cappedBudget cap (heightExpression signature) =
      min cap (exactBudget (heightExpression signature)) :=
  capped_budget_exact cap _

end Ascent
