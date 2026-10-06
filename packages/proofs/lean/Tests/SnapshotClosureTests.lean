-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import SnapshotClosure
import Tests.ComponentClosureTests
namespace Ascent.SnapshotClosureTests
open ComponentClosure ComponentClosureTests SnapshotClosure
open ComponentClosureTests.Fact

def current : Database ComponentClosureTests.Fact := iterate rules owner 2 initial 1

theorem agreement : Agrees rules owner 1 initial current :=
  unrelated_iteration_agrees rules owner 1 2 initial 1 (by decide)
    (by simp [Depends, rules, owner])

theorem snapshotStable : iterate rules owner 1 initial 3 = iterate rules owner 1 initial 2 := by
  funext fact
  cases fact <;> simp [iterate, step, Holds, rules, owner, initial]

example : merge owner 1 current (iterate rules owner 1 initial 2) =
    iterate rules owner 1 current 2 := merge_exact rules owner 1 initial current 2 agreement
example : ClosedAt rules owner 1 (merge owner 1 current (iterate rules owner 1 initial 2)) :=
  completed_closed rules owner 1 initial current 2 agreement snapshotStable
example : merge owner 1 current (iterate rules owner 1 initial 2) right := by
  exact Or.inl (by simp [current, iterate, step, Holds, rules, owner, initial])

/-- A changed predecessor read invalidates the frame, even though the old empty
snapshot was stable. A completion flag alone cannot supply this obligation. -/
example : ¬ Agrees rules owner 1 (fun _ => False) initial := by
  intro agree
  have observed := agree seed (Or.inr ⟨⟨[seed], left0⟩, by simp [rules], rfl, by simp⟩)
  simp [initial] at observed
example : iterate rules owner 1 (fun _ => False) 1 = iterate rules owner 1 (fun _ => False) 0 := by
  funext fact
  cases fact <;> simp [iterate, step, Holds, rules, owner]
example : ¬ (iterate rules owner 1 initial 1 = iterate rules owner 1 initial 0) := by
  intro equal
  have observed := congrFun equal left0
  simp [iterate, step, Holds, rules, owner, initial] at observed
#print axioms Ascent.SnapshotClosure.iterate_agrees
#print axioms Ascent.SnapshotClosure.merge_exact
#print axioms Ascent.SnapshotClosure.stable_transfers
#print axioms Ascent.SnapshotClosure.completed_closed
#print axioms Ascent.SnapshotClosure.unrelated_iteration_agrees
end Ascent.SnapshotClosureTests
