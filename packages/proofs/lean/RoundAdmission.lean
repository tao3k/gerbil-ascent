-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Traversal distance since the most recent successful owner credit.
The period is any positive natural number; these laws do not bound generations
or assert a wall-clock cancellation latency or native mailbox refinement. -/
namespace Ascent.CreditObservation

def traversal (period ticks : Nat) : Nat :=
  if ticks + 1 ≥ period then 0 else ticks + 1

def batchCredit (ticks : Nat) (accepted : Bool) : Nat :=
  if accepted then 0 else ticks

theorem traversal_bounded (period ticks : Nat) (positive : 0 < period) :
    traversal period ticks < period := by
  unfold traversal
  split <;> omega

theorem credit_bounded (period ticks : Nat) (positive : 0 < period)
    (bounded : ticks < period) (accepted : Bool) :
    batchCredit ticks accepted < period := by
  cases accepted <;> simp [batchCredit] <;> assumption

theorem refused_credit_preserves_distance (ticks : Nat) :
    batchCredit ticks false = ticks := rfl

theorem successful_credit_restarts_distance (ticks : Nat) :
    batchCredit ticks true = 0 := rfl

theorem traversal_requires_observation_at_boundary (period ticks : Nat)
    (boundary : ticks + 1 ≥ period) : traversal period ticks = 0 := by
  simp [traversal, boundary]

end Ascent.CreditObservation

/-! Ready-component safety is separate from one component's least fixed point.
These unbounded laws use completed predecessor membership as a premise; they do
not prove Tarjan, canonical head projection or native mailbox refinement. -/


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
