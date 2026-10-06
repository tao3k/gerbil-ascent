-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure

/-! Pure semantic rebasing of completed component evaluation. Mailboxes,
credits, readiness and terminal delivery belong to TLA+, not this algebra. -/
namespace Ascent.SnapshotClosure
open ComponentClosure
variable {Fact Component : Type}

def Relevant (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (fact : Fact) : Prop :=
  owner fact = component ∨ ∃ rule ∈ rules, owner rule.head = component ∧ fact ∈ rule.body

def Agrees (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (first second : Database Fact) : Prop :=
  ∀ fact, Relevant rules owner component fact → (first fact ↔ second fact)

theorem step_agrees (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (first second : Database Fact)
    (agree : Agrees rules owner component first second) :
    Agrees rules owner component (step rules owner component first) (step rules owner component second) := by
  intro fact relevant
  constructor
  · rintro (old | ⟨rule, member, owned, body, head⟩)
    · exact Or.inl ((agree fact relevant).mp old)
    · exact Or.inr ⟨rule, member, owned,
        fun read present => (agree read (Or.inr ⟨rule, member, owned, present⟩)).mp (body read present), head⟩
  · rintro (old | ⟨rule, member, owned, body, head⟩)
    · exact Or.inl ((agree fact relevant).mpr old)
    · exact Or.inr ⟨rule, member, owned,
        fun read present => (agree read (Or.inr ⟨rule, member, owned, present⟩)).mpr (body read present), head⟩

theorem iterate_agrees (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (first second : Database Fact) (n : Nat)
    (agree : Agrees rules owner component first second) :
    Agrees rules owner component (iterate rules owner component first n)
      (iterate rules owner component second n) := by
  induction n with
  | zero => exact agree
  | succ n ih => exact step_agrees rules owner component _ _ ih

/-- Admit only the completed worker's owned facts into the current database. -/
def merge (owner : Fact → Component) (component : Component)
    (current completed : Database Fact) : Database Fact :=
  fun fact => current fact ∨ (owner fact = component ∧ completed fact)

theorem merge_exact (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (agree : Agrees rules owner component snapshot current) :
    merge owner component current (iterate rules owner component snapshot n) =
      iterate rules owner component current n := by
  classical
  funext fact
  apply propext
  by_cases owned : owner fact = component
  · have equal := iterate_agrees rules owner component snapshot current n agree fact (Or.inl owned)
    constructor
    · rintro (old | ⟨_, completed⟩)
      · exact iterate_grows rules owner component current n fact old
      · exact equal.mp completed
    · intro present
      exact Or.inr ⟨owned, equal.mpr present⟩
  · simp only [merge, owned, false_and, or_false]
    exact (iterate_frame rules owner component current n fact owned).symm

theorem stable_transfers (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (agree : Agrees rules owner component snapshot current)
    (stable : iterate rules owner component snapshot (n + 1) = iterate rules owner component snapshot n) :
    iterate rules owner component current (n + 1) = iterate rules owner component current n := by
  rw [← merge_exact rules owner component snapshot current (n + 1) agree,
      ← merge_exact rules owner component snapshot current n agree, stable]

/-- A completed stable snapshot remains closed after unrelated concurrent
writes; the read/ownership agreement is the precise semantic obligation. -/
theorem completed_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (agree : Agrees rules owner component snapshot current)
    (stable : iterate rules owner component snapshot (n + 1) = iterate rules owner component snapshot n) :
    ClosedAt rules owner component
      (merge owner component current (iterate rules owner component snapshot n)) := by
  rw [merge_exact rules owner component snapshot current n agree]
  exact stable_closed rules owner component current n
    (stable_transfers rules owner component snapshot current n agree stable)

/-- The no-dependency graph condition derives the agreement frame for writes
owned by another component; no scheduling state is modeled here. -/
theorem unrelated_iteration_agrees (rules : List (Rule Fact)) (owner : Fact → Component)
    (component other : Component) (database : Database Fact) (n : Nat)
    (different : other ≠ component) (independent : ¬ Depends rules owner other component) :
    Agrees rules owner component database (iterate rules owner other database n) := by
  intro fact relevant
  have foreign : owner fact ≠ other := by
    intro equal
    rcases relevant with owned | ⟨rule, member, owned, read⟩
    · exact different (equal.symm.trans owned)
    · exact independent ⟨rule, member, owned, fact, read, equal⟩
  exact (iterate_frame rules owner other database n fact foreign).symm
end Ascent.SnapshotClosure
