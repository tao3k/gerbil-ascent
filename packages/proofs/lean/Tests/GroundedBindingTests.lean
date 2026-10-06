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

noncomputable def rows (database : Database (Fact Nat Nat)) (key : Nat) : List (List Nat) := by
  classical
  exact (domainRows key).filter (fun row => decide (database (key, row)))
theorem faithful : ∀ database key row, row ∈ rows database key ↔
    row ∈ domainRows key ∧ database (key, row) := by
  classical
  intro database key row
  simp [rows]
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
end Ascent.GroundedBindingTests
