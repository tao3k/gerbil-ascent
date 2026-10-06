-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LeanPooAlignment
import Tests.IndexedIterationTests

namespace Ascent.LeanPooAlignmentTests
open LeanPooAlignment IndexedIterationTests

def request (n : Nat) : Request Bool := ⟨initial, n⟩
theorem admission : admitted rules rows domain := ⟨valid, covered, monotone⟩

/-- Actual empty-body seed and dependent rule, through the producer API. -/
theorem routed (n : Nat) :
    (sourceSolver rules rows domain (request n) admission).val =
      IndexedIteration.naive rules rows initial (n + 1) :=
  supplied_solver_correct rules rows domain (indexedSolver rules rows domain) (request n) admission

theorem routed_seed : (sourceSolver rules rows domain (request 0) admission).val false := by
  rw [routed]
  exact Or.inr ⟨seedRule, by simp [rules], [], rfl, by simp [seedRule]⟩

/-- Extracting the older snapshot fails the source contract at initialization. -/
theorem wrong_snapshot_rejected :
    ¬ (sourceProblem rules rows domain).Correct (request 0)
      (IndexedIteration.indexed rules rows initial 0).1 := by
  intro correct
  have absent : ¬ (IndexedIteration.indexed rules rows initial 0).1 false := by
    simp [IndexedIteration.indexed, initial]
  apply absent
  change (IndexedIteration.indexed rules rows initial 0).1 =
    IndexedIteration.naive rules rows initial 1 at correct
  rw [correct]
  simpa [routed] using routed_seed

#print axioms indexedRoute
#print axioms sourceSolver_value
#print axioms supplied_solver_correct
#print axioms routed
#print axioms wrong_snapshot_rejected
end Ascent.LeanPooAlignmentTests
