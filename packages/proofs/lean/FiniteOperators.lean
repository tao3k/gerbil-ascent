/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Denotational premises for the actual positive higher-order operator vocabulary.
These prove operator monotonicity and least-fixed-point laws, not correctness
of Gerbil's compiler or the Scheme implementation of lexical environments.
-/
import Std

namespace Ascent.Operators

abbrev Relation (α : Type) := α → Prop
def Included {α : Type} (a b : Relation α) := ∀ x, a x → b x
def Increasing {α β : Type} (f : Relation α → Relation β) :=
  ∀ a b, Included a b → Included (f a) (f b)

def union {α : Type} (a b : Relation α) : Relation α := fun x => a x ∨ b x
def select {α : Type} (p : α → Prop) (a : Relation α) : Relation α :=
  fun x => a x ∧ p x
def project {α β : Type} (columns : α → β) (a : Relation α) : Relation β :=
  fun y => ∃ x, a x ∧ columns x = y
def join {α β : Type} (keys : α → β → Prop)
    (a : Relation α) (b : Relation β) : Relation (α × β) :=
  fun row => a row.1 ∧ b row.2 ∧ keys row.1 row.2
def flatmap {α β : Type} (mapping : α → β → Prop)
    (a : Relation α) : Relation β := fun y => ∃ x, a x ∧ mapping x y

theorem union_included {α : Type} (a b c d : Relation α)
    (ha : Included a c) (hb : Included b d) :
    Included (union a b) (union c d) := by
  intro x h
  rcases h with h | h
  · exact Or.inl (ha x h)
  · exact Or.inr (hb x h)

theorem select_increasing {α : Type} (p : α → Prop) : Increasing (select p) := by
  intro a b h x hx
  exact ⟨h x hx.1, hx.2⟩

theorem project_increasing {α β : Type} (columns : α → β) :
    Increasing (project columns) := by
  intro a b h y hy
  obtain ⟨x, hx, heq⟩ := hy
  exact ⟨x, h x hx, heq⟩

theorem join_included {α β : Type} (keys : α → β → Prop)
    (a c : Relation α) (b d : Relation β)
    (ha : Included a c) (hb : Included b d) :
    Included (join keys a b) (join keys c d) := by
  intro row h
  exact ⟨ha row.1 h.1, hb row.2 h.2.1, h.2.2⟩

theorem flatmap_increasing {α β : Type} (mapping : α → β → Prop) :
    Increasing (flatmap mapping) := by
  intro a b h y hy
  obtain ⟨x, hx, hm⟩ := hy
  exact ⟨x, h x hx, hm⟩

theorem composition_increasing {α β γ : Type}
    (f : Relation α → Relation β) (g : Relation β → Relation γ)
    (hf : Increasing f) (hg : Increasing g) : Increasing (fun a => g (f a)) := by
  intro a b h
  exact hg (f a) (f b) (hf a b h)

/- Pointwise function order handles function arguments and returned functions.
   Application needs both function inclusion and argument monotonicity. -/
theorem application_included {α β : Type}
    (f g : Relation α → Relation β) (a b : Relation α)
    (functions : ∀ input, Included (f input) (g input))
    (arguments : Included a b) (hg : Increasing g) : Included (f a) (g b) := by
  intro x hx
  exact hg a b arguments x (functions a x hx)

/- Arbitrarily nested arrows use pointwise order, rather than treating
   function arguments as relation rows. The relation index is the admitted
   finite tuple-universe size, not a claim about unbounded Scheme values. -/
inductive Signature where
  | relation (tuples : Nat)
  | arrow (input output : Signature)

def Meaning : Signature → Type
  | .relation n => Fin n → Prop
  | .arrow a b => Meaning a → Meaning b

def Ordered : (t : Signature) → Meaning t → Meaning t → Prop
  | .relation _, a, b => Included a b
  | .arrow _ output, f, g => ∀ input, Ordered output (f input) (g input)

theorem ordered_refl (t : Signature) (value : Meaning t) : Ordered t value value := by
  induction t with
  | relation n => exact fun _ h => h
  | arrow input output _ ih => exact fun x => ih (value x)

theorem ordered_trans (t : Signature) (a b c : Meaning t)
    (hab : Ordered t a b) (hbc : Ordered t b c) : Ordered t a c := by
  induction t with
  | relation n => exact fun x hx => hbc x (hab x hx)
  | arrow input output _ ih => exact fun x => ih (a x) (b x) (c x) (hab x) (hbc x)

def MonotoneArrow (input output : Signature)
    (function : Meaning (.arrow input output)) :=
  ∀ a b, Ordered input a b → Ordered output (function a) (function b)

theorem nested_application_ordered (input output : Signature)
    (f g : Meaning (.arrow input output)) (a b : Meaning input)
    (functions : Ordered (.arrow input output) f g)
    (arguments : Ordered input a b) (mono : MonotoneArrow input output g) :
    Ordered output (f a) (g b) :=
  ordered_trans output (f a) (g a) (g b) (functions a) (mono a b arguments)

theorem abstraction_ordered (input output : Signature)
    (f g : Meaning input → Meaning output)
    (bodies : ∀ argument, Ordered output (f argument) (g argument)) :
    Ordered (.arrow input output) f g := bodies

def Closed {α : Type} (step : Relation α → Relation α) (s : Relation α) :=
  Included (step s) s
def least {α : Type} (step : Relation α → Relation α) : Relation α :=
  fun x => ∀ s, Closed step s → s x

theorem least_included {α : Type} (step : Relation α → Relation α)
    (s : Relation α) (closed : Closed step s) : Included (least step) s := by
  intro x hx
  exact hx s closed

theorem least_closed {α : Type} (step : Relation α → Relation α)
    (mono : Increasing step) : Closed step (least step) := by
  intro x hx s hs
  exact hs x (mono (least step) s (least_included step s hs) x hx)

theorem least_fixed {α : Type} (step : Relation α → Relation α)
    (mono : Increasing step) : step (least step) = least step := by
  have closed := least_closed step mono
  have imageClosed : Closed step (step (least step)) :=
    mono (step (least step)) (least step) closed
  funext x
  apply propext
  exact ⟨closed x, least_included step (step (least step)) imageClosed x⟩

/- A larger captured source can only enlarge the least fixed point. This is
   the needed monotonicity premise for a closure returning a relational fix. -/
theorem least_parameter_included {α : Type}
    (f g : Relation α → Relation α)
    (steps : ∀ s, Included (f s) (g s)) : Included (least f) (least g) := by
  intro x hx s hs
  apply hx s
  intro y hy
  exact hs y (steps s y hy)

/- Native union admission computes an inflationary step. Its closed models
   are exactly the closed models of the original positive step. -/
theorem inflationary_closed_iff {α : Type}
    (step : Relation α → Relation α) (s : Relation α) :
    Closed (fun input => union input (step input)) s ↔ Closed step s := by
  constructor
  · intro h x hx
    exact h x (Or.inr hx)
  · intro h x hx
    rcases hx with hx | hx
    · exact hx
    · exact h x hx

theorem inflationary_least_eq {α : Type} (step : Relation α → Relation α) :
    least (fun input => union input (step input)) = least step := by
  funext x
  apply propext
  constructor
  · intro h s hs
    exact h s ((inflationary_closed_iff step s).mpr hs)
  · intro h s hs
    exact h s ((inflationary_closed_iff step s).mp hs)

end Ascent.Operators
