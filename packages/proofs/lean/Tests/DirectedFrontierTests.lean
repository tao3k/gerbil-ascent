-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DirectedFrontier
namespace Ascent.DirectedFrontierTests
open DirectedFrontier

def empty : Snapshot Nat where
  state := {
    active := fun _ => False
    reach := fun x y => x = y
    refl := fun _ => rfl
    trans := fun _ _ _ => Eq.trans
    supported := fun _ _ known => Or.inl known }
  self := fun _ => False
  self_supported := by simp

def cycle : Snapshot Nat := injectMany empty [(0, 1), (1, 0)]
-- Reachability has identity internally, but unknown rows are never public.
example : ¬ ufVisible empty.state 2 2 := by simp [ufVisible, empty]
example : ¬ strictVisible empty.state empty.self 2 2 := by simp [strictVisible, empty]
-- A cycle changes reach, not the explicit-self predicate of strict trrel.
example : ufVisible cycle.state 0 0 := by
  simp [ufVisible, cycle, injectMany, extendSnapshot, extendState,
    activeAfter, TransitiveComponents.insertEdge, empty]
example : ¬ strictVisible cycle.state cycle.self 0 0 := by
  rw [strict_self_exact]
  simp [cycle, injectMany, extendSnapshot, selfAfter, empty]
example : strictEmitted cycle.state cycle.self 0 0 0 0 := by
  simp [strictEmitted, strictCandidate, cross, strictVisible, cycle,
    injectMany, extendSnapshot, extendState, selfAfter,
    TransitiveComponents.insertEdge, empty]
-- Joining separate directed paths must expose a non-input transitive pair.
example : ufEmitted (injectMany empty [(0, 1), (2, 3)]).state 1 2 0 3 := by
  simp [ufEmitted, ufCandidate, ufVisible, cross, injectMany, extendSnapshot,
    extendState, activeAfter, TransitiveComponents.insertEdge, empty]
example : ¬ ufEmitted cycle.state 0 1 0 1 := by
  simp [ufEmitted, ufVisible, cycle, injectMany, extendSnapshot,
    extendState, activeAfter, TransitiveComponents.insertEdge, empty]
example : extendGroup (fun _ : Bool => empty) true 0 1 false = empty := by
  apply other_group
  decide

#print axioms cross_supported
#print axioms uf_partition
#print axioms uf_emitted_exact
#print axioms strict_partition
#print axioms strict_emitted_exact
#print axioms uf_self_exact
#print axioms strict_self_exact
#print axioms uf_insert_least
#print axioms strict_supported
#print axioms injectMany_least
#print axioms injectMany_monotone
#print axioms injectMany_inputs
#print axioms injectMany_self_exact
#print axioms injectMany_active_exact
#print axioms other_group
end Ascent.DirectedFrontierTests
