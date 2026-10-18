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

def batches : List (List ComponentClosureTests.Fact) := [[left0, left0], [], [left1, right]]
def regrouped : List (List ComponentClosureTests.Fact) := [[right, left1, left0]]
example : publish owner 1 current batches = publish owner 1 current regrouped := by
  apply publish_ext
  intro fact
  simp [batches, regrouped, or_comm, or_left_comm, or_assoc]

theorem delivered : ∀ fact, owner fact = 1 →
    (iterate rules owner 1 initial 2 fact ↔ initial fact ∨ fact ∈ batches.flatten) := by
  intro fact owned
  cases fact <;> simp [owner] at owned <;>
    simp [iterate, step, Holds, rules, owner, initial, batches]
example : publish owner 1 current batches = iterate rules owner 1 current 2 :=
  terminal_publish_exact rules owner 1 initial current 2 batches agreement delivered
example : ClosedAt rules owner 1 (publish owner 1 current batches) :=
  terminal_publish_closed rules owner 1 initial current 2 batches agreement delivered snapshotStable
/-- Losing the final candidate violates the terminal completeness contract. -/
example : ¬ (∀ fact, owner fact = 1 →
    (iterate rules owner 1 initial 2 fact ↔ initial fact ∨ fact ∈ ([[left0]] : List (List ComponentClosureTests.Fact)).flatten)) := by
  intro complete
  have missing := complete left1 rfl
  simp [iterate, step, Holds, rules, owner, initial] at missing
#print axioms Ascent.SnapshotClosure.publish_exact
#print axioms Ascent.SnapshotClosure.publish_ext
#print axioms Ascent.SnapshotClosure.publish_sound
#print axioms Ascent.SnapshotClosure.published_iteration_sound
#print axioms Ascent.SnapshotClosure.terminal_publish_exact
#print axioms Ascent.SnapshotClosure.terminal_publish_closed

def credited : Database ComponentClosureTests.Fact := publish owner 1 current [[left0]]
example : ¬ Agrees rules owner 1 initial credited := by
  intro agree
  have difference := agree left0 (Or.inl rfl)
  simp [credited, publish, admit, current, iterate, step, Holds, rules, owner, initial] at difference
example : ClosedAt rules owner 1 (publish owner 1 credited [[left1]]) := by
  apply credited_terminal_closed rules owner 1 initial credited 2 [[left0]] [[left1]]
  · intro rule member owned fact present foreign
    simp [rules] at member
    rcases member with equal | equal | equal | equal | equal
    all_goals subst rule; simp [owner] at owned
    all_goals simp at present; subst fact
    all_goals simp [owner] at foreign
    all_goals simp [credited, publish, admit, current, iterate, step, Holds, rules, owner, initial]
  · intro fact owned
    cases fact <;> simp [owner] at owned <;>
      simp [credited, publish, admit, current, iterate, step, Holds, rules, owner, initial]
  · intro fact owned
    cases fact <;> simp [owner] at owned <;>
      simp [iterate, step, Holds, rules, owner, initial]
  · exact snapshotStable
#print axioms Ascent.SnapshotClosure.partial_merge_closed
#print axioms Ascent.SnapshotClosure.credited_terminal_closed
end Ascent.SnapshotClosureTests
