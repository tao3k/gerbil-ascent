-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
namespace Ascent.ProviderRouting
variable {Row Value : Type} [DecidableEq Value]

def keyMatches (coordinate : Row → Nat → Value) (constraints : List (Nat × Value))
    (row : Row) : Bool := constraints.all fun binding => coordinate row binding.1 == binding.2

def scan (coordinate : Row → Nat → Value) (constraints : List (Nat × Value))
    (rows : List Row) : List Row := rows.filter (keyMatches coordinate constraints)

def routed (coordinate : Row → Nat → Value) (constraints : List (Nat × Value))
    (candidate : Row → Bool) (rows : List Row) : List Row :=
  (rows.filter candidate).filter (keyMatches coordinate constraints)

theorem selected_constraint (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (binding : Nat × Value) (row : Row)
    (selected : binding ∈ constraints) (hit : keyMatches coordinate constraints row = true) :
    coordinate row binding.1 = binding.2 := by
  have h := List.all_eq_true.mp hit binding selected
  exact beq_iff_eq.mp h

-- Candidate buckets may overselect. They may not omit any matching occurrence.
-- List equality preserves traversal order, duplicates and the stored row itself.
theorem routed_exact (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (candidate : Row → Bool) (rows : List Row)
    (coverage : ∀ row ∈ rows, keyMatches coordinate constraints row = true → candidate row = true) :
    routed coordinate constraints candidate rows = scan coordinate constraints rows := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    have tail := ih (fun r hr => coverage r (List.mem_cons_of_mem row hr))
    have head := coverage row (by simp)
    by_cases hit : keyMatches coordinate constraints row = true
    · have admitted := head hit
      simpa [routed,scan,List.filter_cons,hit,admitted] using congrArg (List.cons row) tail
    · by_cases admitted : candidate row = true <;>
        simpa [routed,scan,List.filter_cons,hit,admitted] using tail

theorem coordinate_bucket_exact (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (binding : Nat × Value) (rows : List Row)
    (selected : binding ∈ constraints) :
    routed coordinate constraints (fun row => coordinate row binding.1 == binding.2) rows =
      scan coordinate constraints rows := by
  apply routed_exact
  intro row _ hit
  exact beq_iff_eq.mpr (selected_constraint coordinate constraints binding row selected hit)

theorem stored_occurrence (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (rows : List Row) (row : Row) :
    row ∈ scan coordinate constraints rows ↔ row ∈ rows ∧ keyMatches coordinate constraints row = true := by
  simp [scan]

theorem conflicting_duplicate (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (column : Nat) (left right : Value) (rows : List Row)
    (a : (column,left) ∈ constraints) (b : (column,right) ∈ constraints) (different : left ≠ right) :
    scan coordinate constraints rows = [] := by
  apply List.filter_eq_nil_iff.mpr
  intro row _ hit
  exact different ((selected_constraint coordinate constraints _ row a hit).symm.trans
    (selected_constraint coordinate constraints _ row b hit))
theorem constraints_permuted (coordinate : Row → Nat → Value)
    (left right : List (Nat × Value)) (rows : List Row) (order : left.Perm right) :
    scan coordinate left rows = scan coordinate right rows := by
  have equalPredicates : keyMatches coordinate left = keyMatches coordinate right := by
    funext row
    exact order.all_eq
  simp [scan,equalPredicates]

theorem bucket_choice_independent (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (left right : Nat × Value) (rows : List Row)
    (a : left ∈ constraints) (b : right ∈ constraints) :
    routed coordinate constraints (fun row => coordinate row left.1 == left.2) rows =
      routed coordinate constraints (fun row => coordinate row right.1 == right.2) rows := by
  rw [coordinate_bucket_exact coordinate constraints left rows a,
      coordinate_bucket_exact coordinate constraints right rows b]
end Ascent.ProviderRouting
