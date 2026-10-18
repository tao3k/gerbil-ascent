-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import IndexedIteration
import Tests.IndexedPositiveTraversalTests

namespace Ascent.IndexedIterationTests
open AtomicBinding PositiveSlots IndexedIteration
#print axioms Ascent.IndexedIteration.batch_refines
#print axioms Ascent.IndexedIteration.returned_frame_valid
#print axioms Ascent.IndexedIteration.pivot_frame_independent
#print axioms Ascent.IndexedIteration.pivot_after_full
#print axioms Ascent.IndexedIteration.indexed_iterations_equal
#print axioms Ascent.IndexedIteration.stable_indexed

noncomputable def rows (database : SemiNaive.Database Bool) (_ : Unit) : List (List Bool) := by
  classical
  exact if database false then [[false]] else []
def domain (_ : Unit) (row : List Bool) : Prop := row = [false]
def seedRule : Rule Unit Bool Bool :=
  ⟨[], [], [], (fun _ => true), (fun _ => [false, false]), (fun _ _ => [false, false])⟩
def nextRule : Rule Unit Bool Bool :=
  ⟨[(⟨(), [.literal false]⟩, [0])], [], [], (fun _ => true),
    (fun _ => [true, true]), (fun _ _ => [true, true])⟩
def rules : List (Rule Unit Bool Bool) := [seedRule, nextRule]
def initial : SemiNaive.Database Bool := fun _ => False

theorem covered : RowsAdmitted domain rows := by
  intro database key row member
  unfold rows at member
  split at member
  · simpa [domain] using member
  · simp at member

theorem monotone : RowsMonotone rows := by
  intro before after included key row member
  unfold rows at *
  split at member
  · rename_i present
    simp [included false present] at *
    exact member
  · simp at member

theorem seedValid : Valid domain seedRule := by
  refine ⟨trivial, ?_, fun _ _ _ _ => rfl⟩
  intro name; rfl

theorem nextValid : Valid domain nextRule := by
  refine ⟨⟨?_, ?_, trivial⟩, ?_, fun _ _ _ _ => rfl⟩
  · intro row admitted
    subst row; rfl
  · intro env frame represented
    simp [IndexedPositiveTraversal.KnownColumns, wanted]
  · intro name; rfl

theorem valid : ∀ rule ∈ rules, Valid domain rule := by
  intro rule member
  simp only [rules, List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl
  · exact seedValid
  · exact nextValid

/-- Empty-body seed execution is full, duplicates are admitted once, and
another rule consumes the seed only in the following frozen-snapshot round. -/
example (n : Nat) : indexed rules rows initial n =
    (naive rules rows initial n, naive rules rows initial (n + 1)) :=
  indexed_iterations_equal rules rows domain valid covered monotone initial n

example : naive rules rows initial 1 false := by
  exact Or.inr ⟨seedRule, by simp [rules], [], rfl, by simp [seedRule]⟩
example : ¬ naive rules rows initial 1 true := by
  simp [naive, fullStep, initial, rules, consequence, seedRule, nextRule,
    rows, ProviderFrontier.body, PositiveConsequence.transition]

theorem stable : naive rules rows initial 3 = naive rules rows initial 2 := by
  funext item; apply propext
  cases item <;> simp [naive, fullStep, initial, rules, consequence, seedRule, nextRule,
    rows, ProviderFrontier.body, PositiveConsequence.transition, AtomicBinding.bind]

example (extra : Nat) : (indexed rules rows initial (2 + extra)).2 = naive rules rows initial 2 :=
  stable_indexed rules rows domain valid covered monotone initial 2 stable extra

/-- Actual dirty returns are threaded across all pivot positions, rather than
restarting each position from a cleared frame. This uses the deep indexed
fixture with repeated columns and 32-row delta buckets. -/
example : Represents IndexedPositiveTraversalTests.names IndexedPositiveTraversalTests.input
    (batch IndexedPositiveTraversalTests.body IndexedPositiveTraversalTests.names
      IndexedPositiveTraversalTests.slotEmit [0, 1] IndexedPositiveTraversalTests.dirty).2 :=
  batch_reuse _ _ _ _ _ _ IndexedPositiveTraversalTests.rep
end Ascent.IndexedIterationTests
