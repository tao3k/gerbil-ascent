-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Abstract edge insertion and SCC quotient concretization. Native parent
links, component hash tables, budget arithmetic and row encoding are separate
refinement obligations, exercised by native/TLC controls, not proved here. -/
namespace Ascent.TransitiveComponents

def insertEdge (reach : N → N → Prop) (a b x y : N) : Prop :=
  reach x y ∨ (reach x a ∧ reach b y)

theorem preserves_old (reach : N → N → Prop) (a b x y : N)
    (old : reach x y) : insertEdge reach a b x y := Or.inl old

theorem inserted_edge (reach : N → N → Prop) (a b : N)
    (refl : ∀ x, reach x x) : insertEdge reach a b a b :=
  Or.inr ⟨refl a, refl b⟩

theorem insertion_transitive (reach : N → N → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (a b x y z : N) (xy : insertEdge reach a b x y)
    (yz : insertEdge reach a b y z) : insertEdge reach a b x z := by
  rcases xy with xy | ⟨xa, by'⟩
  · rcases yz with yz | ⟨ya, bz⟩
    · exact Or.inl (trans x y z xy yz)
    · exact Or.inr ⟨trans x y a xy ya, bz⟩
  · rcases yz with yz | ⟨_, bz⟩
    · exact Or.inr ⟨xa, trans b y z by' yz⟩
    · exact Or.inr ⟨xa, bz⟩

theorem insertion_least (reach other : N → N → Prop) (a b : N)
    (contains : ∀ x y, reach x y → other x y)
    (edge : other a b)
    (trans : ∀ x y z, other x y → other y z → other x z)
    (x y : N) (new : insertEdge reach a b x y) : other x y := by
  rcases new with old | ⟨xa, by'⟩
  · exact contains x y old
  · exact trans x b y (trans x a b (contains x a xa) edge) (contains b y by')

def compressed (root : N → C) (reach : N → N → Prop) (c d : C) : Prop :=
  ∃ x y, root x = c ∧ root y = d ∧ reach x y

theorem quotient_exact (root : N → C) (reach : N → N → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (same : ∀ x y, root x = root y ↔ reach x y ∧ reach y x)
    (x y : N) : compressed root reach (root x) (root y) ↔ reach x y := by
  constructor
  · rintro ⟨u, v, ux, vy, uv⟩
    have xu : reach x u := ((same x u).mp ux.symm).1
    have vy' : reach v y := ((same v y).mp vy).1
    exact trans x v y (trans x u v xu uv) vy'
  · intro xy
    exact ⟨x, y, rfl, rfl, xy⟩

/-! The following laws apply to the complete *post-insertion* root closure.
They justify retaining the winner's reach table and deleting absorbed keys.
They do not assume that an arbitrary incomplete adjacency table is safe. -/
theorem predecessor_representative (reach : N → N → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (c w x : N) (cw : reach c w) (wc : reach w c) :
    reach x c ↔ reach x w :=
  ⟨fun xc => trans x c w xc cw, fun xw => trans x w c xw wc⟩

theorem successor_representative (reach : N → N → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (c w y : N) (cw : reach c w) (wc : reach w c) :
    reach c y ↔ reach w y :=
  ⟨fun cy => trans w c y wc cy, fun wy => trans c w y cw wy⟩

-- The conditional native cleanup cannot miss an incoming absorbed key.
theorem absorbed_key_cleanup (reach : N → N → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (cycle : N → Prop) (w x c : N)
    (toWinner : ∀ r, cycle r → reach r w)
    (cc : cycle c) (xc : reach x c) : reach x w :=
  trans x c w xc (toWinner c cc)

-- Every outgoing arc of an absorbed root is already in the winner's closure.
theorem winner_inherits_successors (reach : N → N → Prop)
    (trans : ∀ x y z, reach x y → reach y z → reach x z)
    (cycle : N → Prop) (w c y : N)
    (fromWinner : ∀ r, cycle r → reach w r)
    (cc : cycle c) (cy : reach c y) : reach w y :=
  trans w c y (fromWinner c cc) cy

-- A losing component has at most the winner's size. A parent-link step
-- therefore places each losing member in a component at least twice as large.
-- Applying this to actual parent depth additionally requires forest/ownership
-- preservation, covered as operational invariants by the TLA model.
theorem largest_merge_doubles (loser winner rest : Nat)
    (largest : loser ≤ winner) : 2 * loser ≤ loser + winner + rest := by
  omega

end Ascent.TransitiveComponents
