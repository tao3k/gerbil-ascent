-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LatticeAdmission
open Ascent.LatticeProjection Ascent.PendingKeys Ascent.LatticeAdmission

def committed : Store Bool Nat := fun key => some (if key then 8 else 9)
def inputs : List (Bool × Nat) := [(false,7),(false,2),(false,4),(true,5)]
def collected := collect min committed empty inputs
example : collected.events = [true,false,false] := by decide
example : overlay committed collected false = some 2 := by decide
example : overlay committed collected true = some 5 := by decide
example : (admit min committed collected false 4).events = collected.events := by decide
example : cost min committed collected false 1 = 0 := by decide
example : cost min committed empty false 7 = 1 := by decide
example : cost min committed empty true 9 = 0 := by decide
example : (admit min committed empty true 9).table true = none := by decide
example : (admit min committed collected false 1).table false = some 1 := by decide
-- Consulting committed instead of pending would incorrectly produce 4 here.
example : merged min (overlay committed collected false) 4 = 2 ∧
    merged min (committed false) 4 = 4 := by decide
example : materialized collected (false,2) := by unfold materialized; decide
example : ¬ materialized collected (false,7) := by unfold materialized; decide
-- Full-update equivalence alone does not certify an arbitrary merge as a join.
example : overlay committed (collect (fun a b => a + b) committed empty [(false,1),(false,2)]) false
    = some 12 := by decide

#print axioms empty_overlay
#print axioms pending_priority
#print axioms committed_fallback
#print axioms admit_covered
#print axioms overlay_write
#print axioms ineffective_unchanged
#print axioms admission_update_exact
#print axioms collection_covered
#print axioms collection_stage_exact
#print axioms empty_collection_stage_exact
#print axioms publication_exact
#print axioms collection_publication_exact
#print axioms ineffective_cost_zero
#print axioms repeated_key_cost_zero
#print axioms fresh_effective_cost_one
#print axioms cost_support_exact
#print axioms collection_inflationary
