-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import IndexedIteration
import LeanPoo.Functional.SolverTransport

/-! Align the existing compiled iteration witness with LeanPoo's public
input-indexed solver transport. No native execution or termination is assumed. -/
namespace Ascent.LeanPooAlignment
open LeanPoo.Functional.Transformation
open IndexedIteration
variable {Key Value Output : Type} [DecidableEq Value]

structure Request (Output : Type) where
  initial : SemiNaive.Database Output
  round : Nat

def admitted (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) : Prop :=
  (∀ rule ∈ rules, Valid domain rule) ∧ RowsAdmitted domain rows ∧ RowsMonotone rows

/-- Source clients request the full-binder result after round + 1. -/
def sourceProblem (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) : Problem where
  Input := Request Output
  Result := fun _ => SemiNaive.Database Output
  Valid := fun _ => admitted rules rows domain
  Correct := fun request result =>
    result = naive rules rows request.initial (request.round + 1)

/-- The target supplies the actual pair returned by compiled indexed execution. -/
def indexedProblem (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) : Problem where
  Input := Request Output
  Result := fun _ => SemiNaive.Database Output × SemiNaive.Database Output
  Valid := fun _ => admitted rules rows domain
  Correct := fun request result => result = indexed rules rows request.initial request.round

/-- Soundness is the existing ASCENT refinement, not an arbitrary client callback.
The exact request is preserved; only the target result is projected. -/
def indexedRoute (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) :
    CertifiedTransformation (sourceProblem rules rows domain) (indexedProblem rules rows domain) where
  forward := id
  preserves := fun _ valid => valid
  extract := fun _ result => result.2
  sound := by
    intro request valid result correct
    obtain ⟨schema, covered, monotone⟩ := valid
    change result = indexed rules rows request.initial request.round at correct
    change result.2 = naive rules rows request.initial (request.round + 1)
    rw [correct, indexed_iterations_equal rules rows domain schema covered monotone]

/-- This is the mathematical compiled evaluator with its exact-result proof.
It is not an executable Scheme bridge or a solver synthesized from existence. -/
def indexedSolver (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) : Solver (indexedProblem rules rows domain) :=
  fun request _ => ⟨indexed rules rows request.initial request.round, rfl⟩

def sourceSolver (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) : Solver (sourceProblem rules rows domain) :=
  (indexedRoute rules rows domain).pullSolver (indexedSolver rules rows domain)

/-- The transported data is the actual target's newer snapshot. -/
theorem sourceSolver_value (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (request : Request Output)
    (valid : admitted rules rows domain) :
    (sourceSolver rules rows domain request valid).val =
      (indexed rules rows request.initial request.round).2 := rfl

/-- Any supplied target implementation must certify its exact indexed result. -/
theorem supplied_solver_correct (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (target : Solver (indexedProblem rules rows domain))
    (request : Request Output) (valid : admitted rules rows domain) :
    ((indexedRoute rules rows domain).pullSolver target request valid).val =
      naive rules rows request.initial (request.round + 1) :=
  ((indexedRoute rules rows domain).pullSolver target request valid).property

end Ascent.LeanPooAlignment
