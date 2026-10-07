-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderRectangles
namespace Ascent.ProviderRectanglesTests
open ProviderRectangles

def bridge : List (Rectangle Nat) := [⟨[0, 1], [2, 3]⟩]
example : expand bridge = [(0, 2), (0, 3), (1, 2), (1, 3)] := by decide
example : count bridge = 4 := by decide
example : ¬ count bridge ≤ 3 := by decide
example : lookup bridge 0 = [(0, 2), (0, 3)] := by decide
example : (expand bridge).Nodup := by decide
-- Descriptor count and logical fact count are different quantities.
example : bridge.length = 1 ∧ count bridge = 4 := by decide
-- Set membership alone fails to prevent overcounting duplicate rectangles.
example : count (bridge ++ bridge) = 8 ∧ ¬ (expand (bridge ++ bridge)).Nodup := by decide
-- Raw injected edges omit an implied bridge pair.
example : (0, 3) ∈ expand bridge ∧ (0, 3) ∉ [(1, 2)] := by decide
-- Empty and diagonal rectangles require no invented active members.
example : count [⟨[], [0, 1]⟩] = 0 := by decide
example : expand [⟨[0], [0]⟩] = [(0, 0)] := by decide

-- A min lattice can ascend in its abstract order while exact winner tuples
-- retract. Set-view monotonicity cannot be inferred from a lawful lattice join.
def winner (n : Nat) (p : Nat × Nat) : Prop := p = (0, n)
example : ¬ (∀ before after : Nat, after ≤ before →
    ∀ p, winner before p → winner after p) := by
  intro monotone
  exact (by simp [winner] : ¬ winner 2 (0, 5)) (monotone 5 2 (by decide) (0, 5) rfl)

#print axioms rectangle_length
#print axioms rectangle_member
#print axioms expansion_member
#print axioms count_exact
#print axioms map_pair_nodup
#print axioms rectangle_nodup
#print axioms expansion_nodup
#print axioms frontier_exact
#print axioms frontier_partition
#print axioms lookup_exact
#print axioms budget_exact
#print axioms duplicate_rectangle
-- A mixed rectangle is a genuine counterexample to whole-rectangle rejection:
-- (0,3) is fresh, but retaining only entirely fresh rectangles loses it.
example : (0, 3) ∈ expand bridge ∧
    (0, 3) ∉ expand (freshRectangles (fun p => p = (0, 2)) bridge) := by
  classical
  constructor
  · decide
  · intro member
    obtain ⟨r, hr, _⟩ := List.mem_flatMap.mp member
    have filtered := List.mem_filter.mp hr
    have same : r = ⟨[0, 1], [2, 3]⟩ := by simpa [bridge] using filtered.1
    subst r
    have fresh : ∀ p ∈ rows (⟨[0, 1], [2, 3]⟩ : Rectangle Nat), p ≠ (0, 2) :=
      by simpa only [decide_eq_true_eq] using filtered.2
    exact fresh (0, 2) (by decide) rfl

#print axioms selected_nodup
#print axioms selected_member
#print axioms uf_selected_exact
#print axioms component_uniform
-- Disjoint members are insufficient when a root pair is repeated.
example : count [⟨[0], [1]⟩, ⟨[0], [1]⟩] = 2 ∧
    ¬ (expand ([⟨[0], [1]⟩, ⟨[0], [1]⟩] : List (Rectangle Nat))).Nodup := by decide
-- Duplicated members violate unique logical cardinality even for one pair.
example : count [⟨[0, 0], [1]⟩] = 2 ∧
    ¬ (expand ([⟨[0, 0], [1]⟩] : List (Rectangle Nat))).Nodup := by decide

#print axioms component_pair_owned
#print axioms component_plan_separate
#print axioms component_plan_nodup
#print axioms component_plan_uniform
#print axioms component_plan_reach_uniform
#print axioms successive_frontiers_disjoint
#print axioms successive_union_exact
#print axioms successive_union_nodup
-- A latent reflexive singleton must not become a visible fact before activation.
private def inactiveSingleton : DirectedFrontier.State Unit where
  active := fun _ => False
  reach := fun _ _ => True
  refl := fun _ => trivial
  trans := fun _ _ _ _ _ => trivial
  supported := fun x y _ => Or.inl (Subsingleton.elim x y)

example : inactiveSingleton.reach () () ∧
    ¬ DirectedFrontier.ufVisible inactiveSingleton () () := by
  simp [inactiveSingleton, DirectedFrontier.ufVisible]

-- SCC equality without supported reach cannot justify activation homogeneity.
-- Universal latent reach and a single root, but mixed active members, lose
-- whole-rectangle homogeneity when the support invariant is omitted.
example : ¬ Uniform (fun p : Bool × Bool => True ∧ p.1 = true ∧ p.2 = true)
    [⟨[false, true], [true]⟩] := by
  intro uniform
  have impossible := uniform ⟨[false, true], [true]⟩ (by simp) (true, true) (by decide)
    (false, true) (by decide) ⟨trivial, rfl, rfl⟩
  exact Bool.noConfusion impossible.2.1

#print axioms component_active_iff
#print axioms component_plan_uf_uniform
#print axioms component_uf_selected_exact
-- Disjoint owned members can still omit a node assigned to that root.
private def omittedMembers : Components Bool Unit where
  members := fun _ => [false]
  owner := fun _ => ()
  owns := fun _ _ _ => rfl
  unique := fun _ => by decide

example : (omittedMembers.owner true, omittedMembers.owner false) ∈ [((), ())] ∧
    (true, false) ∉ expand (componentPlan omittedMembers [((), ())]) := by decide

-- Root enumeration must include the newly activated singleton.
private def singletonFamily : Components Unit Unit where
  members := fun _ => [()]
  owner := fun _ => ()
  owns := fun _ _ _ => rfl
  unique := fun _ => by decide

example : DirectedFrontier.ufEmitted inactiveSingleton () () () () ∧
    expand (componentPlan singletonFamily
      (rootFrontierPairs inactiveSingleton singletonFamily [] () ())) = [] := by
  constructor
  · simp [DirectedFrontier.ufEmitted, DirectedFrontier.ufCandidate,
      DirectedFrontier.cross, DirectedFrontier.ufVisible, inactiveSingleton]
  · simp [rootFrontierPairs, rows, componentPlan, expand]

-- Even a repeated input on an existing cycle has no missing frontier.
example : ¬ UFRootFrontier (DirectedFrontier.extendState inactiveSingleton () ())
    singletonFamily () () ((), ()) := by
  simp [UFRootFrontier, TransitiveComponents.compressed, singletonFamily,
    DirectedFrontier.extendState, DirectedFrontier.activeAfter,
    TransitiveComponents.insertEdge, inactiveSingleton]

#print axioms component_plan_member_iff
#print axioms inactive_component_singleton
#print axioms root_frontier_exact
#print axioms root_plan_exact
#print axioms root_plan_nodup
private def boolFamily : Components Bool Bool where
  members := fun c => [c]
  owner := id
  owns := by intro c x h; simpa using h
  unique := fun _ => by simp

private def emptyBool : DirectedFrontier.State Bool where
  active := fun _ => False
  reach := Eq
  refl := Eq.refl
  trans := fun _ _ _ => Eq.trans
  supported := fun _ _ h => Or.inl h

example : Exact (fun p => DirectedFrontier.ufVisible emptyBool p.1 p.2)
    (fun p => DirectedFrontier.ufVisible (DirectedFrontier.extendState emptyBool false true) p.1 p.2)
    (componentPlan boolFamily (rootFrontierPairs emptyBool boolFamily [false, true] false true)) := by
  apply root_plan_exact
  · intro x; simp [boolFamily]
  · intro x; cases x <;> simp [boolFamily]
  · intro x y; simp [boolFamily, emptyBool, eq_comm]

example : (expand (componentPlan boolFamily
    (rootFrontierPairs emptyBool boolFamily [false, true] false true))).Nodup := by
  exact root_plan_nodup emptyBool boolFamily [false, true] false true (by decide)
end Ascent.ProviderRectanglesTests
