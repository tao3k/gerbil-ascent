-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import GroundedBinding
namespace Ascent.GroundedBindingTests
open GroundedBinding AtomicBinding ComponentClosure

def domainRows : Nat → List (List Nat)
  | 0 => [[0, 0, 0], [1, 1, 1], [1, 2, 1]]
  | 1 => [[1, 7], [2, 8]]
  | _ => []
def atoms : List (PositiveConsequence.Atom Nat Nat) :=
  [⟨0, [.variable 0, .variable 0, .literal 1]⟩,
   ⟨1, [.variable 0, .variable 1]⟩]
def emit (env : Env Nat) : List (Fact Nat Nat) :=
  [(2, [(lookup 0 env).getD 99, (lookup 1 env).getD 99]),
   (2, [(lookup 0 env).getD 99, (lookup 1 env).getD 99]), (3, [])]
def reads : List (Fact Nat Nat) := [(0, [1, 1, 1]), (1, [1, 7])]

/-- Failed repeated-variable, constant and shared-key candidates disappear;
all read witnesses and duplicate/multiple heads survive grounding. -/
example : ground domainRows emit atoms [] =
    [⟨reads, (2, [1, 7])⟩, ⟨reads, (2, [1, 7])⟩, ⟨reads, (3, [])⟩] := rfl
example : ground domainRows (fun _ => [(3, [])]) [] [] = [⟨[], (3, [])⟩] := rfl
example : ground domainRows emit [⟨9, [.wildcard]⟩] [] = [] := rfl

noncomputable def rows := snapshotRows domainRows
theorem faithful : ∀ database key row, row ∈ rows database key ↔
    row ∈ domainRows key ∧ database (key, row) := by
  exact snapshot_rows_faithful domainRows
example (database : Database (Fact Nat Nat)) (item : Fact Nat Nat) :
    (∃ rule ∈ ground domainRows emit atoms [], Holds database rule.body ∧ rule.head = item) ↔
    ∃ output, ProviderFrontier.body (PositiveConsequence.transition (rows database))
      atoms [] output ∧ item ∈ emit output :=
  ground_exact domainRows rows faithful emit atoms [] database item
#print axioms Ascent.GroundedBinding.ground_exact
#print axioms Ascent.GroundedBinding.compiled_ground_exact
#print axioms Ascent.GroundedBinding.program_exact
#print axioms Ascent.GroundedBinding.closed_exact
#print axioms Ascent.GroundedBinding.binder_least_model
#print axioms Ascent.GroundedBinding.credited_compiled_closed
#print axioms Ascent.GroundedBinding.completed_compiled_least
#print axioms Ascent.GroundedBinding.snapshot_rows_faithful
#print axioms Ascent.GroundedBinding.snapshot_rows_admitted
#print axioms Ascent.GroundedBinding.snapshot_rows_monotone
#print axioms Ascent.GroundedBinding.snapshot_delta_exact
#print axioms Ascent.GroundedBinding.snapshot_compiled_ground_exact
#print axioms Ascent.GroundedBinding.snapshot_indexed_history
#print axioms Ascent.GroundedBinding.snapshot_component_least
#print axioms Ascent.ProviderFrontier.SetBatch.admitted_exact
#print axioms Ascent.ProviderFrontier.SetBatch.admitted_unique
#print axioms Ascent.ProviderFrontier.SetBatch.published_exact
#print axioms Ascent.ProviderFrontier.SetBatch.published_unique
#print axioms Ascent.ProviderFrontier.SetBatch.frontier_exact
#print axioms Ascent.ProviderFrontier.SetBatch.repeated_batch_empty
#print axioms Ascent.ProviderFrontier.SetBatch.source_admitted_exact
#print axioms Ascent.ProviderFrontier.SetBatch.admit_disjoint
#print axioms Ascent.ProviderFrontier.SetBatch.unique_whole_log

example : ProviderFrontier.SetBatch.admit [false, true, false] [true] = [false] := by decide
example : ProviderFrontier.SetBatch.admit [false, true, false] ([] : List Bool) = [true, false] := by decide
example : ProviderFrontier.SetBatch.publish [false, false] [true] = [false, true] := by decide
example : ProviderFrontier.SetBatch.sourceAdmit [false, true, false] 0 [] = [] := by decide
example : ProviderFrontier.SetBatch.sourceAdmit [false, true, false] 1 [] = [false] := by decide
example : ProviderFrontier.SetBatch.sourceAdmit [false, true, false] 2 [] = [false, true] := by decide
example : ProviderFrontier.SetBatch.sourceAdmit [false, true, false] 3 [] = [true, false] := by decide
example : ProviderFrontier.SetBatch.admit [false, true, false]
    (ProviderFrontier.SetBatch.publish [false, true, false] []) = [] := by decide
/-- Empty/missing delta cannot satisfy the frontier of a genuinely new row. -/
example : ProviderFrontier.delta (fun r : Bool => r ∈ [false])
    (fun r => r ∈ ProviderFrontier.SetBatch.publish [true] [false]) true ∧
    true ∉ ([] : List Bool) := by unfold ProviderFrontier.delta; decide
example : snapshotRows domainRows (fun fact => fact ∈ reads) 0 = [[1, 1, 1]] := by
  classical
  simp [snapshotRows, domainRows, reads]
example : snapshotRows domainRows (fun fact => fact ∈ reads) 9 = [] := by
  classical
  simp [snapshotRows, domainRows]

example (before after : Database (Fact Nat Nat)) (grows : ∀ fact, before fact → after fact) :
    IndexedPositiveTraversal.DeltaCovers
      (IndexedIteration.instantiate [(⟨0, [.wildcard, .wildcard, .wildcard]⟩, [])]
        (snapshotRows domainRows before) (snapshotRows domainRows after)) :=
  IndexedPositiveTraversal.exact_covers _ (snapshot_delta_exact domainRows _ before after grows)
def boolDomain : Nat → List (List Bool)
  | 0 => [[false]]
  | 1 => [[true]]
  | _ => []
def seedRule : IndexedIteration.Rule Nat Bool (Fact Nat Bool) :=
  ⟨[], [], [], (fun _ => false), (fun _ => [(0, [false]), (0, [false])]),
    (fun _ _ => [(0, [false]), (0, [false])])⟩
def stepRule : IndexedIteration.Rule Nat Bool (Fact Nat Bool) :=
  ⟨[(⟨0, [.literal false]⟩, [0])], [], [], (fun _ => true),
    (fun _ => [(1, [true]), (1, [true])]), (fun _ _ => [(1, [true]), (1, [true])])⟩
def boolRules := [seedRule, stepRule]
example : programGround boolDomain boolRules =
    [⟨[], (0, [false])⟩, ⟨[], (0, [false])⟩,
     ⟨[(0, [false])], (1, [true])⟩, ⟨[(0, [false])], (1, [true])⟩] := rfl
theorem boolValid : ∀ rule ∈ boolRules,
    IndexedIteration.Valid (fun key row => row ∈ boolDomain key) rule := by
  intro rule member
  simp only [boolRules, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl <;>
    simp [IndexedIteration.Valid, IndexedIteration.Schema, seedRule, stepRule,
      boolDomain, PositiveSlots.Represents, lookup, PositiveSlots.slot,
      IndexedPositiveTraversal.KnownColumns, wanted]

/-- Duplicate seed heads and an indexed literal-key consumer instantiate every
round without supplied row-admission or monotonicity premises. -/
example (n : Nat) : IndexedIteration.indexed boolRules (snapshotRows boolDomain) (fun _ => False) n =
    (IndexedIteration.naive boolRules (snapshotRows boolDomain) (fun _ => False) n,
     IndexedIteration.naive boolRules (snapshotRows boolDomain) (fun _ => False) (n + 1)) :=
  snapshot_indexed_history boolDomain boolRules boolValid _ n

/-- One component uses the constructed stabilization witness, rather than an
assumed completed native answer or a fixed iteration cutoff. -/
example (fact : Fact Nat Bool) :
    solve (programGround boolDomain boolRules) (fun _ => ())
      (planned (programGround boolDomain boolRules) (fun _ => ()) [()] (fun _ => False))
      (fun _ => False) fact ↔
    ∀ model : Database (Fact Nat Bool),
      (∀ item, False → model item) →
      (∀ rule ∈ boolRules, ∀ item,
        IndexedIteration.consequence rule (snapshotRows boolDomain) model item → model item) → model fact :=
  snapshot_component_least boolDomain boolRules (fun _ => ()) [()] (fun _ => False)
    (by simp) (by simp [Topological]) fact
#print axioms Ascent.GroundedBinding.snapshot_step_ground
#print axioms Ascent.GroundedBinding.snapshot_naive_ground
#print axioms Ascent.GroundedBinding.snapshot_rounds_spec
#print axioms Ascent.GroundedBinding.snapshot_indexed_least
#print axioms Ascent.GroundedBinding.snapshot_indexed_stays_least

example (fact : Fact Nat Bool) :
    (IndexedIteration.indexed boolRules (snapshotRows boolDomain) (fun _ => False)
      (snapshotRounds boolDomain boolRules (fun _ => False))).2 fact ↔
    Derivable (programGround boolDomain boolRules) (fun _ => False) fact :=
  snapshot_indexed_least boolDomain boolRules boolValid _ fact
example : snapshotRounds boolDomain boolRules (fun _ => False) ≤ 4 := by
  have size : (programGround boolDomain boolRules).length = 4 := rfl
  rw [← size]
  exact (snapshot_rounds_spec boolDomain boolRules (fun _ => False)).1
example (extra : Nat) (fact : Fact Nat Bool) :
    (IndexedIteration.indexed boolRules (snapshotRows boolDomain) (fun _ => False)
      (snapshotRounds boolDomain boolRules (fun _ => False) + extra)).2 fact ↔
    Derivable (programGround boolDomain boolRules) (fun _ => False) fact :=
  snapshot_indexed_stays_least boolDomain boolRules boolValid _ extra fact
end Ascent.GroundedBindingTests
