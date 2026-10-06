-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import FiniteHeight
import ProviderFrontier
import DirectedFrontier

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
/-- Whole-component rejection is sound only when old membership is uniform
inside every rectangle. Arbitrary rectangles do not satisfy this premise. -/
def Uniform (old : α × α → Prop) (rs : List (Rectangle α)) : Prop :=
  ∀ r ∈ rs, ∀ p ∈ rows r, ∀ q ∈ rows r, old p → old q

noncomputable def freshRectangles (old : α × α → Prop) (rs : List (Rectangle α)) := by
  classical
  exact rs.filter fun r => decide (∀ p ∈ rows r, ¬ old p)

theorem selected_member (old : α × α → Prop) (rs : List (Rectangle α))
    (uniform : Uniform old rs) (p : α × α) :
    p ∈ expand (freshRectangles old rs) ↔ p ∈ expand rs ∧ ¬ old p := by
  classical
  simp only [expand, List.mem_flatMap, freshRectangles, List.mem_filter,
    decide_eq_true_eq]
  constructor
  · rintro ⟨r, ⟨member, fresh⟩, present⟩
    exact ⟨⟨r, member, present⟩, fresh p present⟩
  · rintro ⟨⟨r, member, present⟩, absent⟩
    refine ⟨r, ⟨member, ?_⟩, present⟩
    intro q known prior
    exact absent (uniform r member q known p present prior)

theorem selected_nodup (old : α × α → Prop) (rs : List (Rectangle α))
    (members : ∀ r ∈ rs, r.left.Nodup ∧ r.right.Nodup)
    (separate : Separate rs) : (expand (freshRectangles old rs)).Nodup := by
  classical
  apply expansion_nodup
  · intro r present
    exact members r (List.mem_filter.mp present).1
  · exact List.Pairwise.filter _ separate

/-- Derive exact UF delta from the insertion law and a candidate encoding;
no Exact-frontier premise is assumed. Native decoding and SCC partition
homogeneity remain implementation obligations. -/
theorem uf_selected_exact (state : DirectedFrontier.State α) (a b : α)
    (rs : List (Rectangle α))
    (encoding : ∀ p, p ∈ expand rs ↔ DirectedFrontier.ufCandidate state a b p.1 p.2)
    (uniform : Uniform (fun p => DirectedFrontier.ufVisible state p.1 p.2) rs) :
    Exact (fun p => DirectedFrontier.ufVisible state p.1 p.2)
      (fun p => DirectedFrontier.ufVisible (DirectedFrontier.extendState state a b) p.1 p.2)
      (freshRectangles (fun p => DirectedFrontier.ufVisible state p.1 p.2) rs) := by
  intro p
  rw [← expansion_member, selected_member _ rs uniform p, encoding p]
  exact DirectedFrontier.uf_emitted_exact state a b p.1 p.2

/-- Component rectangles are homogeneous whenever each side has one root
and visible reachability is determined by the ordered root pair. -/
theorem component_uniform (root : α → C) (visible : C → C → Prop)
    (rs : List (Rectangle α))
    (components : ∀ r ∈ rs, ∀ x ∈ r.left, ∀ y ∈ r.left, root x = root y)
    (targets : ∀ r ∈ rs, ∀ x ∈ r.right, ∀ y ∈ r.right, root x = root y) :
    Uniform (fun p => visible (root p.1) (root p.2)) rs := by
  intro r member p hp q hq old
  have pp := (rectangle_member r p.1 p.2).mp hp
  have qq := (rectangle_member r q.1 q.2).mp hq
  rw [← components r member p.1 pp.1 q.1 qq.1,
      ← targets r member p.2 pp.2 q.2 qq.2]
  exact old

end Ascent.ProviderRectangles
