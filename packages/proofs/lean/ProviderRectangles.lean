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

/-- A frozen owner index is exact for each axis; globally present endpoints
from different owners cannot form a Cartesian row. -/
theorem indexed_rectangle_member (r : Rectangle α) (leftIndex rightIndex : α → Prop)
    (leftExact : ∀ x, leftIndex x ↔ x ∈ r.left)
    (rightExact : ∀ y, rightIndex y ↔ y ∈ r.right) (x y : α) :
    (x, y) ∈ rows r ↔ leftIndex x ∧ rightIndex y := by
  rw [rectangle_member, ← leftExact x, ← rightExact y]

/-- An exact carrier-local membership test preserves ordered difference export. -/
theorem indexed_difference_order [DecidableEq α] (newer older : List (Rectangle α))
    (probe : α × α → Bool) (exact : ∀ p, probe p = decide (p ∈ expand older)) :
    (expand newer).filter (fun p => !probe p) =
      (expand newer).filter (fun p => decide (p ∉ expand older)) := by
  congr 1
  funext p
  rw [exact]
  by_cases h : p ∈ expand older <;> simp [h]

end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Invocation-owned keys: repeated coordinates retain all equality obligations. -/
def CoordinateKeys (query : List (Nat × α)) (coordinate : Nat) : List α :=
  (query.filter fun binding => binding.1 == coordinate).map Prod.snd

theorem coordinate_keys_member [BEq α] (query : List (Nat × α))
    (coordinate : Nat) (value : α) :
    value ∈ CoordinateKeys query coordinate ↔ (coordinate, value) ∈ query := by
  simp [CoordinateKeys, List.mem_map, List.mem_filter, Prod.ext_iff]

def MatchesConditions (row : Nat → α) (query : List (Nat × α)) : Prop :=
  ∀ binding ∈ query, row binding.1 = binding.2

def MatchesBindings (row : Nat → α) (query : List (Nat × α)) : Prop :=
  ∀ coordinate value, value ∈ CoordinateKeys query coordinate → row coordinate = value

theorem coordinate_binding_refinement [BEq α] (row : Nat → α) (query : List (Nat × α)) :
    MatchesBindings row query ↔ MatchesConditions row query := by
  constructor
  · intro h binding member
    exact h binding.1 binding.2 ((coordinate_keys_member query binding.1 binding.2).mpr member)
  · intro h coordinate value member
    exact h (coordinate, value) ((coordinate_keys_member query coordinate value).mp member)

/-- Conflicting repeats cannot admit a row, irrespective of routing choice. -/
theorem conflicting_conditions_empty (row : Nat → α) (query : List (Nat × α))
    (coordinate : Nat) (a b : α) (ha : (coordinate, a) ∈ query)
    (hb : (coordinate, b) ∈ query) (different : a ≠ b) :
    ¬ MatchesConditions row query := by
  intro accepts
  exact different ((accepts (coordinate, a) ha).symm.trans (accepts (coordinate, b) hb))

/-- A first-binding vector refines all constraints if compilation checked
    every repeat. Owner lookup and coordinate range admission are separate
    implementation premises; this law does not prove hash-table correctness. -/
theorem first_binding_refinement (row : Nat → α) (query : List (Nat × α))
    (bindings : Nat → Option α)
    (covered : ∀ c v, (c, v) ∈ query → bindings c = some v)
    (grounded : ∀ c v, bindings c = some v → (c, v) ∈ query) :
    (∀ c v, bindings c = some v → row c = v) ↔ MatchesConditions row query := by
  constructor
  · intro h binding member
    exact h binding.1 binding.2 (covered binding.1 binding.2 member)
  · intro h c v bound
    exact h (c, v) (grounded c v bound)

/-- Exact per-row acceptance preserves descriptor/member order and duplicates. -/
theorem compiled_query_order (input : List β) (baseline compiled : β → Bool)
    (exact : ∀ row, compiled row = baseline row) :
    input.filter compiled = input.filter baseline := by
  congr 1
  funext row
  exact exact row
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Merge frozen descriptor ordinals. Construction supplies strict ascending
    order and one entry per descriptor; traversal owns only the two cursors. -/
def mergeOrdinals : List Nat → List Nat → List Nat
  | [], _ => []
  | _, [] => []
  | a :: as, b :: bs =>
      if a < b then mergeOrdinals as (b :: bs)
      else if b < a then mergeOrdinals (a :: as) bs
      else a :: mergeOrdinals as bs
termination_by xs ys => xs.length + ys.length

/-- Every emitted ordinal belongs to both captured endpoint plans, excluding
    cross-owner admission without assuming globally unique endpoint values. -/
theorem merge_ordinals_sound (xs ys : List Nat) (n : Nat)
    (member : n ∈ mergeOrdinals xs ys) : n ∈ xs ∧ n ∈ ys := by
  match xs, ys with
  | [], _ => simp [mergeOrdinals] at member
  | _ :: _, [] => simp [mergeOrdinals] at member
  | a :: as, b :: bs =>
    by_cases ab : a < b
    · simp only [mergeOrdinals, ite_eq_left ab] at member
      obtain ⟨left, right⟩ := merge_ordinals_sound as (b :: bs) n member
      exact ⟨List.mem_cons_of_mem a left, right⟩
    · by_cases ba : b < a
      · simp only [mergeOrdinals, ite_eq_right ab, ite_eq_left ba] at member
        obtain ⟨left, right⟩ := merge_ordinals_sound (a :: as) bs n member
        exact ⟨left, List.mem_cons_of_mem b right⟩
      · have same : a = b := by omega
        simp only [mergeOrdinals, ite_eq_right ab, ite_eq_right ba, List.mem_cons] at member
        rcases member with head | tail
        · subst n; simp [same]
        · obtain ⟨left, right⟩ := merge_ordinals_sound as bs n tail
          exact ⟨List.mem_cons_of_mem a left, List.mem_cons_of_mem b right⟩
termination_by xs.length + ys.length

/-- Strictly increasing frozen plans cannot lose a common descriptor when
    the smaller cursor advances. Admission must establish these premises. -/
theorem merge_ordinals_complete (xs ys : List Nat)
    (orderedX : xs.Pairwise (· < ·)) (orderedY : ys.Pairwise (· < ·))
    (n : Nat) (left : n ∈ xs) (right : n ∈ ys) : n ∈ mergeOrdinals xs ys := by
  match xs, ys with
  | [], _ => simp at left
  | _ :: _, [] => simp at right
  | a :: as, b :: bs =>
    have hx := List.pairwise_cons.mp orderedX
    have hy := List.pairwise_cons.mp orderedY
    by_cases ab : a < b
    · have tail : n ∈ as := by
        rcases List.mem_cons.mp left with head | tail
        · rcases List.mem_cons.mp right with same | later
          · omega
          · have lower := hy.1 n later; omega
        · exact tail
      simp only [mergeOrdinals, ite_eq_left ab]
      exact merge_ordinals_complete as (b :: bs) hx.2 orderedY n tail right
    · by_cases ba : b < a
      · have tail : n ∈ bs := by
          rcases List.mem_cons.mp right with head | tail
          · rcases List.mem_cons.mp left with same | later
            · omega
            · have lower := hx.1 n later; omega
          · exact tail
        simp only [mergeOrdinals, ite_eq_right ab, ite_eq_left ba]
        exact merge_ordinals_complete (a :: as) bs orderedX hy.2 n left tail
      · have same : a = b := by omega
        simp only [mergeOrdinals, ite_eq_right ab, ite_eq_right ba, List.mem_cons]
        by_cases head : n = a
        · exact Or.inl head
        · have lx : n ∈ as := (List.mem_cons.mp left).resolve_left head
          have ly : n ∈ bs := (List.mem_cons.mp right).resolve_left (by simpa [same] using head)
          exact Or.inr (merge_ordinals_complete as bs hx.2 hy.2 n lx ly)
termination_by xs.length + ys.length

/-- Each emitted plan remains strictly ordered and has no repeated ordinal. -/
theorem merge_ordinals_ordered (xs ys : List Nat)
    (orderedX : xs.Pairwise (· < ·)) (orderedY : ys.Pairwise (· < ·)) :
    (mergeOrdinals xs ys).Pairwise (· < ·) := by
  match xs, ys with
  | [], _ => simp [mergeOrdinals]
  | _ :: _, [] => simp [mergeOrdinals]
  | a :: as, b :: bs =>
    have hx := List.pairwise_cons.mp orderedX
    have hy := List.pairwise_cons.mp orderedY
    by_cases ab : a < b
    · simp only [mergeOrdinals, ite_eq_left ab]
      exact merge_ordinals_ordered as (b :: bs) hx.2 orderedY
    · by_cases ba : b < a
      · simp only [mergeOrdinals, ite_eq_right ab, ite_eq_left ba]
        exact merge_ordinals_ordered (a :: as) bs orderedX hy.2
      · simp only [mergeOrdinals, ite_eq_right ab, ite_eq_right ba, List.pairwise_cons]
        exact ⟨fun n member => hx.1 n (merge_ordinals_sound as bs n member).1,
          merge_ordinals_ordered as bs hx.2 hy.2⟩
termination_by xs.length + ys.length

/-- A merge iteration advances at least one cursor. This bounds traversal
    work independently of endpoint cardinality or the number of key repeats. -/
def mergeSteps : List Nat → List Nat → Nat
  | [], _ => 0
  | _, [] => 0
  | a :: as, b :: bs =>
      1 + if a < b then mergeSteps as (b :: bs)
          else if b < a then mergeSteps (a :: as) bs else mergeSteps as bs
termination_by xs ys => xs.length + ys.length

theorem merge_steps_linear (xs ys : List Nat) :
    mergeSteps xs ys ≤ xs.length + ys.length := by
  match xs, ys with
  | [], _ => simp [mergeSteps]
  | _ :: _, [] => simp [mergeSteps]
  | a :: as, b :: bs =>
    by_cases ab : a < b
    · have bound := merge_steps_linear as (b :: bs)
      simp only [mergeSteps, ite_eq_left ab, List.length_cons] at *
      omega
    · by_cases ba : b < a
      · have bound := merge_steps_linear (a :: as) bs
        simp only [mergeSteps, ite_eq_right ab, ite_eq_left ba, List.length_cons] at *
        omega
      · have bound := merge_steps_linear as bs
        simp only [mergeSteps, ite_eq_right ab, ite_eq_right ba, List.length_cons] at *
        omega
termination_by xs.length + ys.length

/-- A complete ordered key needs no coordinate table: coverage and grounding
    reduce the selector to a point obligation within the admitted row width. -/
theorem complete_key_refinement (width : Nat) (row key : Nat → α)
    (query : List (Nat × α))
    (covered : ∀ c, c < width → (c, key c) ∈ query)
    (grounded : ∀ binding ∈ query, binding.1 < width ∧ binding.2 = key binding.1) :
    MatchesConditions row query ↔ ∀ c, c < width → row c = key c := by
  constructor
  · intro accepts c bound
    exact accepts (c, key c) (covered c bound)
  · intro point binding member
    obtain ⟨bound, value⟩ := grounded binding member
    exact (point binding.1 bound).trans value.symm
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles

/-- Candidate narrowing is exact when every point answer retains its owner.
    Filtering never changes the captured descriptor order. -/
theorem point_candidate_refinement (rows : List α) (candidate point : α → Bool)
    (covered : ∀ row, point row = true → candidate row = true) :
    (rows.filter candidate).filter point = rows.filter point := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    by_cases accepts : point row = true
    · simp [List.filter, accepts, covered row accepts, ih]
    · by_cases retained : candidate row = true
      · simp [List.filter, accepts, retained, ih]
      · simp [List.filter, accepts, retained, ih]

/-- Tiny constructor associations use owner identity, never member equality. -/
def ownerLookup (owner : Nat) : List (Nat × α) → Option α
  | [] => none
  | (id, value) :: rest => if id = owner then some value else ownerLookup owner rest

theorem owner_lookup_stored (owner : Nat) (stored : α) (rest : List (Nat × α)) :
    ownerLookup owner ((owner, stored) :: rest) = some stored := by
  simp [ownerLookup]

theorem owner_lookup_other (owner id : Nat) (stored : α) (rest : List (Nat × α))
    (distinct : id ≠ owner) :
    ownerLookup owner ((id, stored) :: rest) = ownerLookup owner rest := by
  simp [ownerLookup, distinct]

/-- A two-descriptor construction has a fixed upper bound on identity probes. -/
def ownerProbes (owner : Nat) : List (Nat × α) → Nat
  | [] => 0
  | (id, _) :: rest => 1 + if id = owner then 0 else ownerProbes owner rest

theorem owner_probes_bounded (owner : Nat) (entries : List (Nat × α)) :
    ownerProbes owner entries ≤ entries.length := by
  induction entries with
  | nil => simp [ownerProbes]
  | cons entry rest ih =>
    rcases entry with ⟨id, value⟩
    by_cases same : id = owner <;> simp [ownerProbes, same] <;> omega

theorem tiny_owner_probes (owner : Nat) (entries : List (Nat × α))
    (tiny : entries.length ≤ 2) : ownerProbes owner entries ≤ 2 :=
  Nat.le_trans (owner_probes_bounded owner entries) tiny

end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Bounded head admission plus an exact owner route is full membership.
    The head shortcut must be sound; a miss always falls back to the route. -/
theorem bounded_head_route_refinement (members : List α) (value : α) :
    (value ∈ members.take 4 ∨ value ∈ members) ↔ value ∈ members := by
  constructor
  · intro hit
    rcases hit with head | routed
    · exact List.mem_of_mem_take head
    · exact routed
  · exact Or.inr
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Compact layouts retain the first value of each slot, including false-like
values. Absence is represented separately; query order is not a layout. -/
def compactSlots (group left right : Option α) : Nat → Option α
  | 0 => group
  | 1 => left
  | 2 => right
  | _ => none

theorem compact_slots_acceptance (row : Nat → α) (group left right : Option α) :
    (∀ c v, compactSlots group left right c = some v → row c = v) ↔
    (∀ v, group = some v → row 0 = v) ∧
    (∀ v, left = some v → row 1 = v) ∧
    (∀ v, right = some v → row 2 = v) := by
  constructor
  · intro h
    exact ⟨h 0, h 1, h 2⟩
  · rintro ⟨hg, hl, hr⟩ c v h
    cases c with
    | zero => exact hg v h
    | succ c =>
      cases c with
      | zero => exact hl v h
      | succ c =>
        cases c with
        | zero => exact hr v h
        | succ c => simp [compactSlots] at h

/-- Scalar slots refine the complete condition list when compilation checked
all repeats. This supplies the same acceptance premise as the vector plan,
without requiring a retained vector or changing row order. -/
theorem compact_query_refinement (row : Nat → α) (query : List (Nat × α))
    (group left right : Option α)
    (covered : ∀ c v, (c, v) ∈ query → compactSlots group left right c = some v)
    (grounded : ∀ c v, compactSlots group left right c = some v → (c, v) ∈ query) :
    ((∀ v, group = some v → row 0 = v) ∧
     (∀ v, left = some v → row 1 = v) ∧
     (∀ v, right = some v → row 2 = v)) ↔ MatchesConditions row query :=
  (compact_slots_acceptance row group left right).symm.trans
    (first_binding_refinement row query (compactSlots group left right) covered grounded)
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Frozen plans are deliberately partial indexes. Only present plans promise
an exact answer; a missing cache entry preserves the independent fallback. -/
theorem partial_plan_refinement (answer : List α) (cached : Option (List α))
    (present_exact : ∀ rows, cached = some rows → rows = answer) :
    cached.getD answer = answer := by
  cases cached with
  | none => rfl
  | some rows => exact present_exact rows rfl
end Ascent.ProviderRectangles

namespace Ascent.ProviderRectangles
/-- Descriptor costs select a covered route; they never replace its query
predicate. The native implementation borrows a bucket or ordered axis plan. -/
structure RoutingCandidate (α : Type) where
  predicate : α → Bool
  cost : Nat

def narrowRouting (current next : RoutingCandidate α) : RoutingCandidate α :=
  if next.cost < current.cost then next else current

theorem narrow_routing_cost (current next : RoutingCandidate α) :
    (narrowRouting current next).cost ≤ current.cost := by
  unfold narrowRouting
  split
  · exact Nat.le_of_lt ‹next.cost < current.cost›
  · exact Nat.le_refl _

theorem narrow_routing_coverage (accept : α → Bool) (current next : RoutingCandidate α)
    (current_covers : ∀ row, accept row = true → current.predicate row = true)
    (next_covers : ∀ row, accept row = true → next.predicate row = true) :
    ∀ row, accept row = true → (narrowRouting current next).predicate row = true := by
  intro row accepted
  unfold narrowRouting
  split
  · exact next_covers row accepted
  · exact current_covers row accepted

theorem narrow_routing_query_refinement (rows : List α) (accept : α → Bool)
    (current next : RoutingCandidate α)
    (current_covers : ∀ row, accept row = true → current.predicate row = true)
    (next_covers : ∀ row, accept row = true → next.predicate row = true) :
    (rows.filter (narrowRouting current next).predicate).filter accept = rows.filter accept :=
  point_candidate_refinement rows (narrowRouting current next).predicate accept
    (narrow_routing_coverage accept current next current_covers next_covers)
end Ascent.ProviderRectangles
