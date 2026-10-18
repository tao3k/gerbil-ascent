-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderIteration
open Ascent.ProviderIteration

-- A two-element abstract lattice collapses distinct head facts to one state.
-- This is not the powerset of Bool facts; no gamma(join)=union law is required.
noncomputable def bitLattice : CompleteJoin Bool := by
  classical
  exact {
    le := fun a b => a = true → b = true
    refl := fun _ h => h
    trans := fun _ _ _ ab bc h => bc (ab h)
    antisymm := by intro a b ab ba; cases a <;> cases b <;> simp_all
    sup := fun family => decide (family true)
    upper := by intro family s member hit; subst s; simp [member]
    least := by
      intro family bound caps hit
      exact caps true (of_decide_eq_true hit) rfl }

noncomputable def compressed : Program Bool Unit Unit Bool where
  lattice := bitLattice
  head := fun _ => true
  rules := [⟨[],(),fun _ => false⟩, ⟨[(),()],(),fun _ => true⟩]
  gamma := fun s _ _ _ => s = true
  gamma_mono := fun _ _ ordered _ _ _ hit => ordered hit
  delta := fun _ next _ _ _ => next = true
  delta_sound := fun _ _ _ _ _ _ hit => hit
  delta_covers := fun _ _ _ _ _ _ hit _ => hit

-- Injection of false exposes a true concrete observation. Requiring gamma to
-- return only injected tuples would reject this legitimate compressed domain.
example : compressed.gamma (compressed.head false) () () () := rfl
example : compressed.head false = compressed.head true := rfl
example : bitLattice.le false true := fun h => Bool.noConfusion h
example : compressed.delta true true () () () := rfl

-- An anti-monotone gamma cannot satisfy the admitted concretization contract.
example : ¬ (∀ a b : Bool, bitLattice.le a b → a = false → b = false) := by
  intro mono
  have bad := mono false true (fun h => Bool.noConfusion h) rfl
  exact Bool.noConfusion bad

-- An empty fresh batch cannot overwrite an already accumulated head state.
example : join bitLattice true false ≠ false := by
  intro replaced
  have retained := join_left bitLattice true false
  rw [replaced] at retained
  exact Bool.noConfusion (retained rfl)

#print axioms join_left
#print axioms join_right
#print axioms join_le
#print axioms join_mono
#print axioms inject_upper
#print axioms inject_le
#print axioms inject_mono
#print axioms inject_union
#print axioms heads_partition
#print axioms full_grows
#print axioms heads_mono
#print axioms full_mono
#print axioms pivot_after_full
#print axioms iterations_equal
#print axioms history_below_closed
#print axioms initial_below_history
#print axioms stationary_least
#print axioms least_below_closed
#print axioms seed_below_least
#print axioms least_closed
#print axioms least_fixed
#print axioms stationary_eq_least
#print axioms ranked_termination
#print axioms ranked_converges
