-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure
import IndexedIteration

/-! Construct finite ground rules from actual successful ordinary binder paths.
The admitted row universe is frozen independently of database membership.
Native scalar/plan decoding and SCC ownership remain separate obligations. -/
namespace Ascent.GroundedBinding
open AtomicBinding ComponentClosure
variable {Key Value : Type} [DecidableEq Value]
abbrev Fact (Key Value : Type) := Key × List Value

/-- Failed bindings produce no rule; successful paths retain every read fact.
Empty bodies and repeated/multiple emitted heads retain their list semantics. -/
def ground (domainRows : Key → List (List Value))
    (emit : Env Value → List (Fact Key Value)) :
    List (PositiveConsequence.Atom Key Value) → Env Value → List (ComponentClosure.Rule (Fact Key Value))
  | [], input => (emit input).map fun head => ⟨[], head⟩
  | atom :: rest, input => (domainRows atom.source).flatMap fun row =>
      match bind atom.terms row input with
      | none => []
      | some middle => (ground domainRows emit rest middle).map fun rule =>
          ⟨(atom.source, row) :: rule.body, rule.head⟩

theorem ground_exact (domainRows : Key → List (List Value))
    (rows : Database (Fact Key Value) → Key → List (List Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (emit : Env Value → List (Fact Key Value))
    (atoms : List (PositiveConsequence.Atom Key Value))
    (input : Env Value) (database : Database (Fact Key Value)) (item : Fact Key Value) :
    (∃ rule ∈ ground domainRows emit atoms input, Holds database rule.body ∧ rule.head = item) ↔
    ∃ output, ProviderFrontier.body (PositiveConsequence.transition (rows database))
      atoms input output ∧ item ∈ emit output := by
  induction atoms generalizing input with
  | nil =>
      constructor
      · rintro ⟨rule, member, _, head⟩
        obtain ⟨emitted, emittedMember, equal⟩ := List.mem_map.mp member
        subst rule
        exact ⟨input, rfl, head ▸ emittedMember⟩
      · rintro ⟨output, equal, emitted⟩
        subst output
        exact ⟨⟨[], item⟩, List.mem_map.mpr ⟨item, emitted, rfl⟩,
          (by simp [Holds]), rfl⟩
  | cons atom rest ih =>
      constructor
      · rintro ⟨rule, member, held, head⟩
        obtain ⟨row, admitted, member⟩ := List.mem_flatMap.mp member
        cases found : bind atom.terms row input with
        | none => simp [found] at member
        | some middle =>
            obtain ⟨tail, tailMember, equal⟩ := List.mem_map.mp (by simpa only [found] using member)
            subst rule
            have present : database (atom.source, row) := held _ (by simp)
            have tailHeld : Holds database tail.body := fun fact member => held fact (by simp [member])
            obtain ⟨output, body, emitted⟩ := (ih middle).mp ⟨tail, tailMember, tailHeld, head⟩
            exact ⟨output, ⟨middle, ⟨row, (faithful _ _ _).mpr ⟨admitted, present⟩, found⟩, body⟩, emitted⟩
      · rintro ⟨output, ⟨middle, ⟨row, present, found⟩, body⟩, emitted⟩
        obtain ⟨admitted, known⟩ := (faithful _ _ _).mp present
        obtain ⟨tail, member, held, head⟩ := (ih middle).mpr ⟨output, body, emitted⟩
        refine ⟨⟨(atom.source, row) :: tail.body, tail.head⟩, ?_, ?_, head⟩
        · apply List.mem_flatMap.mpr
          refine ⟨row, admitted, ?_⟩
          simp only [found]
          exact List.mem_map.mpr ⟨tail, member, rfl⟩
        · intro fact member
          rcases List.mem_cons.mp member with equal | member
          · simpa only [equal] using known
          · exact held fact member

def ruleGround (domainRows : Key → List (List Value))
    (rule : IndexedIteration.Rule Key Value (Fact Key Value)) :=
  ground domainRows rule.emit (rule.atoms.map Prod.fst) rule.seed

theorem compiled_ground_exact (domainRows : Key → List (List Value))
    (rows : IndexedIteration.Rows Key Value (Fact Key Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (rule : IndexedIteration.Rule Key Value (Fact Key Value))
    (valid : IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (database : Database (Fact Key Value)) (item : Fact Key Value) :
    item ∈ IndexedIteration.fullRun rule rows database ↔
      ∃ clause ∈ ruleGround domainRows rule, Holds database clause.body ∧ clause.head = item := by
  rw [IndexedIteration.full_run_exact rule rows _ valid
    (fun database key row member => ((faithful database key row).mp member).1)]
  exact (ground_exact domainRows rows faithful rule.emit _ rule.seed database item).symm

def programGround (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value))) :=
  rules.flatMap (ruleGround domainRows)

theorem program_exact (domainRows : Key → List (List Value))
    (rows : IndexedIteration.Rows Key Value (Fact Key Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (database : Database (Fact Key Value)) (item : Fact Key Value) :
    (∃ rule ∈ rules, IndexedIteration.consequence rule rows database item) ↔
      ∃ clause ∈ programGround domainRows rules, Holds database clause.body ∧ clause.head = item := by
  constructor
  · rintro ⟨rule, member, consequence⟩
    obtain ⟨clause, groundMember, held, head⟩ :=
      (ground_exact domainRows rows faithful rule.emit _ rule.seed database item).mpr consequence
    exact ⟨clause, List.mem_flatMap.mpr ⟨rule, member, groundMember⟩, held, head⟩
  · rintro ⟨clause, member, held, head⟩
    obtain ⟨rule, member, groundMember⟩ := List.mem_flatMap.mp member
    exact ⟨rule, member,
      (ground_exact domainRows rows faithful rule.emit _ rule.seed database item).mp
        ⟨clause, groundMember, held, head⟩⟩

/-- Ground closure and binder closure coincide for every database, independently
of a solver order or a preselected expected answer. -/
theorem closed_exact (domainRows : Key → List (List Value))
    (rows : IndexedIteration.Rows Key Value (Fact Key Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (database : Database (Fact Key Value)) :
    (∀ rule ∈ rules, ∀ item, IndexedIteration.consequence rule rows database item → database item) ↔
    (∀ clause ∈ programGround domainRows rules, Holds database clause.body → database clause.head) := by
  constructor
  · intro closed clause member held
    obtain ⟨rule, member, consequence⟩ :=
      (program_exact domainRows rows faithful rules database clause.head).mpr ⟨clause, member, held, rfl⟩
    exact closed rule member _ consequence
  · intro closed rule member item consequence
    obtain ⟨clause, member, held, head⟩ :=
      (program_exact domainRows rows faithful rules database item).mp ⟨rule, member, consequence⟩
    exact head ▸ closed clause member held

/-- Finite constructed grounding transports the component least-model theorem
back to ordinary binder semantics, without supplying local stabilization. -/
theorem binder_least_model {Component : Type}
    (domainRows : Key → List (List Value))
    (rows : IndexedIteration.Rows Key Value (Fact Key Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (owner : Fact Key Value → Component) (order : List Component)
    (seed model : Database (Fact Key Value))
    (heads : ∀ clause ∈ programGround domainRows rules, owner clause.head ∈ order)
    (topology : Topological (programGround domainRows rules) owner order)
    (covers : ∀ fact, seed fact → model fact)
    (closed : ∀ rule ∈ rules, ∀ item, IndexedIteration.consequence rule rows model item → model item)
    (fact : Fact Key Value)
    (produced : solve (programGround domainRows rules) owner
      (planned (programGround domainRows rules) owner order seed) seed fact) : model fact := by
  have derived := (topological_least (programGround domainRows rules) owner order seed
    heads topology fact).mp produced
  have groundClosed := (closed_exact domainRows rows faithful rules model).mp closed
  clear produced
  induction derived with
  | seed present => exact covers _ present
  | fire rule member body ih => exact groundClosed rule member (fun f h => ih f h)
end Ascent.GroundedBinding
