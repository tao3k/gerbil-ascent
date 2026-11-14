-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Algebraic obligations for owned Rayon publication, not a proof of Rust,
Rayon, its memory model, hash implementation, or scheduler performance. -/
namespace Ascent.RayonPublication

def charge (used amount limit : Nat) : Option Nat :=
  if used + amount ≤ limit then some (used + amount) else none

theorem charge_exact (used amount limit next : Nat)
    (ok : charge used amount limit = some next) :
    next = used + amount ∧ next ≤ limit := by
  unfold charge at ok
  split at ok <;> simp_all

theorem batch_charge (used a b limit : Nat) :
    charge used (a + b) limit =
      (charge used a limit).bind (fun next => charge next b limit) := by
  unfold charge
  by_cases first : used + a ≤ limit
  · simp only [first, ↓reduceIte, Option.bind_some]
    simp [Nat.add_assoc]
  · have total : ¬ used + (a + b) ≤ limit := by omega
    simp [first, total]

theorem charge_order (used a b limit : Nat) :
    (charge used a limit).bind (fun next => charge next b limit) =
      (charge used b limit).bind (fun next => charge next a limit) := by
  rw [← batch_charge, ← batch_charge, Nat.add_comm a b]

abbrev Rows (α : Type) := α → Prop
structure Frontier (α : Type) where
  known : Rows α
  pending : Rows α

def combined (state : Frontier α) (fact : α) : Prop :=
  state.known fact ∨ state.pending fact

def publish (owner : α → Nat) (relation : Nat) (state : Frontier α) : Frontier α :=
  ⟨fun fact => state.known fact ∨ (state.pending fact ∧ owner fact = relation),
   fun fact => state.pending fact ∧ owner fact ≠ relation⟩

theorem publish_preserves_union (owner : α → Nat) (relation : Nat)
    (state : Frontier α) (fact : α) :
    combined (publish owner relation state) fact ↔ combined state fact := by
  by_cases head : owner fact = relation <;> simp [combined, publish, head]

theorem publishers_commute (owner : α → Nat) (left right : Nat)
    (state : Frontier α) (fact : α) :
    (publish owner left (publish owner right state)).known fact ↔
      (publish owner right (publish owner left state)).known fact := by
  by_cases l : owner fact = left <;> by_cases r : owner fact = right <;>
    simp_all [publish]

theorem publication_drains_its_relation (owner : α → Nat) (relation : Nat)
    (state : Frontier α) (fact : α) (owned : owner fact = relation) :
    ¬ (publish owner relation state).pending fact := by
  simp [publish, owned]

def admit (state : Frontier α) (candidate : α) : Frontier α :=
  ⟨state.known, fun fact => state.pending fact ∨ (fact = candidate ∧ ¬ state.known candidate)⟩

theorem repeated_admission_is_idempotent (state : Frontier α) (candidate fact : α) :
    (admit (admit state candidate) candidate).pending fact ↔
      (admit state candidate).pending fact := by
  simp [admit]

def checkedEqual [DecidableEq α] (digest : α → Nat) (a b : α) : Bool :=
  decide (digest a = digest b ∧ a = b)

theorem collision_is_not_equality [DecidableEq α] (digest : α → Nat) (a b : α)
    (distinct : a ≠ b) : checkedEqual digest a b = false := by
  simp [checkedEqual, distinct]

/- A lossless decode is the explicit premise for compact value identities.
   This does not prove the Rust interner or extend the supported scalar domain. -/
theorem encoding_preserves_equality (encode : α → Nat) (decode : Nat → Option α)
    (lossless : ∀ value, decode (encode value) = some value) (a b : α) :
    encode a = encode b ↔ a = b := by
  constructor
  · intro same
    have equal : some a = some b := by rw [← lossless a, same, lossless b]
    exact Option.some.inj equal
  · intro same
    simp [same]

def complete (old candidate : α) (canceled expired joined drained : Bool) : α :=
  if !canceled && !expired && joined && drained then candidate else old

theorem late_cancel_preserves_snapshot (old candidate : α) (expired joined drained : Bool) :
    complete old candidate true expired joined drained = old := by simp [complete]

theorem expired_preserves_snapshot (old candidate : α) (canceled joined drained : Bool) :
    complete old candidate canceled true joined drained = old := by simp [complete]

theorem unjoined_preserves_snapshot (old candidate : α) (canceled expired drained : Bool) :
    complete old candidate canceled expired false drained = old := by simp [complete]

theorem incomplete_preserves_snapshot (old candidate : α) (canceled expired joined : Bool) :
    complete old candidate canceled expired joined false = old := by simp [complete]

theorem successful_publication (old candidate : α) :
    complete old candidate false false true true = candidate := by simp [complete]

end Ascent.RayonPublication
