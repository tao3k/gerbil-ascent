-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderRectangles

/-! Public two/three-column UF encoding and event orientation. Option.none is
an ungrouped relation, never an alias of Option.some false. Native values and
nested fields must have stable equality while held by a frozen view. -/
namespace Ascent.ProviderEncoding

def encode (group : Option α) (pair : α × α) : List α :=
  match group with
  | none => [pair.1, pair.2]
  | some g => [g, pair.1, pair.2]

def decode : List α → Option (Option α × (α × α))
  | [x,y] => some (none, (x,y))
  | [g,x,y] => some (some g, (x,y))
  | _ => none

theorem decode_encode (group : Option α) (pair : α × α) :
    decode (encode group pair) = some (group,pair) := by
  cases group <;> cases pair <;> rfl

theorem encode_injective (g h : Option α) (p q : α × α)
    (equal : encode g p = encode h q) : g = h ∧ p = q := by
  have decoded := congrArg decode equal
  rw [decode_encode, decode_encode] at decoded
  exact Prod.mk.inj (Option.some.inj decoded)

theorem scopes_disjoint (g h : Option α) (p q : α × α)
    (different : g ≠ h) : encode g p ≠ encode h q :=
  fun equal => different (encode_injective g h p q equal).1

theorem encoded_member (group : Option α) (pairs : List (α × α)) (p : α × α) :
    encode group p ∈ pairs.map (encode group) ↔ p ∈ pairs := by
  constructor
  · intro present
    obtain ⟨q, member, equal⟩ := List.mem_map.mp present
    exact (encode_injective group group q p equal).2 ▸ member
  · intro member
    exact List.mem_map.mpr ⟨p, member, rfl⟩

theorem encoded_nodup (group : Option α) (pairs : List (α × α))
    (unique : pairs.Nodup) : (pairs.map (encode group)).Nodup := by
  induction pairs with
  | nil => simp
  | cons p pairs ih =>
      have split := List.nodup_cons.mp unique
      apply List.nodup_cons.mpr
      refine ⟨?_, ih split.2⟩
      intro present
      obtain ⟨q, member, equal⟩ := List.mem_map.mp present
      exact split.1 ((encode_injective group group q p equal).2 ▸ member)

theorem encoded_count (group : Option α) (rs : List (ProviderRectangles.Rectangle α)) :
    ((ProviderRectangles.expand rs).map (encode group)).length =
      ProviderRectangles.count rs := by
  rw [List.length_map, ProviderRectangles.count_exact]

theorem encoded_frontier (group : Option α) (old next : α × α → Prop)
    (rs : List (ProviderRectangles.Rectangle α))
    (exact : ProviderRectangles.Exact old next rs) (p : α × α) :
    encode group p ∈ (ProviderRectangles.expand rs).map (encode group) ↔
      next p ∧ ¬ old p := by
  rw [encoded_member, ProviderRectangles.frontier_exact old next rs exact]
  rfl

-- Compose encoding with the constructed root/member plan: no candidate
-- encoding or Exact-frontier premise is assumed at this boundary.
theorem root_plan_encoded_exact (group : Option α) (state : DirectedFrontier.State α)
    (family : ProviderRectangles.Components α C) (roots : List C) (a b : α)
    (complete : ∀ x, x ∈ family.members (family.owner x))
    (covered : ∀ x, family.owner x ∈ roots)
    (same : ∀ x y, family.owner x = family.owner y ↔ state.reach x y ∧ state.reach y x)
    (p : α × α) :
    encode group p ∈ (ProviderRectangles.expand (ProviderRectangles.componentPlan family
      (ProviderRectangles.rootFrontierPairs state family roots a b))).map (encode group) ↔
      DirectedFrontier.ufVisible (DirectedFrontier.extendState state a b) p.1 p.2 ∧
      ¬ DirectedFrontier.ufVisible state p.1 p.2 :=
  encoded_frontier group _ _ _
    (ProviderRectangles.root_plan_exact state family roots a b complete covered same) p

-- Journal orientation changes presentation only, not concretization or budget.
def orient (derived : Bool) (rows : List α) : List α :=
  if derived then rows.reverse else rows

theorem orient_member (derived : Bool) (rows : List α) (x : α) :
    x ∈ orient derived rows ↔ x ∈ rows := by
  cases derived <;> simp [orient]

theorem orient_count (derived : Bool) (rows : List α) :
    (orient derived rows).length = rows.length := by
  cases derived <;> simp [orient]

theorem orient_nodup (derived : Bool) (rows : List α) (unique : rows.Nodup) :
    (orient derived rows).Nodup := by
  cases derived
  · exact unique
  · exact List.pairwise_reverse.mpr (unique.imp Ne.symm)

end Ascent.ProviderEncoding
