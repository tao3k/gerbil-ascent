-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure

/-! Pure semantic rebasing of completed component evaluation. Mailboxes,
credits, readiness and terminal delivery belong to Quint, not this algebra. -/
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

/-- Set admission models candidate membership, preserving existing facts and
filtering by component ownership. Temporal delivery stays outside this model. -/
def admit (owner : Fact → Component) (component : Component)
    (database : Database Fact) (batch : List Fact) : Database Fact :=
  fun fact => database fact ∨ (owner fact = component ∧ fact ∈ batch)

def publish (owner : Fact → Component) (component : Component) :
    Database Fact → List (List Fact) → Database Fact
  | database, [] => database
  | database, batch :: rest => publish owner component (admit owner component database batch) rest

theorem publish_exact (owner : Fact → Component) (component : Component)
    (database : Database Fact) (batches : List (List Fact)) (fact : Fact) :
    publish owner component database batches fact ↔
      database fact ∨ (owner fact = component ∧ fact ∈ batches.flatten) := by
  induction batches generalizing database with
  | nil => simp [publish]
  | cons batch rest ih =>
      simp only [publish, ih, admit, List.flatten_cons, List.mem_append]
      constructor
      · rintro ((old | ⟨owned, head⟩) | ⟨owned, tail⟩)
        · exact Or.inl old
        · exact Or.inr ⟨owned, Or.inl head⟩
        · exact Or.inr ⟨owned, Or.inr tail⟩
      · rintro (old | ⟨owned, head | tail⟩)
        · exact Or.inl (Or.inl old)
        · exact Or.inl (Or.inr ⟨owned, head⟩)
        · exact Or.inr ⟨owned, tail⟩

/-- Arbitrary chunk boundaries, duplicate candidates and differing list order
have no effect on admitted Set facts if delivered membership is identical. -/
theorem publish_ext (owner : Fact → Component) (component : Component)
    (database : Database Fact) (first second : List (List Fact))
    (same : ∀ fact, fact ∈ first.flatten ↔ fact ∈ second.flatten) :
    publish owner component database first = publish owner component database second := by
  funext fact
  apply propext
  rw [publish_exact, publish_exact, same]

theorem publish_sound (rules : List (Rule Fact)) (seed : Database Fact)
    (owner : Fact → Component) (component : Component) (database : Database Fact)
    (batches : List (List Fact))
    (oldSound : ∀ fact, database fact → Derivable rules seed fact)
    (candidateSound : ∀ fact, owner fact = component → fact ∈ batches.flatten → Derivable rules seed fact)
    (fact : Fact) (present : publish owner component database batches fact) :
    Derivable rules seed fact := by
  rcases (publish_exact owner component database batches fact).mp present with old | ⟨owned, candidate⟩
  · exact oldSound fact old
  · exact candidateSound fact owned candidate

/-- Candidate soundness is derived from local evaluation soundness for any
partial delivered list, rather than asserted as an independent oracle. -/
theorem published_iteration_sound (rules : List (Rule Fact)) (seed : Database Fact)
    (owner : Fact → Component) (component : Component)
    (snapshot current : Database Fact) (n : Nat) (batches : List (List Fact))
    (snapshotSound : ∀ fact, snapshot fact → Derivable rules seed fact)
    (currentSound : ∀ fact, current fact → Derivable rules seed fact)
    (produced : ∀ fact, owner fact = component → fact ∈ batches.flatten →
      iterate rules owner component snapshot n fact)
    (fact : Fact) (present : publish owner component current batches fact) :
    Derivable rules seed fact :=
  publish_sound rules seed owner component current batches currentSound
    (fun fact owned member => iterate_sound rules owner component snapshot seed n snapshotSound
      fact (produced fact owned member)) fact present

/-- The terminal delivery obligation accounts for retained snapshot facts as
well as new emitted candidates. It does not assume workers replay seed rows. -/
theorem terminal_publish_exact (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (batches : List (List Fact))
    (agree : Agrees rules owner component snapshot current)
    (delivered : ∀ fact, owner fact = component →
      (iterate rules owner component snapshot n fact ↔ snapshot fact ∨ fact ∈ batches.flatten)) :
    publish owner component current batches = iterate rules owner component current n := by
  rw [← merge_exact rules owner component snapshot current n agree]
  funext fact
  apply propext
  rw [publish_exact]
  change (current fact ∨ owner fact = component ∧ fact ∈ batches.flatten) ↔
    current fact ∨ owner fact = component ∧ iterate rules owner component snapshot n fact
  constructor
  · rintro (old | ⟨owned, candidate⟩)
    · exact Or.inl old
    · exact Or.inr ⟨owned, (delivered fact owned).mpr (Or.inr candidate)⟩
  · rintro (old | ⟨owned, complete⟩)
    · exact Or.inl old
    · rcases (delivered fact owned).mp complete with old | candidate
      · exact Or.inl ((agree fact (Or.inl owned)).mp old)
      · exact Or.inr ⟨owned, candidate⟩

theorem terminal_publish_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (batches : List (List Fact))
    (agree : Agrees rules owner component snapshot current)
    (delivered : ∀ fact, owner fact = component →
      (iterate rules owner component snapshot n fact ↔ snapshot fact ∨ fact ∈ batches.flatten))
    (stable : iterate rules owner component snapshot (n + 1) = iterate rules owner component snapshot n) :
    ClosedAt rules owner component (publish owner component current batches) := by
  rw [terminal_publish_exact rules owner component snapshot current n batches agree delivered]
  exact stable_closed rules owner component current n
    (stable_transfers rules owner component snapshot current n agree stable)

/-- External reads stay framed while owned facts may already contain credited
partial batches. This is the native owner's actual terminal state. -/
def ExternalAgrees (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) : Prop :=
  ∀ rule ∈ rules, owner rule.head = component → ∀ fact ∈ rule.body,
    owner fact ≠ component → (snapshot fact ↔ current fact)

theorem partial_merge_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (external : ExternalAgrees rules owner component snapshot current)
    (bounded : ∀ fact, owner fact = component → current fact →
      iterate rules owner component snapshot n fact)
    (stable : iterate rules owner component snapshot (n + 1) = iterate rules owner component snapshot n) :
    ClosedAt rules owner component
      (merge owner component current (iterate rules owner component snapshot n)) := by
  classical
  intro rule member owned held
  have body : Holds (iterate rules owner component snapshot n) rule.body := by
    intro fact present
    rcases held fact present with known | ⟨same, produced⟩
    · by_cases same : owner fact = component
      · exact bounded fact same known
      · exact (iterate_frame rules owner component snapshot n fact same).mpr
          ((external rule member owned fact present same).mpr known)
    · exact produced
  exact Or.inr ⟨owned, stable_closed rules owner component snapshot n stable rule member owned body⟩

/-- Complete terminal delivery extends an already published prefix. Seed facts
need not be replayed; credited own facts are allowed to exceed the old snapshot. -/
theorem partial_terminal_exact (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (tail : List (List Fact))
    (remaining : ∀ fact, owner fact = component →
      (iterate rules owner component snapshot n fact ↔ current fact ∨ fact ∈ tail.flatten)) :
    publish owner component current tail =
      merge owner component current (iterate rules owner component snapshot n) := by
  funext fact
  apply propext
  rw [publish_exact]
  constructor
  · rintro (old | ⟨owned, delivered⟩)
    · exact Or.inl old
    · exact Or.inr ⟨owned, (remaining fact owned).mpr (Or.inr delivered)⟩
  · rintro (old | ⟨owned, produced⟩)
    · exact Or.inl old
    · rcases (remaining fact owned).mp produced with old | delivered
      · exact Or.inl old
      · exact Or.inr ⟨owned, delivered⟩

theorem partial_terminal_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (tail : List (List Fact))
    (external : ExternalAgrees rules owner component snapshot current)
    (remaining : ∀ fact, owner fact = component →
      (iterate rules owner component snapshot n fact ↔ current fact ∨ fact ∈ tail.flatten))
    (stable : iterate rules owner component snapshot (n + 1) = iterate rules owner component snapshot n) :
    ClosedAt rules owner component (publish owner component current tail) := by
  rw [partial_terminal_exact rules owner component snapshot current n tail remaining]
  exact partial_merge_closed rules owner component snapshot current n external
    (fun fact owned present => (remaining fact owned).mpr (Or.inl present)) stable

theorem publish_append (owner : Fact → Component) (component : Component)
    (current : Database Fact) (creditedBatches tail : List (List Fact)) :
    publish owner component current (creditedBatches ++ tail) =
      publish owner component (publish owner component current creditedBatches) tail := by
  induction creditedBatches generalizing current with
  | nil => rfl
  | cons batch rest ih => exact ih _

/-- Credited prefix membership and complete delivery derive the remaining-tail
contract. Current owned facts are permitted to differ from the frozen snapshot. -/
theorem credited_terminal_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (snapshot current : Database Fact) (n : Nat)
    (creditedBatches tail : List (List Fact))
    (external : ExternalAgrees rules owner component snapshot current)
    (credited : ∀ fact, owner fact = component →
      (current fact ↔ snapshot fact ∨ fact ∈ creditedBatches.flatten))
    (complete : ∀ fact, owner fact = component →
      (iterate rules owner component snapshot n fact ↔ snapshot fact ∨ fact ∈ (creditedBatches ++ tail).flatten))
    (stable : iterate rules owner component snapshot (n + 1) = iterate rules owner component snapshot n) :
    ClosedAt rules owner component (publish owner component current tail) := by
  apply partial_terminal_closed rules owner component snapshot current n tail external
  · intro fact owned
    rw [complete fact owned, credited fact owned]
    simp only [List.flatten_append, List.mem_append]
    exact (or_assoc).symm
  · exact stable
end Ascent.SnapshotClosure
