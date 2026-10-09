/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
Current-cut one-based occurrence selection retains duplicate values separately.
Native decoding and grounded graph coverage remain representation obligations.
-/
import Std
namespace Ascent.SourceOccurrences
variable {Row : Type}
def withdraw (rows : List Row) (selected : List Nat) : List Row :=
  ((rows.zipIdx 1).filter (fun entry => decide (entry.2 ∉ selected))).map Prod.fst
/-- A value survives precisely when some unselected occurrence supports it. -/
theorem survives (rows : List Row) (selected : List Nat) (row : Row) :
    row ∈ withdraw rows selected ↔
      ∃ occurrence ∈ rows.zipIdx 1, occurrence.1 = row ∧ occurrence.2 ∉ selected := by
  simp only [withdraw, List.mem_map, List.mem_filter, decide_eq_true_eq]
  constructor
  · rintro ⟨occurrence, ⟨present, retained⟩, value⟩
    exact ⟨occurrence, present, value, retained⟩
  · rintro ⟨occurrence, present, value, retained⟩
    exact ⟨occurrence, ⟨present, retained⟩, value⟩
/-- The prospective source and evidence become visible through one publication. -/
structure Cut (Source Evidence : Type) where
  generation : Nat
  source : Source
  evidence : Evidence
  deriving DecidableEq
def publish (old next : Cut Source Evidence) (expected : Nat) (accepted : Bool) : Cut Source Evidence :=
  if expected = old.generation ∧ accepted = true then next else old
theorem rejection_preserves (old next : Cut Source Evidence) (expected : Nat) :
    publish old next expected false = old := by simp [publish]
theorem stale_preserves (old next : Cut Source Evidence) (expected : Nat)
    (stale : expected ≠ old.generation) :
    publish old next expected true = old := by simp [publish, stale]
theorem accepted_publication (old next : Cut Source Evidence) :
    publish old next old.generation true = next := by simp [publish]
/-- Rechecking under a serialized owner rejects a second request carrying the
same expected generation after the first publication increments it. -/
theorem competing_request_rejected (old next later : Cut Source Evidence)
    (advance : next.generation = old.generation + 1) :
    publish next later old.generation true = next := by
  apply stale_preserves
  rw [advance]
  exact Nat.ne_of_lt (Nat.lt_succ_self old.generation)
/-- Resource units cover edge, inspected premise and output-root visits.
This admission abstraction does not extract a native execution trace. -/
def publishBounded (old next : Cut Source Evidence) (expected edgeVisits premiseVisits rootVisits budget : Nat) : Cut Source Evidence :=
  publish old next expected (decide (edgeVisits + premiseVisits + rootVisits ≤ budget))
theorem exhausted_preserves (old next : Cut Source Evidence)
    (expected edges premises roots budget : Nat)
    (exhausted : budget < edges + premises + roots) :
    publishBounded old next expected edges premises roots budget = old := by
  simp [publishBounded, Nat.not_le.mpr exhausted, rejection_preserves]
theorem bounded_accepted (old next : Cut Source Evidence)
    (edges premises roots budget : Nat) (fit : edges + premises + roots ≤ budget) :
    publishBounded old next old.generation edges premises roots budget = next := by
  simp [publishBounded, fit, accepted_publication]
end Ascent.SourceOccurrences
