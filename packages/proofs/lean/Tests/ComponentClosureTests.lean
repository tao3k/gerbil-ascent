-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure
namespace Ascent.ComponentClosureTests
open ComponentClosure
inductive Fact where
  | seed | left0 | left1 | right | out
  deriving DecidableEq
open Fact

def owner : Fact → Nat
  | seed => 0
  | left0 | left1 => 1
  | right => 2
  | out => 3

def rules : List (Rule Fact) :=
  [⟨[seed], left0⟩, ⟨[left0], left1⟩, ⟨[left1], left0⟩,
   ⟨[seed], right⟩, ⟨[left1, right], out⟩]
def initial : Database Fact := fun fact => fact = seed
def first : List (Nat × Nat) := [(1, 2), (2, 1), (3, 1)]
def second : List (Nat × Nat) := [(2, 1), (1, 2), (3, 1)]
theorem firstHeads : ∀ rule ∈ rules, owner rule.head ∈ first.map Prod.fst := by
  simp [rules, owner, first]
theorem secondHeads : ∀ rule ∈ rules, owner rule.head ∈ second.map Prod.fst := by
  simp [rules, owner, second]
theorem firstOrder : Ordered rules owner first := by
  simp [Ordered, Depends, rules, owner, first]
theorem secondOrder : Ordered rules owner second := by
  simp [Ordered, Depends, rules, owner, second]
theorem firstStable : StablePlan rules owner first initial := by
  refine ⟨?_, ?_, ?_, trivial⟩
  all_goals funext fact; cases fact <;> simp [iterate, step, Holds, rules, owner, initial]
theorem secondStable : StablePlan rules owner second initial := by
  refine ⟨?_, ?_, ?_, trivial⟩
  all_goals funext fact; cases fact <;> simp [iterate, step, Holds, rules, owner, initial]
example : solve rules owner first initial = solve rules owner second initial :=
  orders_equal rules owner first second initial firstHeads secondHeads firstOrder secondOrder
    firstStable secondStable
example (fact : Fact) : solve rules owner first initial fact ↔ Derivable rules initial fact :=
  least_closure rules owner first initial firstHeads firstOrder firstStable fact

/-- Completing the successor before its predecessors loses a derivable head. -/
def early : List (Nat × Nat) := [(3, 1), (1, 2), (2, 1)]
example : ¬ Ordered rules owner early := by
  simp [Ordered, Depends, rules, owner, early]
example : ¬ solve rules owner early initial out := by
  simp [solve, early, iterate, step, Holds, rules, owner, initial]
example : solve rules owner first initial out := by
  simp [solve, first, iterate, step, Holds, rules, owner, initial]
/-- One local round does not close the recursive left component. -/
example : ¬ (iterate rules owner 1 initial 2 = iterate rules owner 1 initial 1) := by
  intro equal
  have observed := congrFun equal left1
  simp [iterate, step, Holds, rules, owner, initial] at observed
/-- The recursive diamond has duplicate heads; no unique-head premise is needed. -/
example (database : Database Fact) : ∃ n, n ≤ 5 ∧
    iterate rules owner 1 database (n + 1) = iterate rules owner 1 database n := by
  simpa only [rules, List.length_cons, List.length_nil] using
    local_stabilizes rules owner 1 database
example (database : Database Fact) :
    iterate ([] : List (Rule Fact)) owner 1 database 1 = database := by
  funext fact
  simp [iterate, step]

theorem firstTopology : Topological rules owner [1, 2, 3] := by
  simp [Topological, Depends, rules, owner]
theorem secondTopology : Topological rules owner [2, 1, 3] := by
  simp [Topological, Depends, rules, owner]
example (fact : Fact) : solve rules owner (planned rules owner [1, 2, 3] initial) initial fact ↔
    Derivable rules initial fact :=
  topological_least rules owner [1, 2, 3] initial
    (by simpa [first] using firstHeads) firstTopology fact
example : solve rules owner (planned rules owner [1, 2, 3] initial) initial =
    solve rules owner (planned rules owner [2, 1, 3] initial) initial := by
  funext fact
  apply propext
  exact (topological_least rules owner _ initial (by simpa [first] using firstHeads)
    firstTopology fact).trans
    (topological_least rules owner _ initial (by simpa [second] using secondHeads)
      secondTopology fact).symm
#print axioms Ascent.ComponentClosure.local_stabilizes
#print axioms Ascent.ComponentClosure.planned_stable
#print axioms Ascent.ComponentClosure.topological_least
#print axioms Ascent.ComponentClosure.iterate_frame
#print axioms Ascent.ComponentClosure.solve_closed
#print axioms Ascent.ComponentClosure.least_closure
#print axioms Ascent.ComponentClosure.least_model
#print axioms Ascent.ComponentClosure.orders_equal
end Ascent.ComponentClosureTests
