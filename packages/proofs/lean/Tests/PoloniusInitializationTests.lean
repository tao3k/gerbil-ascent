-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PoloniusInitialization
open Ascent.PoloniusInitialization

-- A moved and assigned seed at the same point remains a may fact.
example : Flow (fun p : Nat => p = 0) (fun _ _ => True) (fun _ => True) 0 := .seed rfl

-- A successor assignment kills uninitialized propagation at that successor.
example : ¬ Flow (fun p : Nat => p = 0) (fun _ _ => True) (fun p => p = 1) 1 := by
  intro h
  have impossible := (blocked_target_iff_seed (blocked := fun p : Nat => p = 1) rfl).mp h
  cases impossible

-- Arbitrarily cycling CFG edges cannot generate a fact from no seed.
example : ¬ Flow (fun _ : Nat => False) (fun _ _ => True) (fun _ => False) 100 :=
  no_seeds_no_flow

-- A kill at the source does not kill propagation into an unblocked successor.
example : Flow (fun p : Nat => p = 0) (fun p q => p = 0 ∧ q = 1) (fun p => p = 0) 1 :=
  .step (.seed rfl) ⟨rfl, rfl⟩ (by decide)

#print axioms flow_iff_seed_path
#print axioms blocked_target_iff_seed
#print axioms no_seeds_no_flow
#print axioms blockers_antitone
