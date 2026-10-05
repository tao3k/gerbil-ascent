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

end Ascent.TransitiveComponents
