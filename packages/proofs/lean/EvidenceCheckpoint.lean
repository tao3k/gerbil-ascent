-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
/-! Generic dependency closure. Host attestations and native refinement are premises. -/
namespace Ascent.EvidenceCheckpoint

def observeCompletion {Unit : Type} [DecidableEq Unit] (seen : List Unit)
    (event : Option Unit) : List Unit :=
  match event with
  | none => seen
  | some unit => if unit ∈ seen then seen else unit :: seen

theorem no_completion_is_not_progress {Unit : Type} [DecidableEq Unit] (seen : List Unit) :
    observeCompletion seen none = seen := rfl

theorem repeated_completion_does_not_advance {Unit : Type} [DecidableEq Unit]
    (seen : List Unit) (unit : Unit) :
    observeCompletion (observeCompletion seen (some unit)) (some unit) =
      observeCompletion seen (some unit) := by
  by_cases member : unit ∈ seen
  · simp [observeCompletion, member]
  · simp [observeCompletion, member]

structure ExecutionPrefix where
  sequence : Nat
  closed : Bool

def appendRecord (s : ExecutionPrefix) : Option ExecutionPrefix :=
  if s.closed then none else some { s with sequence := s.sequence + 1 }

theorem terminal_prefix_rejects_append (s : ExecutionPrefix) (closed : s.closed = true) :
    appendRecord s = none := by simp [appendRecord, closed]

-- Completeness is relative to a declared inventory, never inferred from the
-- absence of a mismatch. Host custody of that inventory remains a premise.
def completeBindings {Key Digest : Type} (required : Key → Prop)
    (recorded current : Key → Digest → Prop) : Prop :=
  ∀ key, required key → ∃ digest, recorded key digest ∧ current key digest

theorem missing_required_binding_is_not_complete {Key Digest : Type}
    (required : Key → Prop) (recorded current : Key → Digest → Prop)
    (key : Key) (needed : required key) (missing : ∀ digest, ¬ recorded key digest) :
    ¬ completeBindings required recorded current := by
  intro complete
  obtain ⟨digest, bound, _⟩ := complete key needed
  exact missing digest bound

structure CommandObservation where
  expectedExit : Int
  actualExit : Option Int
  timedOut : Option Bool
  parentReaped : Option Bool
  groupQuiescent : Option Bool

structure EnumerationWitness (Scope Member : Type) where
  declaredScope : Scope
  observedScope : Scope
  witnessed : Prop
  required : Member → Prop
  supplied : Member → Prop

def EnumerationWitness.grounded {Scope Member : Type} (w : EnumerationWitness Scope Member) : Prop :=
  w.witnessed ∧ w.declaredScope = w.observedScope ∧ ∀ member, w.required member ↔ w.supplied member

theorem omitted_declaration_cannot_be_grounded {Scope Member : Type}
    (w : EnumerationWitness Scope Member) (member : Member)
    (required : w.required member) (omitted : ¬ w.supplied member) : ¬ w.grounded := by
  intro admitted
  exact omitted ((admitted.2.2 member).mp required)

theorem unwitnessed_inventory_cannot_be_grounded {Scope Member : Type}
    (w : EnumerationWitness Scope Member) (missing : ¬ w.witnessed) : ¬ w.grounded := by
  intro admitted
  exact missing admitted.1

theorem wrong_scope_cannot_be_grounded {Scope Member : Type}
    (w : EnumerationWitness Scope Member) (wrong : w.declaredScope ≠ w.observedScope) : ¬ w.grounded := by
  intro admitted
  exact wrong admitted.2.1

theorem explicitly_empty_inventory_is_grounded {Scope Member : Type} (scope : Scope) :
    (EnumerationWitness.mk scope scope True (fun (_ : Member) => False) (fun _ => False)).grounded := by
  exact ⟨True.intro, rfl, fun _ => Iff.rfl⟩

def CommandObservation.satisfied (c : CommandObservation) : Prop :=
  c.actualExit = some c.expectedExit ∧ c.timedOut = some false ∧
  c.parentReaped = some true ∧ c.groupQuiescent = some true

theorem command_without_exit_cannot_satisfy (c : CommandObservation)
    (missing : c.actualExit = none) : ¬ c.satisfied := by
  intro accepted
  simp [CommandObservation.satisfied, missing] at accepted

theorem command_without_quiescence_cannot_satisfy (c : CommandObservation)
    (missing : c.groupQuiescent ≠ some true) : ¬ c.satisfied := by
  intro accepted
  exact missing accepted.2.2.2

inductive Affected {α : Type} (depends : α → α → Prop) (direct : α → Prop) : α → Prop
  | seed {a} : direct a → Affected depends direct a
  | dependent {a p} : depends a p → Affected depends direct p → Affected depends direct a

theorem closure_contains_direct {α : Type} (depends : α → α → Prop)
    (direct : α → Prop) (a : α) (h : direct a) : Affected depends direct a := .seed h

theorem closure_is_dependency_closed {α : Type} (depends : α → α → Prop)
    (direct : α → Prop) (a p : α) (edge : depends a p)
    (h : Affected depends direct p) : Affected depends direct a := .dependent edge h

theorem closure_is_least {α : Type} (depends : α → α → Prop)
    (direct closed : α → Prop) (seeds : ∀ a, direct a → closed a)
    (step : ∀ a p, depends a p → closed p → closed a)
    (a : α) (h : Affected depends direct a) : closed a := by
  induction h with
  | seed h => exact seeds _ h
  | dependent edge _ ih => exact step _ _ edge ih

theorem larger_gap_set_cannot_restore_support {α : Type} (depends : α → α → Prop)
    (before after : α → Prop) (grows : ∀ a, before a → after a)
    (a : α) (h : Affected depends before a) : Affected depends after a := by
  induction h with
  | seed h => exact .seed (grows _ h)
  | dependent edge _ ih => exact .dependent edge ih

structure Evidence (α : Type) where
  historical : α → Prop
  depends : α → α → Prop
  directGap : α → Prop
  materialAvailable : α → Prop
  quiescent : α → Prop

def applicable {α : Type} (s : Evidence α) (a : α) : Prop :=
  s.historical a ∧ ¬ Affected s.depends s.directGap a

def reusable {α : Type} (s : Evidence α) (a : α) : Prop :=
  applicable s a ∧ s.materialAvailable a ∧ s.quiescent a

def clean {α : Type} (s : Evidence α) : Evidence α :=
  { s with materialAvailable := fun _ => False }

def interrupted {α : Type} (s : Evidence α) : Evidence α :=
  { s with quiescent := fun _ => False }

theorem cleanup_keeps_history {α : Type} (s : Evidence α) :
    (clean s).historical = s.historical := rfl

theorem cleanup_keeps_applicability {α : Type} (s : Evidence α) (a : α) :
    applicable (clean s) a ↔ applicable s a := Iff.rfl

theorem restart_is_not_observed_exit {α : Type} (s : Evidence α) (a : α) :
    ¬ reusable (interrupted s) a := by
  intro h
  exact h.2.2

theorem affected_parent_revokes_child {α : Type} (s : Evidence α) (a p : α)
    (edge : s.depends a p) (h : Affected s.depends s.directGap p) :
    ¬ applicable s a := by
  intro current
  exact current.2 (.dependent edge h)

theorem independent_history_remains_applicable {α : Type} (s : Evidence α) (a : α)
    (history : s.historical a) (unaffected : ¬ Affected s.depends s.directGap a) :
    applicable s a := ⟨history, unaffected⟩

-- No evidence observation has an action or authorization field to overwrite.
structure Consumer (α : Type) where
  evidence : Evidence α
  choice : Option String
  executionAuthorized : Bool

def observe {α : Type} (s : Consumer α) (e : Evidence α) : Consumer α :=
  { s with evidence := e }

theorem observation_preserves_choice_and_authority {α : Type}
    (s : Consumer α) (e : Evidence α) :
    (observe s e).choice = s.choice ∧
    (observe s e).executionAuthorized = s.executionAuthorized := ⟨rfl, rfl⟩

end Ascent.EvidenceCheckpoint
