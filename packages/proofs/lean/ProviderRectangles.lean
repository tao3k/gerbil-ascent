-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import FiniteHeight
import ProviderFrontier

/-! Compressed positive relation frontiers. These laws concern frozen member
lists, not mutable Scheme parent pointers, protocol steps or arbitrary lattices. -/
namespace Ascent.ProviderRectangles
structure Rectangle (α : Type) where
  left : List α
  right : List α

def rows (r : Rectangle α) : List (α × α) :=
  r.left.flatMap fun x => r.right.map fun y => (x, y)
def expand (rs : List (Rectangle α)) : List (α × α) := rs.flatMap rows
def count (rs : List (Rectangle α)) : Nat :=
  (rs.map fun r => r.left.length * r.right.length).sum

theorem rectangle_length (r : Rectangle α) :
    (rows r).length = r.left.length * r.right.length := by
  exact Ascent.table_product_length r.left r.right Prod.mk

theorem rectangle_member (r : Rectangle α) (x y : α) :
    (x, y) ∈ rows r ↔ x ∈ r.left ∧ y ∈ r.right := by
  simp [rows, List.mem_flatMap, List.mem_map, Prod.mk.injEq]

theorem expansion_member (rs : List (Rectangle α)) (p : α × α) :
    p ∈ expand rs ↔ ∃ r ∈ rs, p.1 ∈ r.left ∧ p.2 ∈ r.right := by
  cases p with
  | mk x y => simp [expand, List.mem_flatMap, rectangle_member]

theorem count_exact (rs : List (Rectangle α)) : (expand rs).length = count rs := by
  induction rs with
  | nil => rfl
  | cons r rs ih => simp [expand, count, List.flatMap_cons, rectangle_length] at *

def Separate (rs : List (Rectangle α)) : Prop :=
  rs.Pairwise fun a b => ∀ p, p ∈ rows a → p ∈ rows b → False

theorem map_pair_nodup (x : α) (ys : List α) (unique : ys.Nodup) :
    (ys.map fun y => (x, y)).Nodup := by
  induction ys with
  | nil => simp
  | cons y ys ih =>
      simp only [List.nodup_cons] at unique
      simp only [List.map_cons, List.nodup_cons]
      exact ⟨by simpa using unique.1, ih unique.2⟩

theorem rectangle_nodup (r : Rectangle α)
    (left : r.left.Nodup) (right : r.right.Nodup) : (rows r).Nodup := by
  rcases r with ⟨xs, ys⟩
  induction xs with
  | nil => simp [rows]
  | cons x xs ih =>
      simp only [List.nodup_cons] at left
      apply List.nodup_append.mpr
      refine ⟨map_pair_nodup x ys right, ih left.2 right, ?_⟩
      intro a ha b hb equal
      subst b
      obtain ⟨y, _, same⟩ := List.mem_map.mp ha
      subst a
      have member := (rectangle_member ⟨xs, ys⟩ x y).mp hb
      exact left.1 member.1

theorem expansion_nodup (rs : List (Rectangle α))
    (members : ∀ r ∈ rs, r.left.Nodup ∧ r.right.Nodup)
    (separate : Separate rs) : (expand rs).Nodup := by
  induction rs with
  | nil => simp [expand]
  | cons r rs ih =>
      have sep := List.pairwise_cons.mp separate
      apply List.nodup_append.mpr
      refine ⟨rectangle_nodup r (members r (by simp)).1 (members r (by simp)).2,
        ih (fun q h => members q (by simp [h])) sep.2, ?_⟩
      intro a ha b hb same
      subst b
      obtain ⟨q, hq, hrow⟩ := List.mem_flatMap.mp hb
      exact sep.1 q hq a ha hrow

/-- A complete exact frontier specification is independent of enumeration. -/
def Exact (old next : α × α → Prop) (rs : List (Rectangle α)) : Prop :=
  ∀ p, (∃ r ∈ rs, p.1 ∈ r.left ∧ p.2 ∈ r.right) ↔ next p ∧ ¬ old p

theorem frontier_exact (old next : α × α → Prop) (rs : List (Rectangle α))
    (contract : Exact old next rs) (p : α × α) :
    p ∈ expand rs ↔ ProviderFrontier.delta old next p := by
  rw [expansion_member]; exact contract p

theorem frontier_partition (old next : α × α → Prop) (rs : List (Rectangle α))
    (grows : ∀ p, old p → next p) (contract : Exact old next rs) (p : α × α) :
    next p ↔ old p ∨ p ∈ expand rs := by
  rw [frontier_exact old next rs contract]
  exact ProviderFrontier.concrete_partition old next grows p

def lookup [DecidableEq α] (rs : List (Rectangle α)) (x : α) :=
  (expand rs).filter fun p => p.1 == x

theorem lookup_exact [DecidableEq α] (rs : List (Rectangle α)) (x y : α) :
    (x, y) ∈ lookup rs x ↔ (x, y) ∈ expand rs := by simp [lookup]

theorem budget_exact (rs : List (Rectangle α)) (budget : Nat) :
    count rs ≤ budget ↔ (expand rs).length ≤ budget := by rw [count_exact]

/-- An overlapping descriptor family overcounts and repeats, despite correct
Set membership. Disjointness is essential to unique-fact budget semantics. -/
theorem duplicate_rectangle (r : Rectangle α) :
    count [r, r] = 2 * (rows r).length := by
  simp [count, rectangle_length, Nat.two_mul]
end Ascent.ProviderRectangles
