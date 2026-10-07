-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import StrictDependencies
open Ascent.RuleGraphClosure Ascent.StrictDependencies

def kinds : Nat → RelationKind := fun key => if key = 0 then .lattice else .relation
def plans : List (Rule Nat) := [⟨[1,2],[⟨.atom,some 0⟩,⟨.guard,some 7⟩]⟩]
example : (extract kinds plans).length = 2 := by decide
example : (extract kinds plans).map Edge.strict = [true,true] := by decide
example : needsStrict kinds plans = true := by decide
example : needsStrict (fun _ : Nat => .relation) plans = false := by decide
example : strict kinds .atom 1 0 = false := by decide
example : strict kinds .aggregate 1 0 = true := by decide
example : componentMax [1,2] (fun key => if key = 1 then 1 else 0) = 1 := by decide
example : normalize [1,2] (fun key => if key = 1 then 1 else 0) 2 = 1 := by decide
example : normalize [1,2] (fun key => if key = 1 then 1 else 0) 0 = 0 := by decide

#print axioms extraction_exact
#print axioms strict_exact
#print axioms strict_preflight
#print axioms skipped_edges_nonstrict
#print axioms skipped_zero_valid
#print axioms path_bound
#print axioms strict_cycle_impossible
#print axioms projection_later
#print axioms relax_below_valid
#print axioms propagated_below_valid
#print axioms completed_propagation_minimal
#print axioms mutual_paths_equal
#print axioms component_max_below
#print axioms normalization_below_valid
