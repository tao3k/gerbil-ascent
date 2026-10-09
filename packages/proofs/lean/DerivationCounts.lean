-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
/-! Unit natural annotations count combinations of child proof trees, then
sum distinct alternatives. Native graph completeness is a separate premise;
these laws do not identify all-tree semantics with minimum-depth provenance. -/
namespace Ascent.DerivationCounts
def body : List Nat → Nat
  | [] => 1
  | count :: rest => count * body rest
def annotation (alternatives : List (List Nat)) : Nat :=
  (alternatives.map body).sum
def choices {A : Type} : List (List A) → List (List A)
  | [] => [[]]
  | head :: rest => head.flatMap (fun item => (choices rest).map (item :: ·))

theorem length_branches {A : Type} (head : List A) (tails : List (List A)) :
    (head.flatMap (fun item => tails.map (item :: ·))).length = head.length * tails.length := by
  induction head with
  | nil => simp
  | cons item rest ih =>
    simp only [List.flatMap_cons, List.length_append, List.length_map, List.length_cons]
    rw [ih]
    simp [Nat.succ_mul, Nat.add_comm]

theorem body_counts_trees {A : Type} (groups : List (List A)) :
    body (groups.map List.length) = (choices groups).length := by
  induction groups with
  | nil => rfl
  | cons head rest ih =>
    simp only [List.map_cons, body, choices, length_branches]
    rw [ih]

theorem alternatives_count_trees {A : Type} (alternatives : List (List (List A))) :
    annotation (alternatives.map (fun groups => groups.map List.length)) =
      (alternatives.flatMap choices).length := by
  induction alternatives with
  | nil => rfl
  | cons groups rest ih =>
    simpa [annotation, List.sum_cons, body_counts_trees] using
      congrArg (fun count => (choices groups).length + count) ih

theorem repeated_body (count : Nat) : body [count,count] = count * count := by
  simp [body]
theorem alternative_union (a b : List (List Nat)) :
    annotation (a ++ b) = annotation a + annotation b := by
  simp [annotation, List.sum_append]

def rounds {A : Type} (step : A → A) (seed : A) : Nat → A
  | 0 => seed
  | n + 1 => step (rounds step seed n)
theorem stable_rounds {A : Type} (step : A → A) (seed : A)
    (stable : step seed = seed) (n : Nat) : rounds step seed n = seed := by
  induction n with
  | zero => rfl
  | succ n ih => simp [rounds, ih, stable]
end Ascent.DerivationCounts
