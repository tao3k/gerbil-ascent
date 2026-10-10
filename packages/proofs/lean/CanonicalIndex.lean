-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! A fixed ordered inventory gives every demand set one matching input.
Native lexicographic sorting implements this inventory without enumerating the
column powerset. These laws do not extract the native sorter or matching search. -/
namespace Ascent.CanonicalIndex
variable {K P : Type} [DecidableEq K]

def canonical (inventory demands : List K) : List K :=
  inventory.filter (fun key => decide (key ∈ demands))

theorem membership (inventory demands : List K) (key : K) :
    key ∈ canonical inventory demands ↔ key ∈ inventory ∧ key ∈ demands := by
  simp [canonical]

theorem same_demand_set (inventory a b : List K)
    (same : ∀ key, key ∈ a ↔ key ∈ b) :
    canonical inventory a = canonical inventory b := by
  unfold canonical
  congr 1
  funext key
  simp only [same key]

theorem encounter_order (inventory a b : List K) (order : a.Perm b) :
    canonical inventory a = canonical inventory b :=
  same_demand_set inventory a b (fun _ => order.mem_iff)

theorem duplicates (inventory demands : List K) :
    canonical inventory (demands ++ demands) = canonical inventory demands := by
  apply same_demand_set
  intro key
  simp

theorem layout_identity (planner : List K → P) (inventory a b : List K)
    (same : ∀ key, key ∈ a ↔ key ∈ b) :
    planner (canonical inventory a) = planner (canonical inventory b) := by
  rw [same_demand_set inventory a b same]
end Ascent.CanonicalIndex
