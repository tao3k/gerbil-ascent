-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import FiniteHeight
import ProviderFrontier
import DirectedFrontier
import EquivalenceComponents

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

/-- A finite captured component family. Ownership excludes overlapping member
lists; root-pair uniqueness must still be checked independently. -/
structure Components (α C : Type) where
  members : C → List α
  owner : α → C
  owns : ∀ c x, x ∈ members c → owner x = c
  unique : ∀ c, (members c).Nodup

def componentPlan (family : Components α C) (pairs : List (C × C)) : List (Rectangle α) :=
  pairs.map fun pair => ⟨family.members pair.1, family.members pair.2⟩

theorem component_pair_owned (family : Components α C) (pair : C × C)
    (p : α × α) (present : p ∈ rows ⟨family.members pair.1, family.members pair.2⟩) :
    (family.owner p.1, family.owner p.2) = pair := by
  have member := (rectangle_member _ p.1 p.2).mp present
  exact Prod.ext (family.owns _ _ member.1) (family.owns _ _ member.2)

theorem component_plan_separate (family : Components α C) (pairs : List (C × C))
    (unique : pairs.Nodup) : Separate (componentPlan family pairs) := by
  apply List.pairwise_map.mpr
  apply unique.imp
  intro a b different p ha hb
  exact different ((component_pair_owned family a p ha).symm.trans
    (component_pair_owned family b p hb))

theorem component_plan_nodup (family : Components α C) (pairs : List (C × C))
    (unique : pairs.Nodup) : (expand (componentPlan family pairs)).Nodup := by
  apply expansion_nodup _ _ (component_plan_separate family pairs unique)
  intro r present
  obtain ⟨pair, _, same⟩ := List.mem_map.mp present
  subst r
  exact ⟨family.unique _, family.unique _⟩

theorem component_plan_uniform (family : Components α C) (pairs : List (C × C))
    (visible : C → C → Prop) :
    Uniform (fun p => visible (family.owner p.1) (family.owner p.2))
      (componentPlan family pairs) := by
  apply component_uniform
  · intro r present x hx y hy
    obtain ⟨pair, _, same⟩ := List.mem_map.mp present
    subst r
    exact (family.owns _ _ hx).trans (family.owns _ _ hy).symm
  · intro r present x hx y hy
    obtain ⟨pair, _, same⟩ := List.mem_map.mp present
    subst r
    exact (family.owns _ _ hx).trans (family.owns _ _ hy).symm

/-- SCC quotient exactness supplies the root interpretation required above. -/
theorem component_plan_reach_uniform (family : Components α C) (pairs : List (C × C))
    (reach : α → α → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (same : ∀ x y, family.owner x = family.owner y ↔ reach x y ∧ reach y x) :
    Uniform (fun p => reach p.1 p.2) (componentPlan family pairs) := by
  have uniform := component_plan_uniform family pairs
    (TransitiveComponents.compressed family.owner reach)
  intro r member p hp q hq old
  have compressed := (TransitiveComponents.quotient_exact family.owner reach trans same p.1 p.2).mpr old
  exact (TransitiveComponents.quotient_exact family.owner reach trans same q.1 q.2).mp
    (uniform r member p hp q hq compressed)

/-- Supported reach prevents an SCC from mixing active and inactive members.
Latent reflexivity alone does not imply that an endpoint is active. -/
theorem component_active_iff (state : DirectedFrontier.State α)
    (family : Components α C)
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x)
    (x y : α) (owned : family.owner x = family.owner y) :
    state.active x ↔ state.active y := by
  rcases state.supported x y ((same x y).mp owned).1 with equal | active
  · subst y; rfl
  · exact ⟨fun _ => active.2, fun _ => active.1⟩

/-- Homogeneity of the public UF relation includes endpoint activation, not
only latent reach. The support invariant discharges this extra obligation. -/
theorem component_plan_uf_uniform (state : DirectedFrontier.State α)
    (family : Components α C) (pairs : List (C × C))
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x) :
    Uniform (fun p => DirectedFrontier.ufVisible state p.1 p.2)
      (componentPlan family pairs) := by
  intro r member p hp q hq old
  obtain ⟨pair, _, equal⟩ := List.mem_map.mp member
  subst r
  have ownedP := component_pair_owned family pair p hp
  have ownedQ := component_pair_owned family pair q hq
  have owners := ownedP.trans ownedQ.symm
  exact ⟨component_plan_reach_uniform family pairs state.reach state.trans same
      _ (List.mem_map.mpr ⟨pair, by assumption, rfl⟩) p hp q hq old.1,
    (component_active_iff state family same p.1 q.1 (congrArg Prod.fst owners)).mp old.2.1,
    (component_active_iff state family same p.2 q.2 (congrArg Prod.snd owners)).mp old.2.2⟩

/-- Specialize frontier selection to supported SCC plans. Completeness of
native candidate decoding is still an explicit premise; Uniform is derived. -/
theorem component_uf_selected_exact (state : DirectedFrontier.State α) (a b : α)
    (family : Components α C) (pairs : List (C × C))
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x)
    (encoding : ∀ p, p ∈ expand (componentPlan family pairs) ↔
      DirectedFrontier.ufCandidate state a b p.1 p.2) :
    Exact (fun p => DirectedFrontier.ufVisible state p.1 p.2)
      (fun p => DirectedFrontier.ufVisible (DirectedFrontier.extendState state a b) p.1 p.2)
      (freshRectangles (fun p => DirectedFrontier.ufVisible state p.1 p.2)
        (componentPlan family pairs)) := by
  exact uf_selected_exact state a b _ encoding (component_plan_uf_uniform state family pairs same)

/-- Ownership alone excludes overlap but not omission. Complete captured
member lists also contain every node assigned to a root. -/
theorem component_plan_member_iff (family : Components α C) (pairs : List (C × C))
    (complete : ∀ x, x ∈ family.members (family.owner x)) (p : α × α) :
    p ∈ expand (componentPlan family pairs) ↔ (family.owner p.1, family.owner p.2) ∈ pairs := by
  constructor
  · intro present
    obtain ⟨r, member, row⟩ := List.mem_flatMap.mp present
    obtain ⟨pair, known, equal⟩ := List.mem_map.mp member
    subst r
    exact (component_pair_owned family pair p row).symm ▸ known
  · intro known
    apply List.mem_flatMap.mpr
    refine ⟨⟨family.members (family.owner p.1), family.members (family.owner p.2)⟩,
      List.mem_map.mpr ⟨(family.owner p.1, family.owner p.2), known, rfl⟩, ?_⟩
    exact (rectangle_member _ p.1 p.2).mpr ⟨complete _, complete _⟩

theorem inactive_component_singleton (state : DirectedFrontier.State α)
    (family : Components α C)
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x)
    (a x : α) (inactive : ¬ state.active a) (owned : family.owner x = family.owner a) :
    x = a := by
  rcases state.supported x a ((same x a).mp owned).1 with equal | active
  · exact equal
  · exact False.elim (inactive active.2)

def UFRootFrontier (state : DirectedFrontier.State α) (family : Components α C)
    (a b : α) (pair : C × C) : Prop :=
  (TransitiveComponents.compressed family.owner state.reach pair.1 (family.owner a) ∧
   TransitiveComponents.compressed family.owner state.reach (family.owner b) pair.2 ∧
   ¬ TransitiveComponents.compressed family.owner state.reach pair.1 pair.2) ∨
  (pair.1 = family.owner a ∧ pair.2 = family.owner a ∧ ¬ state.active a) ∨
  (pair.1 = family.owner b ∧ pair.2 = family.owner b ∧ ¬ state.active b)

theorem root_frontier_exact (state : DirectedFrontier.State α)
    (family : Components α C) (a b x y : α)
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x) :
    UFRootFrontier state family a b (family.owner x, family.owner y) ↔
      DirectedFrontier.ufEmitted state a b x y := by
  rw [DirectedFrontier.uf_emitted_decomposition]
  unfold UFRootFrontier
  rw [TransitiveComponents.quotient_exact _ _ state.trans same x a,
      TransitiveComponents.quotient_exact _ _ state.trans same b y,
      TransitiveComponents.quotient_exact _ _ state.trans same x y]
  constructor
  · rintro (⟨xa, by', missing⟩ | ⟨xa, ya, inactive⟩ | ⟨xb, yb, inactive⟩)
    · exact Or.inl ⟨⟨xa, by'⟩, missing⟩
    · exact Or.inr (Or.inl ⟨inactive_component_singleton state family same a x inactive xa,
        inactive_component_singleton state family same a y inactive ya, inactive⟩)
    · exact Or.inr (Or.inr ⟨inactive_component_singleton state family same b x inactive xb,
        inactive_component_singleton state family same b y inactive yb, inactive⟩)
  · rintro (⟨⟨xa, by'⟩, missing⟩ | ⟨rfl, rfl, inactive⟩ | ⟨rfl, rfl, inactive⟩)
    · exact Or.inl ⟨xa, by', missing⟩
    · exact Or.inr (Or.inl ⟨rfl, rfl, inactive⟩)
    · exact Or.inr (Or.inr ⟨rfl, rfl, inactive⟩)

noncomputable def rootFrontierPairs (state : DirectedFrontier.State α)
    (family : Components α C) (roots : List C) (a b : α) : List (C × C) := by
  classical
  exact (rows ⟨roots, roots⟩).filter fun pair => decide (UFRootFrontier state family a b pair)

/-- Candidate completeness follows from finite root/member coverage and the
root predicate, rather than an assumed exact emitted-frontier encoding. -/
theorem root_plan_exact (state : DirectedFrontier.State α) (family : Components α C)
    (roots : List C) (a b : α)
    (complete : ∀ x, x ∈ family.members (family.owner x))
    (covered : ∀ x, family.owner x ∈ roots)
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x) :
    Exact (fun p => DirectedFrontier.ufVisible state p.1 p.2)
      (fun p => DirectedFrontier.ufVisible (DirectedFrontier.extendState state a b) p.1 p.2)
      (componentPlan family (rootFrontierPairs state family roots a b)) := by
  classical
  intro p
  rw [← expansion_member, component_plan_member_iff family _ complete p]
  simp only [rootFrontierPairs, List.mem_filter, decide_eq_true_eq]
  have present : (family.owner p.1, family.owner p.2) ∈ rows ⟨roots, roots⟩ :=
    (rectangle_member _ _ _).mpr ⟨covered _, covered _⟩
  rw [root_frontier_exact state family a b p.1 p.2 same]
  exact ⟨fun h => (DirectedFrontier.uf_emitted_exact state a b p.1 p.2).mp h.2,
    fun h => ⟨present, (DirectedFrontier.uf_emitted_exact state a b p.1 p.2).mpr h⟩⟩

theorem root_plan_nodup (state : DirectedFrontier.State α) (family : Components α C)
    (roots : List C) (a b : α) (unique : roots.Nodup) :
    (expand (componentPlan family (rootFrontierPairs state family roots a b))).Nodup := by
  classical
  apply component_plan_nodup
  exact List.Pairwise.filter _ (rectangle_nodup ⟨roots, roots⟩ unique unique)

/-- Disjointness across consecutive injection frontiers follows from their
history, not from component ownership alone. This justifies additive union. -/
theorem successive_frontiers_disjoint (old middle next : α × α → Prop)
    (left right : List (Rectangle α)) (first : Exact old middle left)
    (second : Exact middle next right) (p : α × α)
    (hl : p ∈ expand left) (hr : p ∈ expand right) : False := by
  have known := (frontier_exact old middle left first p).mp hl
  have fresh := (frontier_exact middle next right second p).mp hr
  exact fresh.2 known.1

theorem successive_union_exact (old middle next : α × α → Prop)
    (left right : List (Rectangle α))
    (growsFirst : ∀ p, old p → middle p)
    (growsSecond : ∀ p, middle p → next p)
    (first : Exact old middle left) (second : Exact middle next right) :
    Exact old next (left ++ right) := by
  classical
  intro p
  rw [← expansion_member]
  simp only [expand, List.flatMap_append, List.mem_append]
  change (p ∈ expand left ∨ p ∈ expand right) ↔ next p ∧ ¬ old p
  rw [frontier_exact old middle left first, frontier_exact middle next right second]
  unfold ProviderFrontier.delta
  constructor
  · rintro (⟨present, fresh⟩ | ⟨present, fresh⟩)
    · exact ⟨growsSecond p present, fresh⟩
    · exact ⟨present, fun old => fresh (growsFirst p old)⟩
  · rintro ⟨present, fresh⟩
    by_cases prior : middle p
    · exact Or.inl ⟨prior, fresh⟩
    · exact Or.inr ⟨present, prior⟩

theorem successive_union_nodup (old middle next : α × α → Prop)
    (left right : List (Rectangle α)) (first : Exact old middle left)
    (second : Exact middle next right) (uniqueLeft : (expand left).Nodup)
    (uniqueRight : (expand right).Nodup) : (expand (left ++ right)).Nodup := by
  rw [expand, List.flatMap_append]
  apply List.nodup_append.mpr
  refine ⟨uniqueLeft, uniqueRight, ?_⟩
  intro p hp q hq same
  subst q
  exact successive_frontiers_disjoint old middle next left right first second p hp hq

/-- The actual equivalence insertion descriptor family: at most two fresh
singleton diagonals and two opposite component rectangles. -/
noncomputable def equivalenceBlocks (state : EquivalenceComponents.State α)
    (a b : α) (left right : List α) : List (Rectangle α) := by
  classical
  exact (if state.active a then [] else [⟨[a], [a]⟩]) ++
    (if state.active b ∨ b = a then [] else [⟨[b], [b]⟩]) ++
    (if EquivalenceComponents.base state a b a b then []
     else [⟨left, right⟩, ⟨right, left⟩])

/-- Coverage is derived from the constructed family rather than assumed as an
Exact frontier contract. Native member extraction remains an explicit bridge. -/
theorem equivalence_blocks_exact (state : EquivalenceComponents.State α)
    (a b : α) (left right : List α)
    (leftExact : ∀ x, x ∈ left ↔ EquivalenceComponents.base state a b x a)
    (rightExact : ∀ y, y ∈ right ↔ EquivalenceComponents.base state a b b y)
    (x y : α) :
    (x, y) ∈ expand (equivalenceBlocks state a b left right) ↔
      EquivalenceComponents.insert state a b x y ∧ ¬ state.rel x y := by
  classical
  rw [← EquivalenceComponents.emitted_exact]
  have flipLeft : EquivalenceComponents.base state a b y a ↔
      EquivalenceComponents.base state a b a y := by
    exact ⟨EquivalenceComponents.base_symm state a b y a,
           EquivalenceComponents.base_symm state a b a y⟩
  have flipRight : EquivalenceComponents.base state a b b x ↔
      EquivalenceComponents.base state a b x b := by
    exact ⟨EquivalenceComponents.base_symm state a b b x,
           EquivalenceComponents.base_symm state a b x b⟩
  have appendMember (u v : List (Rectangle α)) :
      (x, y) ∈ expand (u ++ v) ↔ (x, y) ∈ expand u ∨ (x, y) ∈ expand v := by
    simp [expand, List.flatMap_append]
  have conditional (condition : Prop) (decision : Decidable condition)
      (blocks : List (Rectangle α)) :
      (x, y) ∈ expand (@ite (List (Rectangle α)) condition decision [] blocks) ↔
        ¬ condition ∧ (x, y) ∈ expand blocks := by
    by_cases h : condition <;> simp [h, expand]
  unfold equivalenceBlocks
  rw [appendMember, appendMember, conditional, conditional, conditional]
  simp only [expand, List.flatMap_cons, List.flatMap_nil, List.append_nil,
    List.mem_append, rectangle_member, List.mem_singleton, not_or,
    leftExact, rightExact, flipLeft, flipRight, EquivalenceComponents.emitted,
    EquivalenceComponents.cross]
  simp only [and_comm, and_assoc, or_assoc]

/-- Logical preflight, independent of descriptor storage units. -/
noncomputable def equivalenceNeeded (state : EquivalenceComponents.State α)
    (a b : α) (left right : List α) : Nat := by
  classical
  exact (if state.active a then 0 else 1) +
    (if state.active b ∨ b = a then 0 else 1) +
    (if EquivalenceComponents.base state a b a b then 0
     else 2 * (left.length * right.length))

/-- The constructed descriptor count is exactly the native preflight formula:
fresh diagonals plus both products, with no cross term for a joined class. -/
theorem equivalence_blocks_count (state : EquivalenceComponents.State α)
    (a b : α) (left right : List α) :
    count (equivalenceBlocks state a b left right) =
      equivalenceNeeded state a b left right := by
  classical
  unfold equivalenceBlocks equivalenceNeeded
  split <;> split <;> split <;>
    simp [count, Nat.mul_comm, Nat.mul_two] <;> omega

/-- Logical admission uses the full expansion count even though descriptor
storage has a constant bound. This is not a count of representation units. -/
theorem equivalence_blocks_budget (state : EquivalenceComponents.State α)
    (a b : α) (left right : List α) (budget : Nat) :
    count (equivalenceBlocks state a b left right) ≤ budget ↔
      (expand (equivalenceBlocks state a b left right)).length ≤ budget :=
  budget_exact _ budget

theorem equivalence_blocks_units (state : EquivalenceComponents.State α)
    (a b : α) (left right : List α) :
    (equivalenceBlocks state a b left right).length ≤ 4 := by
  classical
  unfold equivalenceBlocks
  split <;> split <;> split <;> simp

/-- A frozen equivalence total is the square of each admitted component.
Exact partition observations include member identity and the active roster;
aggregate cardinality alone supplies neither of these obligations. -/
theorem component_squares_exact (family : Components α C) (roots : List C)
    (x y : α) :
    (x, y) ∈ expand (componentPlan family (roots.map fun c => (c, c))) ↔
      ∃ c, c ∈ roots ∧ x ∈ family.members c ∧ y ∈ family.members c := by
  simp only [expand, componentPlan, List.map_map, List.mem_flatMap,
    List.mem_map, rectangle_member]
  constructor
  · rintro ⟨block, ⟨c, hc, rfl⟩, hx, hy⟩
    exact ⟨c, hc, hx, hy⟩
  · rintro ⟨c, hc, hx, hy⟩
    exact ⟨⟨family.members c, family.members c⟩, ⟨c, hc, rfl⟩, hx, hy⟩

/-- Equal member lists for every active root determine the complete concrete
relation, without enumerating the Cartesian products. Native extraction of
those lists and exact roster agreement remain explicit bridge obligations. -/
theorem component_squares_partition_equal (left right : Components α C)
    (roots : List C) (same : ∀ c, c ∈ roots → left.members c = right.members c)
    (x y : α) :
    (x, y) ∈ expand (componentPlan left (roots.map fun c => (c, c))) ↔
    (x, y) ∈ expand (componentPlan right (roots.map fun c => (c, c))) := by
  rw [component_squares_exact, component_squares_exact]
  constructor <;> rintro ⟨c, hc, hx, hy⟩
  · exact ⟨c, hc, (same c hc) ▸ hx, (same c hc) ▸ hy⟩
  · exact ⟨c, hc, (same c hc).symm ▸ hx, (same c hc).symm ▸ hy⟩

end Ascent.ProviderRectangles

/-! The materializer prepends into its private output spine, then reverses that
spine once. This law preserves ordered rows, including repeated values; it does
not require the disjointness assumption used for closure cardinality. -/
namespace Ascent.ProviderRectangles

def collect (xs acc : List α) : List α :=
  match xs with
  | [] => acc
  | x :: tail => collect tail (x :: acc)

theorem collect_order (xs acc : List α) : collect xs acc = xs.reverse ++ acc := by
  induction xs generalizing acc with
  | nil => simp [collect]
  | cons x xs ih => simp [collect, ih, List.reverse_cons, List.append_assoc]

theorem materialize_order (rs : List (Rectangle α)) :
    (collect (expand rs) []).reverse = expand rs := by
  simp [collect_order]

theorem materialize_count (rs : List (Rectangle α)) :
    ((collect (expand rs) []).reverse).length = count rs := by
  rw [materialize_order, count_exact]

-- Grouped construction copies the prefix once into each logical tuple.
-- The two-column and one-prefix specializations have the same ordered values.
theorem scalar_tuple (left right : α) : [] ++ [left, right] = [left, right] := rfl
theorem grouped_tuple (group left right : α) :
    [group] ++ [left, right] = [group, left, right] := rfl

end Ascent.ProviderRectangles

/-! Frozen singleton sources can concatenate target member axes, including the
source diagonal. Multi-member sources keep descriptor order. Filtering either
representation must preserve the same ordered row trace. -/
namespace Ascent.ProviderRectangles

def targetBlocks (left : List α) (targets : List (List α)) : List (Rectangle α) :=
  targets.map fun right => ⟨left, right⟩

theorem singleton_capture_order (left : α) (targets : List (List α)) :
    expand (targetBlocks [left] targets) = rows ⟨[left], targets.flatten⟩ := by
  induction targets with
  | nil => simp [expand, targetBlocks, rows]
  | cons first rest ih => simp [expand, targetBlocks, rows] at *; exact ih

def compactCapture (left : List α) (targets : List (List α)) : List (Rectangle α) :=
  match left with
  | [_] => [⟨left, targets.flatten⟩]
  | _ => targetBlocks left targets

theorem compact_capture_order (left : List α) (targets : List (List α)) :
    expand (compactCapture left targets) = expand (targetBlocks left targets) := by
  cases left with
  | nil => rfl
  | cons a tail =>
    cases tail with
    | nil => simpa [compactCapture, expand] using (singleton_capture_order a targets).symm
    | cons b rest => rfl

theorem compact_capture_count (left : List α) (targets : List (List α)) :
    count (compactCapture left targets) = count (targetBlocks left targets) := by
  rw [← count_exact, ← count_exact, compact_capture_order]

theorem compact_capture_selection (left : List α) (targets : List (List α))
    (accept : α × α → Bool) :
    (expand (compactCapture left targets)).filter accept =
      (expand (targetBlocks left targets)).filter accept := by
  rw [compact_capture_order]

end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
-- A conservative descriptor scan may visit extra candidates, but the exact
-- row predicate restores the same ordered output. Arity admission is separate.
theorem conservative_selection (xs : List α) (candidate accept : α → Bool)
    (complete : ∀ x, accept x = true → candidate x = true) :
    (xs.filter candidate).filter accept = xs.filter accept := by
  induction xs with
  | nil => simp
  | cons x xs ih =>
    cases hp : accept x <;> cases hc : candidate x <;> simp [hp, hc, ih]
    exact Bool.noConfusion ((complete x hp).symm.trans hc)
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
-- Refinement of the two tail-recursive loops: fold rights into the owned
-- builder, then advance the left axis without a callback per row.
def collectRight (x : α) (ys : List α) (acc : List (α × α)) :=
  ys.foldl (fun rows y => rows ++ [(x, y)]) acc

def collectProduct (xs ys : List α) (acc : List (α × α)) :=
  xs.foldl (fun rows x => collectRight x ys rows) acc

theorem collect_right_order (x : α) (ys : List α) (acc : List (α × α)) :
    collectRight x ys acc = acc ++ ys.map (fun y => (x, y)) := by
  induction ys generalizing acc with
  | nil => simp [collectRight]
  | cons y ys ih =>
    change collectRight x ys (acc ++ [(x, y)]) = acc ++ List.map (fun y => (x, y)) (y :: ys)
    rw [ih]
    simp [List.append_assoc]

theorem collect_product_order (xs ys : List α) (acc : List (α × α)) :
    collectProduct xs ys acc = acc ++ rows ⟨xs, ys⟩ := by
  induction xs generalizing acc with
  | nil => simp [collectProduct, rows]
  | cons x xs ih =>
    simp only [collectProduct, List.foldl_cons] at *
    rw [ih, collect_right_order]
    simp [rows, List.reverse_append, List.append_assoc]

theorem direct_product_export (xs ys : List α) :
    collectProduct xs ys [] = rows ⟨xs, ys⟩ := by
  simp [collect_product_order]

theorem collect_blocks_order (rs : List (Rectangle α)) (acc : List (α × α)) :
    rs.foldl (fun result r => collectProduct r.left r.right result) acc = acc ++ expand rs := by
  induction rs generalizing acc with
  | nil => simp [expand]
  | cons r rs ih =>
    simp only [List.foldl_cons]
    rw [ih, collect_product_order]
    simp [expand, List.append_assoc]

theorem direct_export_count (rs : List (Rectangle α)) :
    (rs.foldl (fun result r => collectProduct r.left r.right result) []).length = count rs := by
  rw [collect_blocks_order]
  simpa using count_exact rs

-- Once the index owner establishes the selected axis, binding it once has
-- exactly the same ordered Cartesian output as binding it per descriptor.
def bindLeft (rs : List (Rectangle α)) (members : List α) :=
  rs.map fun r => Rectangle.mk members r.right

def bindRight (rs : List (Rectangle α)) (members : List α) :=
  rs.map fun r => Rectangle.mk r.left members

theorem bind_left_order (rs : List (Rectangle α)) (members : List α) :
    expand (bindLeft rs members) = rs.flatMap (fun r => rows ⟨members, r.right⟩) := by
  simp [expand, bindLeft, List.flatMap_map]

theorem bind_right_order (rs : List (Rectangle α)) (members : List α) :
    expand (bindRight rs members) = rs.flatMap (fun r => rows ⟨r.left, members⟩) := by
  simp [expand, bindRight, List.flatMap_map]
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Extensional refinement of an invocation-owned forward list builder. -/
def collectRows (xs : List α) (acc : List α) :=
  xs.foldl (fun rows x => rows ++ [x]) acc

theorem collect_rows_order (xs : List α) (acc : List α) :
    collectRows xs acc = acc ++ xs := by
  induction xs generalizing acc with
  | nil => simp [collectRows]
  | cons x xs ih =>
    change collectRows xs (acc ++ [x]) = acc ++ (x :: xs)
    rw [ih]
    simp [List.append_assoc]

theorem selected_materialization (xs : List α) (accept : α → Bool) :
    collectRows (xs.filter accept) [] = xs.filter accept := by
  simp [collect_rows_order]

-- Cons-cell accounting for complete query results, excluding constant heads,
-- runtime metadata and payload objects. This is not a VM allocation theorem.
def legacyQueryCells (width rows : Nat) := rows * (width + 2)
def ownedQueryCells (width rows : Nat) := rows * (width + 1)

theorem one_spine_released (width rows : Nat) :
    legacyQueryCells width rows = ownedQueryCells width rows + rows := by
  simp [legacyQueryCells, ownedQueryCells, Nat.mul_add, Nat.mul_succ, Nat.add_assoc]

theorem grouped_cell_ratio (rows : Nat) :
    ownedQueryCells 3 rows * 5 = legacyQueryCells 3 rows * 4 := by
  simp [ownedQueryCells, legacyQueryCells, Nat.mul_assoc]
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Sharing a frozen owner plan requires equal axes; Scheme checks identity. -/
theorem self_owner_selection (r : Rectangle α) (same : r.left = r.right)
    (accept : α → Bool) : r.left.filter accept = r.right.filter accept := by
  rw [same]
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Direct product collection also refines bound query axes, in descriptor order.
    Index ownership and checked selector admission remain implementation premises. -/
theorem collect_bound_left_order (rs : List (Rectangle α)) (members : List α) :
    (bindLeft rs members).foldl (fun acc r => collectProduct r.left r.right acc) [] =
      rs.flatMap (fun r => rows ⟨members, r.right⟩) := by
  rw [collect_blocks_order]
  simpa using bind_left_order rs members

theorem collect_bound_right_order (rs : List (Rectangle α)) (members : List α) :
    (bindRight rs members).foldl (fun acc r => collectProduct r.left r.right acc) [] =
      rs.flatMap (fun r => rows ⟨r.left, members⟩) := by
  rw [collect_blocks_order]
  simpa using bind_right_order rs members
end Ascent.ProviderRectangles
