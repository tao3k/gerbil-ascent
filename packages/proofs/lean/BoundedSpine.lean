/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Pure finite-spine refinement of bounded-list-length. Payloads are erased.
Cycles and mutable Gerbil pointers require the independent native controls.
-/
import Std
namespace Ascent.BoundedSpine
inductive Spine where
  | nil
  | cons (rest : Spine)
  | improper
  deriving DecidableEq, Repr
open Spine

def properLength : Spine → Option Nat
  | nil => some 0
  | improper => none
  | cons rest => (properLength rest).map Nat.succ

def boundedLength : Nat → Spine → Option Nat
  | _, nil => some 0
  | _, improper => none
  | 0, cons _ => none
  | cap + 1, cons rest => (boundedLength cap rest).map Nat.succ

theorem bounded_formula (cap : Nat) (spine : Spine) :
    boundedLength cap spine = (properLength spine).bind
      (fun n => if n ≤ cap then some n else none) := by
  induction spine generalizing cap with
  | nil => simp [boundedLength, properLength]
  | improper => simp [boundedLength, properLength]
  | cons rest ih =>
    cases cap with
    | zero => cases h : properLength rest <;> simp [boundedLength, properLength, h]
    | succ cap =>
      cases h : properLength rest with
      | none => simp [boundedLength, properLength, ih, h]
      | some n =>
        by_cases fit : n ≤ cap <;> simp [boundedLength, properLength, ih, h, fit]

theorem accepted_exact (cap n : Nat) (spine : Spine) :
    boundedLength cap spine = some n ↔ properLength spine = some n ∧ n ≤ cap := by
  rw [bounded_formula]
  cases h : properLength spine with
  | none => simp
  | some width =>
    by_cases fit : width ≤ cap <;> simp [fit] <;> omega

theorem improper_rejected (cap : Nat) (spine : Spine)
    (h : properLength spine = none) : boundedLength cap spine = none := by
  simp [bounded_formula, h]

theorem exact_cap (cap : Nat) (spine : Spine)
    (h : properLength spine = some cap) : boundedLength cap spine = some cap := by
  exact (accepted_exact cap cap spine).mpr ⟨h, Nat.le_refl cap⟩

theorem oversized_rejected (cap width : Nat) (spine : Spine)
    (h : properLength spine = some width) (large : cap < width) :
    boundedLength cap spine = none := by
  simp [bounded_formula, h, Nat.not_le.mpr large]

theorem admitted_monotone (small large n : Nat) (spine : Spine)
    (caps : small ≤ large) (h : boundedLength small spine = some n) :
    boundedLength large spine = some n := by
  obtain ⟨proper, fit⟩ := (accepted_exact small n spine).mp h
  exact (accepted_exact large n spine).mpr ⟨proper, Nat.le_trans fit caps⟩

-- Pair advances, excluding the final nil/improper/cap boundary observation.
def advances : Nat → Spine → Nat
  | cap + 1, cons rest => 1 + advances cap rest
  | _, _ => 0

theorem advances_bound (cap : Nat) (spine : Spine) : advances cap spine ≤ cap := by
  induction cap generalizing spine with
  | zero => cases spine <;> simp [advances]
  | succ cap ih =>
    cases spine with
    | nil => simp [advances]
    | improper => simp [advances]
    | cons rest => have h := ih rest; simp only [advances]; omega
end Ascent.BoundedSpine
