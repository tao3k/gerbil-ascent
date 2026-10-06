-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Reindex
import DependencyInvalidation

/-!
Use LeanPoo's Functional.Requirements to expose exactly the typed relation
capabilities a rule head reads. A consumer cannot inspect a relation omitted
from its checklist. This discharges the locality premise of the abstract
dependency-invalidation theorem; correspondence with native lowered plans
remains a separate obligation.
-/

namespace Ascent.FunctionalDependency

open LeanPoo.Functional

universe u v

variable {Key : Type u} {Value : Key → Type v}

abbrev Source (Key : Type u) (Value : Key → Type v) :=
  (key : Key) → Value key

abbrev Family (Value : Key → Type v) (_ : Unit) (key : Key) := Value key

/-- Select read functions independently of a source cut. The current source
is the context supplied when the retained functions are built. -/
def provider : Provider (Source Key Value) Key (fun _ key => Value key) :=
  fun key => some (fun state => state key)

/-- A target lists its body relations in caller order and consumes only the
prepared typed factories. `empty` makes failure behavior explicit, although
this total source provider supplies every key. -/
structure Program (Key : Type u) (Value : Key → Type v) where
  reads : Key → List Key
  empty : (target : Key) → Value target
  evaluate : (target : Key) →
    Requirements.Factories Unit (Family Value) (reads target) → Value target

/-- Preparation depends on the checklist, not on a captured source snapshot. -/
def Program.prepare (program : Program Key Value) (target : Key) :=
  Requirements.prepare (provider (Value := Value)) (program.reads target)

def Program.step (program : Program Key Value) (state : Source Key Value) :
    Source Key Value := fun target =>
  match program.prepare target with
  | .error _ => program.empty target
  | .ok selected => program.evaluate target (Requirements.reindex (fun (_ : Unit) => state) selected)

def Program.edge (program : Program Key Value) (source target : Key) : Prop :=
  source ∈ program.reads target

/-- Context adaptation agrees with independently preparing that exact source
cut, including the complete tuple and first-missing outcome. -/
theorem Program.prepare_at (program : Program Key Value) (target : Key)
    (state : Source Key Value) :
    (program.prepare target).map (Requirements.reindex (fun (_ : Unit) => state)) =
      Requirements.prepare (fun key => some (fun (_ : Unit) => state key))
        (program.reads target) := by
  exact (Requirements.prepare_reindex (fun (_ : Unit) => state)
    (provider (Value := Value)) (program.reads target)).symm

/-- Migration preserves the previous per-cut evaluator result for every
checklist and source, not just the concrete qualification fixture. -/
theorem Program.step_eq_prepared_cut (program : Program Key Value)
    (state : Source Key Value) (target : Key) :
    program.step state target =
      match Requirements.prepare (fun key => some (fun (_ : Unit) => state key))
          (program.reads target) with
      | .error _ => program.empty target
      | .ok selected => program.evaluate target selected := by
  rw [← program.prepare_at target state]
  unfold Program.step
  cases program.prepare target <;> rfl

/-- The producer's context adaptation and checklist equality prove locality.
Only the current source values at requested keys enter the adapted factories. -/
theorem Program.local (program : Program Key Value) :
    DependencyInvalidation.Local program.edge program.step := by
  intro before after target same
  have prepared := Requirements.prepare_congr
    (fun key => some (fun (_ : Unit) => before key))
    (fun key => some (fun (_ : Unit) => after key)) (program.reads target)
    (by
      intro source listed
      simp only [Option.some.injEq]
      exact congrArg (fun value : Value source => fun (_ : Unit) => value)
        (same source listed).symm)
  rw [← program.prepare_at target before, ← program.prepare_at target after] at prepared
  unfold Program.step
  cases selected : program.prepare target with
  | error missing => rfl
  | ok factories =>
    simp only [selected, Except.map, Except.ok.injEq] at prepared
    exact congrArg (program.evaluate target) prepared.symm

theorem Program.completed_frame (program : Program Key Value)
    (affected : Key → Prop)
    (closed : DependencyInvalidation.Closed program.edge affected)
    {before after : Source Key Value}
    (agree : DependencyInvalidation.AgreeOutside affected before after)
    (oldRounds newRounds : Nat)
    (oldStable : program.step
      (DependencyInvalidation.iterate program.step oldRounds before) =
      DependencyInvalidation.iterate program.step oldRounds before)
    (newStable : program.step
      (DependencyInvalidation.iterate program.step newRounds after) =
      DependencyInvalidation.iterate program.step newRounds after) :
    DependencyInvalidation.AgreeOutside affected
      (DependencyInvalidation.iterate program.step oldRounds before)
      (DependencyInvalidation.iterate program.step newRounds after) :=
  DependencyInvalidation.completed_frame program.edge affected program.step
    closed program.local agree oldRounds newRounds oldStable newStable

end Ascent.FunctionalDependency
