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

/-! Ready-component safety is separate from one component's least fixed point.
These unbounded laws use completed predecessor membership as a premise; they do
not prove Tarjan, canonical head projection or native mailbox refinement. -/
namespace Ascent.ReadyComponents

def ready (predecessors : Nat → List Nat) (done : List Nat) (task : Nat) : Bool :=
  (predecessors task).all (fun parent => done.contains parent)

theorem ready_parent_completed (predecessors : Nat → List Nat) (done : List Nat)
    (task parent : Nat) (allowed : ready predecessors done task = true)
    (required : parent ∈ predecessors task) : parent ∈ done := by
  simp only [ready, List.all_eq_true] at allowed
  simpa using allowed parent required

structure State where
  queued : List Nat
  active : List Nat
  done : List Nat

def complete (state : State) (task : Nat) : State :=
  if task ∈ state.active then
    { state with active := state.active.filter (fun next => next != task),
                 done := task :: state.done }
  else state

theorem unassigned_completion (state : State) (task : Nat)
    (foreign : task ∉ state.active) : complete state task = state := by
  simp [complete, foreign]

theorem completed_absent (state : State) (task : Nat) :
    task ∉ (complete state task).active := by
  by_cases assigned : task ∈ state.active
  · simp [complete, assigned]
  · simpa [complete, assigned] using assigned

theorem duplicate_completion (state : State) (task : Nat) :
    complete (complete state task) task = complete state task := by
  exact unassigned_completion _ _ (completed_absent state task)

/-- An unrelated still-running component is deliberately not a readiness
premise. Completed prerequisites suffice regardless of other active work. -/
theorem independent_active_does_not_block (predecessors : Nat → List Nat)
    (left right : State) (task : Nat) (sameDone : left.done = right.done) :
    ready predecessors left.done task = ready predecessors right.done task := by
  rw [sameDone]
end Ascent.ReadyComponents

/-! Cache identity laws use unbounded natural identities as an abstraction of
native object identity. Only completed immutable metadata is published; these
laws do not refine native weak-key lifetime, mutexes or allocation ownership. -/
namespace Ascent.ComponentPlanCache

abbrev Slot (α : Type) := Option (Nat × α)

def lookup (slot : Slot α) (identity : Nat) : Option α :=
  match slot with
  | none => none
  | some (key, plan) => if key = identity then some plan else none

def publish (slot : Slot α) (identity : Nat) (completed : Option α) : Slot α :=
  match completed with
  | none => slot
  | some plan => some (identity, plan)

theorem exact_identity_hit (identity : Nat) (plan : α) :
    lookup (some (identity, plan)) identity = some plan := by
  simp [lookup]

theorem different_identity_miss (key identity : Nat) (plan : α)
    (changed : key ≠ identity) : lookup (some (key, plan)) identity = none := by
  simp [lookup, changed]

theorem failed_build_preserves (slot : Slot α) (identity : Nat) :
    publish slot identity none = slot := by
  rfl

theorem completed_build_hit (slot : Slot α) (identity : Nat) (plan : α) :
    lookup (publish slot identity (some plan)) identity = some plan := by
  simp [publish, lookup]

end Ascent.ComponentPlanCache

/-! Ordered index extension models bucket membership with an arbitrary Boolean
key predicate. Native reversal traverses only the admitted batch; old row roots
are retained. This does not refine native hash storage, mutation or mutexes. -/
namespace Ascent.ComponentIndex

def bucket (accepts : α → Bool) (rows : List α) : List α := rows.filter accepts

def extendBucket (accepts : α → Bool) (batch old : List α) : List α :=
  batch.foldr (fun row rest => if accepts row then row :: rest else rest) old

theorem extension_order (accepts : α → Bool) (batch old : List α) :
    extendBucket accepts batch old = bucket accepts batch ++ old := by
  induction batch with
  | nil => simp [extendBucket, bucket]
  | cons row rest ih =>
    simp only [extendBucket, List.foldr_cons] at *
    cases h : accepts row <;> simp [bucket, h, ih]

theorem reverse_traversal_order (accepts : α → Bool) (batch old : List α) :
    batch.reverse.foldl (fun rest row => if accepts row then row :: rest else rest) old =
      bucket accepts batch ++ old := by
  rw [← List.foldr_eq_foldl_reverse]
  exact extension_order accepts batch old

theorem extension_equals_rebuild (accepts : α → Bool) (batch old : List α) :
    extendBucket accepts batch (bucket accepts old) = bucket accepts (batch ++ old) := by
  rw [extension_order]
  simp [bucket]

end Ascent.ComponentIndex
