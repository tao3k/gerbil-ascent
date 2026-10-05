-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPoo.Functional.Requirements
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

/-- Every read capability is a constant factory over the current cut. -/
def provider (state : Source Key Value) : Provider Unit Key (Family Value) :=
  fun key => some (fun _ => state key)

/-- A target lists its body relations in caller order and consumes only the
prepared typed factories. `empty` makes failure behavior explicit, although
this total source provider supplies every key. -/
structure Program (Key : Type u) (Value : Key → Type v) where
  reads : Key → List Key
  empty : (target : Key) → Value target
  evaluate : (target : Key) →
    Requirements.Factories Unit (Family Value) (reads target) → Value target

def Program.step (program : Program Key Value) (state : Source Key Value) :
    Source Key Value := fun target =>
  match Requirements.prepare (provider state) (program.reads target) with
  | .error _ => program.empty target
  | .ok selected => program.evaluate target selected

def Program.edge (program : Program Key Value) (source target : Key) : Prop :=
  source ∈ program.reads target

/-- LeanPoo's whole-checklist equality closes the per-rule locality gap: a
source change outside a head's declared reads preserves its complete prepared
factory tuple, including failure behavior. -/
theorem Program.local (program : Program Key Value) :
    DependencyInvalidation.Local program.edge program.step := by
  intro before after target same
  have prepared := Requirements.prepare_congr
    (provider before) (provider after) (program.reads target)
    (by
      intro source listed
      simp only [provider, Option.some.injEq]
      exact congrArg (fun value : Value source => fun (_ : Unit) => value)
        (same source listed).symm)
  simp only [Program.step, prepared]

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
