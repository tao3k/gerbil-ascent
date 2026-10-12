-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import TransitiveComponents
open Ascent.TransitiveComponents

-- Complete mutual reach makes either representative interchangeable.
example (r : Nat → Nat → Prop)
    (t : ∀ x y z, r x y → r y z → r x z)
    (cw : r 1 2) (wc : r 2 1) : r 0 1 ↔ r 0 2 :=
  predecessor_representative r t 1 2 0 cw wc

-- An incomplete reach table containing 0→1 and 1→2 misses 0→2.
-- Mutual SCC labels alone cannot justify the optimized key removal.
def incomplete (x y : Nat) : Prop :=
  (x = 0 ∧ y = 1) ∨ (x = 1 ∧ y = 2) ∨ (x = 2 ∧ y = 1)
example : incomplete 0 1 ∧ ¬ incomplete 0 2 := by simp [incomplete]
example : ¬ (∀ x y z, incomplete x y → incomplete y z → incomplete x z) := by
  intro t
  have bad := t 0 1 2 (by simp [incomplete]) (by simp [incomplete])
  exact (by simp [incomplete] : ¬ incomplete 0 2) bad

example : 2 * 3 ≤ 3 + 4 + 2 := largest_merge_doubles 3 4 2 (by simp [incomplete])
example : ¬ (2 * 4 ≤ 4 + 1 + 0) := by simp [incomplete]

#print axioms predecessor_representative
#print axioms successor_representative
#print axioms absorbed_key_cleanup
#print axioms winner_inherits_successors
#print axioms largest_merge_doubles

example (targets present : Nat → Prop) (a n : Nat) :
    missing targets present a n ↔ targets n ∧ ¬ (present n ∨ n = a) :=
  difference_exact targets present a n

example (nodes : List Nat) (targets present : Nat → Prop) (a : Nat)
    (weights : Nat → Nat) [DecidablePred targets] [DecidablePred present] :
    ((nodes.filter fun n => decide (missing targets present a n)).map weights).sum =
    ((nodes.filter fun n => decide (targets n ∧ ¬ (present n ∨ n = a))).map weights).sum :=
  difference_weighted nodes targets present a weights

#print axioms difference_exact
#print axioms difference_weighted
#print axioms retirement_mask_exact
