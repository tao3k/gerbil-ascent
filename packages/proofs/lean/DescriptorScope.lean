/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Identity scope preflight for acyclic descriptor unfoldings. Natural keys model
stable descriptor identities, not Scheme symbol spelling. Graph revalidation,
sharing and row typing are separate implementation refinement obligations.
-/
import Std
namespace Ascent.DescriptorScope

inductive Term where
  | source
  | parameter : Nat → Term
  | union : Term → Term → Term
  | bind : Nat → Term → Term

def Free : Term → Nat → Prop
  | .source, _ => False
  | .parameter identity, key => key = identity
  | .union a b, key => Free a key ∨ Free b key
  | .bind identity body, key => Free body key ∧ key ≠ identity

def Scoped : List Nat → Term → Prop
  | _, .source => True
  | context, .parameter identity => identity ∈ context
  | context, .union a b => Scoped context a ∧ Scoped context b
  | context, .bind identity body => Scoped (identity :: context) body

theorem free_bound_iff_scoped (term : Term) (context : List Nat) :
    (∀ key, Free term key → key ∈ context) ↔ Scoped context term := by
  induction term generalizing context with
  | source => simp [Free, Scoped]
  | parameter identity => simp [Free, Scoped]
  | union a b ia ib =>
    simp only [Free, Scoped]
    constructor
    · intro h
      exact ⟨(ia context).mp (fun key hk => h key (Or.inl hk)),
        (ib context).mp (fun key hk => h key (Or.inr hk))⟩
    · intro h key hk
      exact hk.elim ((ia context).mpr h.1 key) ((ib context).mpr h.2 key)
  | bind identity body ih =>
    change (∀ key, Free body key ∧ key ≠ identity → key ∈ context) ↔ Scoped (identity :: context) body
    rw [← ih (identity :: context)]
    constructor
    · intro h key hk
      by_cases eq : key = identity
      · simp [eq]
      · exact List.mem_cons_of_mem identity (h key ⟨hk, eq⟩)
    · intro h key hk
      have member := h key hk.1
      simp only [List.mem_cons] at member
      exact member.elim (fun eq => False.elim (hk.2 eq)) id

theorem closed_iff_scoped (term : Term) :
    (∀ key, ¬ Free term key) ↔ Scoped [] term := by
  have h := free_bound_iff_scoped term []
  simpa using h

theorem escaped_parameter_rejects (term : Term) (key : Nat) (escaped : Free term key) :
    ¬ Scoped [] term := by
  intro accepted
  exact ((closed_iff_scoped term).mpr accepted key) escaped

theorem scope_extension (term : Term) (a b : List Nat)
    (included : ∀ key, key ∈ a → key ∈ b) (accepted : Scoped a term) : Scoped b term :=
  (free_bound_iff_scoped term b).mp
    (fun key free => included key ((free_bound_iff_scoped term a).mpr accepted key free))

theorem binding_capture (key : Nat) : Scoped [] (.bind key (.parameter key)) := by
  simp [Scoped]

theorem distinct_binding_does_not_capture (a b : Nat) (distinct : a ≠ b) :
    ¬ Scoped [] (.bind a (.parameter b)) := by
  simp [Scoped, Ne.symm distinct]

theorem shared_child_cannot_escape (body : Term) (key : Nat)
    (free : Free body key) : ¬ Scoped [] (.union (.bind key body) body) :=
  escaped_parameter_rejects _ key (Or.inr free)

end Ascent.DescriptorScope
