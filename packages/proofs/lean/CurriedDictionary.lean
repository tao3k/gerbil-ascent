-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderRouting

/-! Materialized node inventories, independently ordered at every path.
The visitation policy must permute its input keys; no shared global inventory
or common sibling visitation order is required. Native hash extraction is the
implementation obligation for this dictionary interface. -/
namespace Ascent.CurriedDictionary
open ProviderRouting
variable {K R : Type} [DecidableEq K]

def Node (K R : Type) : Nat → Type
  | 0 => List R
  | depth + 1 => List K × (K → Node K R depth)

def materializedKeys : List K → List K
  | [] => []
  | key :: rest =>
      let keys := materializedKeys rest
      if key ∈ keys then keys else key :: keys

theorem materialized_keys_membership (key : K) (keys : List K) :
    key ∈ materializedKeys keys ↔ key ∈ keys := by
  induction keys generalizing key with
  | nil => simp [materializedKeys]
  | cons head rest ih =>
    change (key ∈ (if head ∈ materializedKeys rest then materializedKeys rest else head :: materializedKeys rest)) ↔ key ∈ head :: rest
    by_cases present : head ∈ materializedKeys rest
    · have inside : head ∈ rest := (ih head).mp present
      rw [ite_eq_left present, ih key]
      simp only [List.mem_cons]
      exact ⟨Or.inr, fun hit => hit.elim (fun same => same ▸ inside) id⟩
    · simp [present, ih]

theorem materialized_keys_unique (keys : List K) : (materializedKeys keys).Nodup := by
  induction keys with
  | nil => simp [materializedKeys]
  | cons head rest ih =>
    by_cases present : head ∈ materializedKeys rest
    · simpa [materializedKeys, present] using ih
    · simp [materializedKeys, present, ih]

def buildNode : (depth : Nat) → (R → Nat → K) →
    (List K → List K → List K) → List K → List R → Node K R depth
  | 0, _, _, _, rows => rows
  | depth + 1, coordinate, visit, path, rows =>
      (visit path (materializedKeys (rows.map (fun row => coordinate row 0))),
        fun key => buildNode depth (fun row i => coordinate row (i + 1)) visit
          (path ++ [key]) (keyScan (fun row => coordinate row 0) key rows))

def forgetNode : (depth : Nat) → Node K R depth → CurriedTrie K R depth
  | 0, node => node
  | depth + 1, node => fun key => forgetNode depth (node.2 key)

def collectNode : (depth : Nat) → Node K R depth → List R
  | 0, node => node
  | depth + 1, node => node.1.flatMap fun key => collectNode depth (node.2 key)

def readNode : (depth : Nat) → List K → Node K R depth → List R
  | depth, [], node => collectNode depth node
  | 0, _ :: _, _ => []
  | depth + 1, key :: rest, node => readNode depth rest (node.2 key)

theorem forget_build (depth : Nat) (coordinate : R → Nat → K)
    (visit : List K → List K → List K) (path : List K) (rows : List R) :
    forgetNode depth (buildNode depth coordinate visit path rows) = trieBuild depth coordinate rows := by
  induction depth generalizing coordinate path rows with
  | zero => rfl
  | succ depth ih => funext key; exact ih _ _ _

theorem materialized_inventory (coordinate : R → Nat → K) (rows : List R)
    (visit : List K → List K → List K) (path : List K)
    (permuted : ∀ path keys, (visit path keys).Perm keys) :
    (visit path (materializedKeys (rows.map (fun row => coordinate row 0)))).Nodup ∧
      ∀ row ∈ rows, coordinate row 0 ∈ visit path (materializedKeys (rows.map (fun row => coordinate row 0))) := by
  have permutation := permuted path (materializedKeys (rows.map (fun row => coordinate row 0)))
  constructor
  · exact permutation.nodup_iff.mpr (materialized_keys_unique _)
  · intro row member
    exact permutation.mem_iff.mpr ((materialized_keys_membership _ _).mpr (List.mem_map.mpr ⟨row, member, rfl⟩))

theorem collect_build_count [DecidableEq R] (depth : Nat) (coordinate : R → Nat → K)
    (visit : List K → List K → List K)
    (permuted : ∀ path keys, (visit path keys).Perm keys) (path : List K)
    (rows : List R) (row : R) :
    (collectNode depth (buildNode depth coordinate visit path rows)).count row = rows.count row := by
  induction depth generalizing coordinate path rows with
  | zero => rfl
  | succ depth ih =>
    have children (key : K) :
        (collectNode depth (buildNode depth (fun row i => coordinate row (i + 1)) visit
          (path ++ [key]) (keyScan (fun row => coordinate row 0) key rows))).count row =
        (keyScan (fun row => coordinate row 0) key rows).count row := ih _ _ _
    simp only [collectNode, buildNode, List.count_flatMap, Function.comp_def, children]
    have inventory := materialized_inventory coordinate rows visit path permuted
    have counted := complete_read_all_count (fun row => coordinate row 0) rows
      (visit path (materializedKeys (rows.map (fun row => coordinate row 0)))) inventory.1 inventory.2 row
    simpa only [enumerateBuckets, List.count_flatMap, Function.comp_def, build_buckets_exact] using counted

theorem collect_build_perm [DecidableEq R] (depth : Nat) (coordinate : R → Nat → K)
    (visit : List K → List K → List K)
    (permuted : ∀ path keys, (visit path keys).Perm keys) (path : List K) (rows : List R) :
    (collectNode depth (buildNode depth coordinate visit path rows)).Perm rows := by
  exact List.perm_iff_count.mpr (collect_build_count depth coordinate visit permuted path rows)

theorem read_build_perm [DecidableEq R] (depth : Nat) (coordinate : R → Nat → K)
    (visit : List K → List K → List K)
    (permuted : ∀ path keys, (visit path keys).Perm keys) (path : List K)
    (rows : List R) (query : List K) :
    (readNode depth query (buildNode depth coordinate visit path rows)).Perm
      (rows.filter (prefixSelected depth coordinate query)) := by
  have allRows (input : List R) : input.filter (fun _ => true) = input :=
    List.filter_eq_self.mpr (by intro _ _; rfl)
  induction depth generalizing coordinate path rows query with
  | zero => cases query <;> simp [readNode, collectNode, buildNode, prefixSelected, allRows]
  | succ depth ih =>
    cases query with
    | nil => simpa [readNode, prefixSelected, allRows] using
        collect_build_perm (depth + 1) coordinate visit permuted path rows
    | cons key rest =>
      have recursive := ih (fun row i => coordinate row (i + 1)) (path ++ [key])
        (keyScan (fun row => coordinate row 0) key rows) rest
      simpa [readNode, buildNode, keyScan, List.filter_filter, prefixSelected, Bool.and_comm] using recursive

theorem numbered_prefix_restore {Row : Type} [DecidableEq Row] (depth : Nat)
    (coordinate : Row → Nat → K) (visit : List K → List K → List K)
    (permuted : ∀ path keys, (visit path keys).Perm keys)
    (source : List Row) (history : List (List Row)) (query : List K) :
    (restoreRecords (readNode depth query
      (buildNode depth (fun record : Nat × Row => coordinate record.2) visit []
        (replayNumbered (source.length + 1) (numberRows 1 source.reverse).reverse history).2))).map
      Prod.snd = (replayRows history source).filter (prefixSelected depth coordinate query) := by
  apply constructed_prefix_restore
  have enumerated := read_build_perm depth (fun record : Nat × Row => coordinate record.2)
    visit permuted []
    (replayNumbered (source.length + 1) (numberRows 1 source.reverse).reverse history).2 query
  have lifted : prefixSelected depth (fun record : Nat × Row => coordinate record.2) query =
      (fun record => prefixSelected depth coordinate query record.2) :=
    funext (fun record => prefix_selected_projection depth coordinate query Prod.snd record)
  rw [lifted] at enumerated
  exact enumerated
end Ascent.CurriedDictionary
