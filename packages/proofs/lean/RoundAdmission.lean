-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Unbounded work-key and cancellation safety for the proposed actor runtime.
Identity fields are opaque logical identifiers, not authentication. This module
does not implement a mailbox, worker termination, merge or native scheduling. -/
namespace Ascent.RoundAdmission

structure Key where
  session : Nat
  generation : Nat
  stratum : Nat
  round : Nat
  program : Nat
  source : Nat
  frontier : Nat
  deriving DecidableEq

structure State (Row : Type) where
  key : Key
  pending : List Nat
  canceled : Bool
  published : List Row

def eligible (state : State Row) (key : Key) (task : Nat) : Prop :=
  state.canceled = false ∧ key = state.key ∧ task ∈ state.pending

instance (state : State Row) (key : Key) (task : Nat) :
    Decidable (eligible state key task) := inferInstanceAs
      (Decidable (state.canceled = false ∧ key = state.key ∧ task ∈ state.pending))

/-- Record terminal acceptance once. Row merge and publication remain separate
owner operations; admitting a reply alone cannot publish candidate rows. -/
def receive (state : State Row) (key : Key) (task : Nat) : State Row :=
  if eligible state key task then
    { state with pending := state.pending.filter (fun next => next != task) }
  else state

def cancel (state : State Row) : State Row :=
  { state with canceled := true
               key := { state.key with generation := state.key.generation + 1 } }

theorem mismatched_key (state : State Row) (key : Key) (task : Nat)
    (different : key ≠ state.key) : receive state key task = state := by
  simp [receive, eligible, different]

theorem stale_generation (state : State Row) (key : Key) (task : Nat)
    (different : key.generation ≠ state.key.generation) :
    receive state key task = state := by
  apply mismatched_key
  intro same
  exact different (congrArg Key.generation same)

theorem duplicate_reply (state : State Row) (key : Key) (task : Nat) :
    receive (receive state key task) key task = receive state key task := by
  by_cases admitted : eligible state key task
  · have absent : ¬ eligible
        { state with pending := state.pending.filter (fun next => next != task) } key task := by
      simp [eligible]
    have first : receive state key task =
        { state with pending := state.pending.filter (fun next => next != task) } :=
      if_pos admitted
    rw [first]
    exact if_neg absent
  · have first : receive state key task = state := if_neg admitted
    rw [first]
    exact first

theorem receive_preserves_publication (state : State Row) (key : Key) (task : Nat) :
    (receive state key task).published = state.published := by
  unfold receive
  split <;> rfl

theorem cancel_preserves_publication (state : State Row) :
    (cancel state).published = state.published := rfl

theorem canceled_reply (state : State Row) (key : Key) (task : Nat) :
    receive (cancel state) key task = cancel state := by
  simp [receive, eligible, cancel]

/-- Re-enabling acceptance after cancellation cannot admit work from the old
generation, even when the phase flag, session and task number are reused. -/
theorem canceled_generation_after_resume (state : State Row) (task : Nat) :
    receive { cancel state with canceled := false } state.key task =
      { cancel state with canceled := false } := by
  apply stale_generation
  simp [cancel]

/-- Pending admission and assigned work are different resources. Stopping
admission cannot certify the return barrier while an assigned worker remains.
These laws describe the native coordinator ownership, not a VM refinement. -/
structure DrainState where
  queued : List Nat
  assigned : List Nat
  stopped : Bool

def stopAdmission (state : DrainState) : DrainState :=
  { state with queued := [], stopped := true }

def returnable (state : DrainState) : Prop :=
  state.queued = [] ∧ state.assigned = []

theorem stop_preserves_assigned (state : DrainState) :
    (stopAdmission state).assigned = state.assigned := rfl

theorem stopped_not_drained (state : DrainState) (task : Nat)
    (running : task ∈ state.assigned) : ¬ returnable (stopAdmission state) := by
  intro returned
  have empty : state.assigned = [] := returned.2
  simp [empty] at running

def acknowledge (state : DrainState) (task : Nat) : DrainState :=
  { state with assigned := state.assigned.filter (fun next => next != task) }

theorem acknowledgment_preserves_stopped (state : DrainState) (task : Nat) :
    (acknowledge state task).stopped = state.stopped := rfl

theorem acknowledged_absent (state : DrainState) (task : Nat) :
    task ∉ (acknowledge state task).assigned := by
  simp [acknowledge]

end Ascent.RoundAdmission
