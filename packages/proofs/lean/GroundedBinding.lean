-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure
import IndexedIteration
import SnapshotClosure

/-! Construct finite ground rules from actual successful ordinary binder paths.
The admitted row universe is frozen independently of database membership.
Native scalar/plan decoding and SCC ownership remain separate obligations. -/
namespace Ascent.GroundedBinding
open AtomicBinding ComponentClosure
variable {Key Value : Type} [DecidableEq Value]
abbrev Fact (Key Value : Type) := Key × List Value

/-- Canonical finite Set concretization, constructed from the frozen admitted
row universe. No provider-faithfulness premise is supplied by the caller. -/
noncomputable def snapshotRows (domainRows : Key → List (List Value)) :
    IndexedIteration.Rows Key Value (Fact Key Value) := by
  classical
  exact fun database key => (domainRows key).filter (fun row => decide (database (key, row)))

omit [DecidableEq Value] in
theorem snapshot_rows_faithful (domainRows : Key → List (List Value))
    (database : Database (Fact Key Value)) (key : Key) (row : List Value) :
    row ∈ snapshotRows domainRows database key ↔ row ∈ domainRows key ∧ database (key, row) := by
  classical
  simp [snapshotRows]

omit [DecidableEq Value] in
theorem snapshot_rows_admitted (domainRows : Key → List (List Value)) :
    IndexedIteration.RowsAdmitted (fun key row => row ∈ domainRows key) (snapshotRows domainRows) := by
  intro database key row present
  exact ((snapshot_rows_faithful domainRows database key row).mp present).1

omit [DecidableEq Value] in
theorem snapshot_rows_monotone (domainRows : Key → List (List Value)) :
    IndexedIteration.RowsMonotone (snapshotRows domainRows) := by
  intro before after grows key row present
  obtain ⟨admitted, known⟩ := (snapshot_rows_faithful domainRows before key row).mp present
  exact (snapshot_rows_faithful domainRows after key row).mpr ⟨admitted, grows _ known⟩

/-- Exact row differences and canonical snapshots construct the indexed pivot
frontier contract for every finite body and growing database pair. -/
theorem snapshot_delta_exact (domainRows : Key → List (List Value))
    (specs : List (IndexedIteration.Spec Key Value))
    (before after : Database (Fact Key Value)) (grows : ∀ fact, before fact → after fact) :
    IndexedPositiveTraversal.DeltaExact
      (IndexedIteration.instantiate specs (snapshotRows domainRows before) (snapshotRows domainRows after)) :=
  IndexedIteration.instantiated_delta specs _ _
    (snapshot_rows_monotone domainRows before after grows)

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

/-- Integrated admission law: completed credit/tail delivery under the native
read frame makes every admitted compiled rule closed in the final database.
Grounding, indexed binding and partial snapshot rebasing are composed here. -/
theorem credited_compiled_closed {Component : Type}
    (domainRows : Key → List (List Value))
    (rows : IndexedIteration.Rows Key Value (Fact Key Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (valid : ∀ rule ∈ rules, IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (owner : Key → Component) (component : Component)
    (snapshot current : Database (Fact Key Value)) (n : Nat)
    (creditedBatches tail : List (List (Fact Key Value)))
    (external : SnapshotClosure.ExternalAgrees (programGround domainRows rules)
      (fun fact => owner fact.1) component snapshot current)
    (credited : ∀ fact, owner fact.1 = component →
      (current fact ↔ snapshot fact ∨ fact ∈ creditedBatches.flatten))
    (complete : ∀ fact, owner fact.1 = component →
      (iterate (programGround domainRows rules) (fun fact => owner fact.1) component snapshot n fact ↔
        snapshot fact ∨ fact ∈ (creditedBatches ++ tail).flatten))
    (stable : iterate (programGround domainRows rules) (fun fact => owner fact.1) component snapshot (n + 1) =
      iterate (programGround domainRows rules) (fun fact => owner fact.1) component snapshot n)
    (rule : IndexedIteration.Rule Key Value (Fact Key Value)) (member : rule ∈ rules)
    (item : Fact Key Value) (owned : owner item.1 = component)
    (produced : item ∈ IndexedIteration.fullRun rule rows
      (SnapshotClosure.publish (fun fact => owner fact.1) component current tail)) :
    SnapshotClosure.publish (fun fact => owner fact.1) component current tail item := by
  have closed := SnapshotClosure.credited_terminal_closed (programGround domainRows rules)
    (fun fact => owner fact.1) component snapshot current n creditedBatches tail external credited complete stable
  have consequence := (IndexedIteration.full_run_exact rule rows _ (valid rule member)
    (fun database key row present => ((faithful database key row).mp present).1) _ item).mp produced
  obtain ⟨clause, clauseMember, body, head⟩ :=
    (program_exact domainRows rows faithful rules _ item).mp ⟨rule, member, consequence⟩
  have headOwned : owner clause.head.1 = component := by simpa only [head] using owned
  have present := closed clause clauseMember headOwned body
  exact head ▸ present

/-- Whole-result admission: compiled closure plus sound publication and seed
coverage characterize the least model, rather than only one component's result. -/
theorem completed_compiled_least
    (domainRows : Key → List (List Value))
    (rows : IndexedIteration.Rows Key Value (Fact Key Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      row ∈ domainRows key ∧ database (key, row))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (valid : ∀ rule ∈ rules, IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (seed result : Database (Fact Key Value))
    (covers : ∀ fact, seed fact → result fact)
    (sound : ∀ fact, result fact → Derivable (programGround domainRows rules) seed fact)
    (closed : ∀ rule ∈ rules, ∀ item, item ∈ IndexedIteration.fullRun rule rows result → result item)
    (fact : Fact Key Value) : result fact ↔ Derivable (programGround domainRows rules) seed fact := by
  have binderClosed : ∀ rule ∈ rules, ∀ item,
      IndexedIteration.consequence rule rows result item → result item := by
    intro rule member item consequence
    exact closed rule member item
      ((IndexedIteration.full_run_exact rule rows _ (valid rule member)
        (fun database key row present => ((faithful database key row).mp present).1) result item).mpr consequence)
  have groundClosed := (closed_exact domainRows rows faithful rules result).mp binderClosed
  constructor
  · exact sound fact
  · intro derived
    induction derived with
    | seed present => exact covers _ present
    | fire rule member body ih => exact groundClosed rule member (fun f h => ih f h)
/-- The canonical Set instance now connects actual compiled binding to the
constructed ground rules without a caller-supplied enumeration axiom. -/
theorem snapshot_compiled_ground_exact (domainRows : Key → List (List Value))
    (rule : IndexedIteration.Rule Key Value (Fact Key Value))
    (valid : IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (database : Database (Fact Key Value)) (item : Fact Key Value) :
    item ∈ IndexedIteration.fullRun rule (snapshotRows domainRows) database ↔
      ∃ clause ∈ ruleGround domainRows rule, Holds database clause.body ∧ clause.head = item :=
  compiled_ground_exact domainRows (snapshotRows domainRows)
    (snapshot_rows_faithful domainRows) rule valid database item

/-- The constructed canonical enumerator supplies both admission and monotonic
concretization to every natural-number indexed history. -/
theorem snapshot_indexed_history (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (valid : ∀ rule ∈ rules, IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (initial : Database (Fact Key Value)) (n : Nat) :
    IndexedIteration.indexed rules (snapshotRows domainRows) initial n =
      (IndexedIteration.naive rules (snapshotRows domainRows) initial n,
       IndexedIteration.naive rules (snapshotRows domainRows) initial (n + 1)) :=
  IndexedIteration.indexed_iterations_equal rules _ _ valid
    (snapshot_rows_admitted domainRows) (snapshot_rows_monotone domainRows) initial n

/-- The constructed finite component solver is the least model of ordinary
binder consequences for the canonical Set instance. Stability is constructed
by the existing ground planner, not assumed of an arbitrary completed result. -/
theorem snapshot_component_least {Component : Type}
    (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (owner : Fact Key Value → Component) (order : List Component)
    (seed : Database (Fact Key Value))
    (heads : ∀ clause ∈ programGround domainRows rules, owner clause.head ∈ order)
    (topology : Topological (programGround domainRows rules) owner order)
    (fact : Fact Key Value) :
    solve (programGround domainRows rules) owner
      (planned (programGround domainRows rules) owner order seed) seed fact ↔
    ∀ model : Database (Fact Key Value),
      (∀ item, seed item → model item) →
      (∀ rule ∈ rules, ∀ item,
        IndexedIteration.consequence rule (snapshotRows domainRows) model item → model item) → model fact := by
  constructor
  · intro produced model covers closed
    exact binder_least_model domainRows _ (snapshot_rows_faithful domainRows)
      rules owner order seed model heads topology covers closed fact produced
  · intro least
    apply (topological_least (programGround domainRows rules) owner order seed heads topology fact).mpr
    apply least (Derivable (programGround domainRows rules) seed)
    · intro item present
      exact Derivable.seed present
    · intro rule member item consequence
      obtain ⟨clause, present, held, equal⟩ :=
        (program_exact domainRows _ (snapshot_rows_faithful domainRows) rules _ item).mp
          ⟨rule, member, consequence⟩
      exact equal ▸ Derivable.fire clause present held

/-- Canonical ordinary consequence and the constructed ground operator are
the same function, not merely equivalent final expected answers. -/
theorem snapshot_step_ground (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (database : Database (Fact Key Value)) :
    IndexedIteration.fullStep rules (snapshotRows domainRows) database =
      step (programGround domainRows rules) (fun _ => ()) () database := by
  funext fact
  apply propext
  simp only [IndexedIteration.fullStep, step, true_and]
  exact or_congr_right (program_exact domainRows _ (snapshot_rows_faithful domainRows) rules database fact)

theorem snapshot_naive_ground (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (initial : Database (Fact Key Value)) (n : Nat) :
    IndexedIteration.naive rules (snapshotRows domainRows) initial n =
      iterate (programGround domainRows rules) (fun _ => ()) () initial n := by
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [IndexedIteration.naive, iterate, ih, snapshot_step_ground]

/-- Select the existing proved finite-head stabilization witness. This is a
semantic construction, not a fixed native timeout or runtime iteration cap. -/
noncomputable def snapshotRounds (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (initial : Database (Fact Key Value)) : Nat :=
  rounds (programGround domainRows rules) (fun _ => ()) () initial

theorem snapshot_rounds_spec (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (initial : Database (Fact Key Value)) :
    snapshotRounds domainRows rules initial ≤ (programGround domainRows rules).length ∧
    IndexedIteration.naive rules (snapshotRows domainRows) initial
      (snapshotRounds domainRows rules initial + 1) =
    IndexedIteration.naive rules (snapshotRows domainRows) initial (snapshotRounds domainRows rules initial) := by
  simpa only [snapshotRounds, snapshot_naive_ground] using
    rounds_spec (programGround domainRows rules) (fun _ => ()) () initial

/-- The compiled indexed result reaches the least model using a constructed
finite stabilization witness; no result soundness, closure or stability is
supplied as a premise. Native iteration/publication extraction stays separate. -/
theorem snapshot_indexed_least (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (valid : ∀ rule ∈ rules, IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (initial : Database (Fact Key Value)) (fact : Fact Key Value) :
    (IndexedIteration.indexed rules (snapshotRows domainRows) initial
      (snapshotRounds domainRows rules initial)).2 fact ↔
      Derivable (programGround domainRows rules) initial fact := by
  rw [snapshot_indexed_history domainRows rules valid initial,
    (snapshot_rounds_spec domainRows rules initial).2, snapshot_naive_ground]
  simpa only [planned, solve, snapshotRounds] using
    topological_least (programGround domainRows rules) (fun _ => ()) [()] initial
      (by simp) (by simp [Topological]) fact

/-- Every later indexed snapshot remains the same least model; no generation
bound or runtime cutoff is introduced by the finite witness. -/
theorem snapshot_indexed_stays_least (domainRows : Key → List (List Value))
    (rules : List (IndexedIteration.Rule Key Value (Fact Key Value)))
    (valid : ∀ rule ∈ rules, IndexedIteration.Valid (fun key row => row ∈ domainRows key) rule)
    (initial : Database (Fact Key Value)) (extra : Nat) (fact : Fact Key Value) :
    (IndexedIteration.indexed rules (snapshotRows domainRows) initial
      (snapshotRounds domainRows rules initial + extra)).2 fact ↔
      Derivable (programGround domainRows rules) initial fact := by
  rw [IndexedIteration.stable_indexed rules _ _ valid
    (snapshot_rows_admitted domainRows) (snapshot_rows_monotone domainRows)
    initial _ (snapshot_rounds_spec domainRows rules initial).2 extra,
    snapshot_naive_ground]
  simpa only [planned, solve, snapshotRounds] using
    topological_least (programGround domainRows rules) (fun _ => ()) [()] initial
      (by simp) (by simp [Topological]) fact

end Ascent.GroundedBinding
