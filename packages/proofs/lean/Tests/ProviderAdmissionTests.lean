-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderAdmission
open Ascent.ProviderAdmission

def source : Bool → Nat | false => 2 | true => 1
def substituted : Bool → Nat | false => 1 | true => 2
example : mass [false,true] source = mass [false,true] substituted := by decide
example : ¬ (∀ r, substituted r ≤ source r) := by
  intro cap
  have bad := cap true
  simp [source,substituted] at bad
example : mass [false,true] (fun _ => 1) ≠ mass [false,true] source := by decide
example : source false = 2 := rfl

-- A concrete powerset provider with overlapping tau/delta satisfies B23.
-- Its delta enumerates the whole merged relation, not exact Set difference.
def overlapping (Row : Type) : Domain (Row → Prop) Row where
  le s t := ∀ r, s r → t r
  merge s d := fun r => s r ∨ d r
  gamma s := s
  tau s _ := s
  delta s d := fun r => s r ∨ d r
  old_le_merge _ _ _ hit := Or.inl hit
  gamma_monotone _ _ included _ hit := included _ hit
  partition _ _ _ := by simp [or_assoc]
  fresh_delta _ _ _ hit _ := hit

example : (overlapping Bool).tau (fun r => r = false) (fun r => r = true) false ∧
    (overlapping Bool).delta (fun r => r = false) (fun r => r = true) false :=
  ⟨rfl, Or.inl rfl⟩

-- Partition alone is insufficient: a fresh true row placed only in tau skips delta.
example : ¬ (∀ r : Bool, (r = false ∨ r = true) → ¬ r = false → False) := by
  intro emits
  exact emits true (Or.inr rfl) (by decide)

#print axioms mass_le
#print axioms cap_and_mass_exact
#print axioms key_occurrences_exact
#print axioms foreign_occurrences_zero
#print axioms old_visible_preserved
#print axioms delta_sound
#print axioms tau_sound
#print axioms fresh_cannot_skip_delta
#print axioms pivots_complete
#print axioms pivots_sound
#print axioms provider_body_partition

#print axioms domain_body_partition
