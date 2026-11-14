-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

/-!
The frame condition behind native dependency invalidation. `reads source
target` must include every positive, negative and aggregate body read of a
target relation. The theorem is independent of the number of fixed-point
rounds; it does not assert that the native compiler constructs that graph.
-/

namespace Ascent.DependencyInvalidation

universe u v

variable {Key : Type u} {Value : Key → Type v}

abbrev State (Key : Type u) (Value : Key → Type v) := (key : Key) → Value key

/-- An affected set is successor closed over the rule-read graph. -/
def Closed (reads : Key → Key → Prop) (affected : Key → Prop) : Prop :=
  ∀ source target, reads source target → affected source → affected target

/-- Every target's next value depends only on the relations it reads. -/
def Local (reads : Key → Key → Prop)
    (step : (State Key Value) → State Key Value) : Prop :=
  ∀ before after target,
    (∀ source, reads source target → before source = after source) →
    step before target = step after target

def AgreeOutside (affected : Key → Prop)
    (before after : State Key Value) : Prop :=
  ∀ target, ¬ affected target → before target = after target

/-- One evaluation round cannot change an unselected target when the read
graph is complete and the affected set is successor closed. -/
theorem step_frame (reads : Key → Key → Prop) (affected : Key → Prop)
    (step : (State Key Value) → State Key Value)
    (closed : Closed reads affected) (locality : Local reads step)
    {before after : State Key Value}
    (agree : AgreeOutside affected before after) :
    AgreeOutside affected (step before) (step after) := by
  intro target untouched
  apply locality before after target
  intro source read
  apply agree source
  intro selected
  exact untouched (closed source target read selected)

/-- Repeated, potentially recursive evaluation from a source snapshot. -/
def iterate (step : (State Key Value) → State Key Value) :
    Nat → (State Key Value) → State Key Value
  | 0, initial => initial
  | n + 1, initial => step (iterate step n initial)

theorem iterate_frame (reads : Key → Key → Prop) (affected : Key → Prop)
    (step : (State Key Value) → State Key Value)
    (closed : Closed reads affected) (locality : Local reads step)
    {before after : State Key Value}
    (agree : AgreeOutside affected before after) (rounds : Nat) :
    AgreeOutside affected (iterate step rounds before)
      (iterate step rounds after) := by
  induction rounds with
  | zero => exact agree
  | succ n ih => exact step_frame reads affected step closed locality ih

theorem iterate_add (step : (State Key Value) → State Key Value)
    (n k : Nat) (initial : State Key Value) :
    iterate step (n + k) initial =
      iterate step k (iterate step n initial) := by
  induction k with
  | zero => rfl
  | succ k ih => exact congrArg step ih

/-- A completed fixed point remains fixed for every later round. -/
theorem stable_tail (step : (State Key Value) → State Key Value)
    (initial : State Key Value) (rounds extra : Nat)
    (stable : step (iterate step rounds initial) =
      iterate step rounds initial) :
    iterate step (rounds + extra) initial =
      iterate step rounds initial := by
  rw [iterate_add]
  induction extra with
  | zero => rfl
  | succ n ih => simp only [iterate, ih, stable]

theorem stable_at_later (step : (State Key Value) → State Key Value)
    (initial : State Key Value) {rounds later : Nat}
    (le : rounds ≤ later)
    (stable : step (iterate step rounds initial) =
      iterate step rounds initial) :
    iterate step later initial = iterate step rounds initial := by
  have sum : rounds + (later - rounds) = later := by omega
  rw [← sum]
  exact stable_tail step initial rounds (later - rounds) stable

/-- Two source snapshots may reach completion in different numbers of
rounds. Their completed values still agree at every unselected relation. -/
theorem completed_frame (reads : Key → Key → Prop)
    (affected : Key → Prop)
    (step : (State Key Value) → State Key Value)
    (closed : Closed reads affected) (locality : Local reads step)
    {before after : State Key Value}
    (agree : AgreeOutside affected before after)
    (oldRounds newRounds : Nat)
    (oldStable : step (iterate step oldRounds before) =
      iterate step oldRounds before)
    (newStable : step (iterate step newRounds after) =
      iterate step newRounds after) :
    AgreeOutside affected (iterate step oldRounds before)
      (iterate step newRounds after) := by
  have equalAtMax := iterate_frame reads affected step closed locality
    agree (max oldRounds newRounds)
  intro target untouched
  calc
    iterate step oldRounds before target =
        iterate step (max oldRounds newRounds) before target := by
          rw [stable_at_later step before (Nat.le_max_left _ _) oldStable]
    _ = iterate step (max oldRounds newRounds) after target :=
      equalAtMax target untouched
    _ = iterate step newRounds after target := by
          rw [stable_at_later step after (Nat.le_max_right _ _) newStable]

end Ascent.DependencyInvalidation
