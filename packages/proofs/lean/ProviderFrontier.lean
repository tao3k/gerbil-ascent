-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Exact emitted frontier for a monotone concrete relation. These are local
provider and binary-join obligations, not a proof of B23 Theorem 3.5 or a
refinement of Scheme hash tables, arbitrary Providers or lattice values. -/
namespace Ascent.ProviderFrontier

def delta (old next : Row → Prop) (row : Row) : Prop := next row ∧ ¬ old row

theorem concrete_partition (old next : Row → Prop)
    (grows : ∀ row, old row → next row) (row : Row) :
    next row ↔ old row ∨ delta old next row := by
  classical
  constructor
  · intro h
    by_cases prior : old row
    · exact Or.inl prior
    · exact Or.inr ⟨h, prior⟩
  · intro h
    rcases h with prior | fresh
    · exact grows row prior
    · exact fresh.1

theorem new_fact_must_be_emitted (old next emitted : Row → Prop)
    (complete : ∀ row, next row → old row ∨ emitted row)
    (row : Row) (fresh : delta old next row) : emitted row := by
  rcases complete row fresh.1 with prior | present
  · exact False.elim (fresh.2 prior)
  · exact present

def join (left : A → B → Prop) (right : B → C → Prop) (a : A) (c : C) : Prop :=
  ∃ b, left a b ∧ right b c

def changed (old next : A → B → Prop) (a : A) (b : B) : Prop :=
  next a b ∧ ¬ old a b

theorem binary_join_partition
    (oldL nextL : A → B → Prop) (oldR nextR : B → C → Prop)
    (growsL : ∀ a b, oldL a b → nextL a b)
    (growsR : ∀ b c, oldR b c → nextR b c) (a : A) (c : C) :
    join nextL nextR a c ↔ join oldL oldR a c ∨
      join (changed oldL nextL) nextR a c ∨
      join oldL (changed oldR nextR) a c := by
  classical
  constructor
  · rintro ⟨b, left, right⟩
    by_cases priorL : oldL a b
    · by_cases priorR : oldR b c
      · exact Or.inl ⟨b, priorL, priorR⟩
      · exact Or.inr (Or.inr ⟨b, priorL, right, priorR⟩)
    · exact Or.inr (Or.inl ⟨b, ⟨left, priorL⟩, right⟩)
  · intro h
    rcases h with ⟨b, left, right⟩ | ⟨b, left, right⟩ | ⟨b, left, right⟩
    · exact ⟨b, growsL a b left, growsR b c right⟩
    · exact ⟨b, left.1, right⟩
    · exact ⟨b, growsL a b left, right.1⟩

end Ascent.ProviderFrontier
