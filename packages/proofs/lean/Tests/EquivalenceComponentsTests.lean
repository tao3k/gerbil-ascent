-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import EquivalenceComponents
namespace Ascent.EquivalenceComponentsTests
open EquivalenceComponents

def empty : State Nat where
  active := fun _ => False
  rel := fun _ _ => False
  supported := by simp
  refl := by simp
  symm := by simp
  trans := by simp

-- Unknown nodes are outside the active domain, including their diagonals.
example : ¬ (extendState empty 0 1).rel 2 2 := by
  simp [extendState, EquivalenceComponents.insert, cross, base, empty]
example : emitted empty 0 0 0 0 := by
  simp [emitted, empty]
example : ¬ emitted empty 0 0 0 1 := by
  simp [emitted, cross, base, empty]
-- A bridge emits the transitive pair; returning only the requested edge fails.
example : emitted (extendState empty 0 1) 1 2 0 2 := by
  simp [emitted, extendState, activeAfter, cross, base, EquivalenceComponents.insert, empty]
example : ¬ emitted (extendState empty 0 1) 1 0 0 1 := by
  simp [emitted, extendState, activeAfter, cross, base, EquivalenceComponents.insert, empty]
example : extendGroup (fun _ : Bool => empty) true 0 1 false = empty := by
  apply other_group
  decide

#print axioms base_symm
#print axioms base_trans
#print axioms insert_symm
#print axioms insert_trans
#print axioms inserted_edge
#print axioms insert_least
#print axioms base_fresh
#print axioms base_supported
#print axioms emitted_exact
#print axioms total_delta
#print axioms insert_supported
#print axioms insert_refl
#print axioms other_group
#print axioms injectMany_least
#print axioms injectMany_monotone
#print axioms injectMany_inputs
end Ascent.EquivalenceComponentsTests
