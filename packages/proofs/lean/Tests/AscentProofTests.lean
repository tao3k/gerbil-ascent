-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import AscentProof
import Tests.RuleBodyFrameTests
import Tests.PositiveSlotsTests
import Tests.PositiveTraversalTests
import Tests.PositiveConsequenceTests
import Tests.IndexedPositiveTraversalTests
import Tests.IndexedIterationTests
import Tests.ComponentClosureTests
import Tests.GroundedBindingTests

/-! Compile-time qualification for LeanPoo source patches, invalidation,
certificate reuse and source-count algebra. Temporal publication belongs to TLA+. -/

namespace Ascent.ProofTests

open LeanPoo.Proof
open Ascent.SourceCertificates

/-- Every positive, negative and aggregate read contributes a source-to-head
edge; guard, generator and binding clauses contribute none. Duplicate heads
are harmless to reachability, as in the native adjacency. -/
def mixedReadPlans : List (Ascent.RuleGraphClosure.Rule Bool) :=
  [{ heads := [true, true]
     body := [⟨.atom, some false⟩, ⟨.negation, some false⟩,
              ⟨.aggregate, some false⟩, ⟨.guard, none⟩,
              ⟨.generator, none⟩,
              ⟨.binding, none⟩] }]

example : true ∈ Ascent.RuleGraphClosure.ruleSuccessors mixedReadPlans false := by decide
example : Ascent.RuleGraphClosure.ruleSuccessors mixedReadPlans true = [] := by decide

#print axioms Ascent.RuleGraphClosure.completed_compiled_exact
#print axioms Ascent.RuleGraphClosure.completed_reuse_frame
#print axioms Ascent.NativeGraphWorklist.runFuel_compiled_exact
#print axioms Ascent.NativeGraphWorklist.runFuel_compiled_closed
#print axioms Ascent.NativeBitmapWorklist.runFuel_compiled_exact
#print axioms Ascent.NativeBitmapWorklist.runFuel_compiled_closed
#print axioms Ascent.SourceUpdateFrame.completed_reuse

/-- One changed source in an ordered append log reaches a recursive head,
then heads with negative and aggregate reads, while an independent relation
stays outside the computed frame. -/
def updateChain : List (Ascent.RuleGraphClosure.Rule (Fin 5)) :=
  [{ heads := [1], body := [⟨.atom, some 0⟩, ⟨.atom, some 1⟩] },
   { heads := [2], body := [⟨.negation, some 1⟩] },
   { heads := [3], body := [⟨.aggregate, some 2⟩] }]

def updateCut : Ascent.SourceUpdateFrame.Cut 5 Nat where
  base := fun key => if key = 0 then [1] else if key = 4 then [99] else []
  newestFirstAppends := fun key => if key = 0 then [3, 2] else []
  candidate := fun key => if key = 0 then [1, 2] else if key = 4 then [99] else []

example : updateCut.before 0 = [1, 2, 3] := by decide
example : updateCut.seeds = [0] := by decide
example : Ascent.SourceUpdateFrame.affected updateChain updateCut 3 := by
  change (Ascent.NativeBitmapWorklist.runFuel
    (Ascent.RuleGraphClosure.ruleSuccessors updateChain) 6
    (Ascent.NativeBitmapWorklist.initial updateCut.seeds)).selected[3] = true
  decide
example : ¬ Ascent.SourceUpdateFrame.affected updateChain updateCut 4 := by
  change (Ascent.NativeBitmapWorklist.runFuel
    (Ascent.RuleGraphClosure.ruleSuccessors updateChain) 6
    (Ascent.NativeBitmapWorklist.initial updateCut.seeds)).selected[4] ≠ true
  decide

/-- Native head admission checks its own prior rows. This modeled evaluator
has only that implicit self-read, so no explicit rule-graph edge is needed. -/
def selfReadProgram : Ascent.FunctionalDependency.Program (Fin 5)
    (fun _ => List Nat) where
  reads := fun target => [target]
  empty := fun _ => []
  evaluate := fun _ selected => selected.1 ()

theorem selfReadMatches (source target : Fin 5)
    (read : selfReadProgram.edge source target) :
    source = target ∨ Ascent.RuleGraphClosure.ReadsInto updateChain source target := by
  left
  simpa [selfReadProgram, Ascent.FunctionalDependency.Program.edge] using read

theorem selfReadStep (state : (key : Fin 5) → List Nat) :
    selfReadProgram.step state = state := by
  funext target
  rfl

example : Ascent.DependencyInvalidation.AgreeOutside
    (Ascent.SourceUpdateFrame.affected updateChain updateCut)
    (Ascent.DependencyInvalidation.iterate selfReadProgram.step 0 updateCut.before)
    (Ascent.DependencyInvalidation.iterate selfReadProgram.step 0 updateCut.candidate) := by
  exact Ascent.SourceUpdateFrame.completed_reuse updateChain updateCut
    selfReadProgram selfReadMatches 0 0
    (by simpa [Ascent.DependencyInvalidation.iterate] using
      selfReadStep updateCut.before)
    (by simpa [Ascent.DependencyInvalidation.iterate] using
      selfReadStep updateCut.candidate)

def cycleAdj : Fin 3 → List (Fin 3)
  | 0 => [1, 1]
  | 1 => [2]
  | 2 => [0]

example : (Ascent.NativeGraphWorklist.runFuel cycleAdj 4
    (Ascent.NativeGraphWorklist.initial ([0] : List (Fin 3)))).pending = [] := by
  exact Ascent.NativeGraphWorklist.runFuel_complete 3 cycleAdj _
    (Ascent.NativeGraphWorklist.initial_wellformed [0] (by decide))

example : (2 : Fin 3) ∈ (Ascent.NativeGraphWorklist.runFuel cycleAdj 4
    (Ascent.NativeGraphWorklist.initial ([0] : List (Fin 3)))).selected := by
  decide

example : (Ascent.NativeBitmapWorklist.runFuel cycleAdj 4
    (Ascent.NativeBitmapWorklist.initial ([0] : List (Fin 3)))).pending = [] := by
  have rep := Ascent.NativeBitmapWorklist.runFuel_corresponds cycleAdj 4
    (Ascent.NativeBitmapWorklist.initial [0])
    (Ascent.NativeGraphWorklist.initial [0])
    (Ascent.NativeBitmapWorklist.initial_corresponds [0])
  rw [rep.2]
  exact Ascent.NativeGraphWorklist.runFuel_complete 3 cycleAdj _
    (Ascent.NativeGraphWorklist.initial_wellformed [0] (by decide))

example : Ascent.NativeBitmapWorklist.marked
    (Ascent.NativeBitmapWorklist.runFuel cycleAdj 4
      (Ascent.NativeBitmapWorklist.initial ([0] : List (Fin 3)))) (2 : Fin 3) := by
  change (Ascent.NativeBitmapWorklist.runFuel cycleAdj 4
    (Ascent.NativeBitmapWorklist.initial ([0] : List (Fin 3)))).selected[2] = true
  decide

/-- If the negation read `source → derived` is absent from the dependency
graph, retaining `derived` after a source change is unsound. -/
def negationStep (state : Bool → Bool) (key : Bool) : Bool :=
  if key then !state false else state false

def negationBefore : Bool → Bool := fun _ => false
def negationAfter : Bool → Bool := fun key => !key
def onlySourceAffected (key : Bool) : Prop := key = false

example : Ascent.DependencyInvalidation.AgreeOutside onlySourceAffected
    negationBefore negationAfter := by
  intro key untouched
  cases key <;> simp [onlySourceAffected, negationBefore, negationAfter] at *

example : ¬ Ascent.DependencyInvalidation.AgreeOutside onlySourceAffected
    (Ascent.DependencyInvalidation.iterate negationStep 1 negationBefore)
    (Ascent.DependencyInvalidation.iterate negationStep 1 negationAfter) := by
  intro preserved
  have impossible := preserved true (by simp [onlySourceAffected])
  simp [Ascent.DependencyInvalidation.iterate, negationStep,
    negationBefore, negationAfter] at impossible

/-- A Functional.Requirements checklist can expose exactly one typed source
to a relation consumer without hand-written tuple selection. -/
def ownRead : Ascent.FunctionalDependency.Program Bool (fun _ => Bool) where
  reads := fun key => [key]
  empty := fun _ => false
  evaluate := fun _ factories => factories.1 ()

example : ownRead.step negationAfter true = negationAfter true := rfl
example : Ascent.DependencyInvalidation.Closed ownRead.edge onlySourceAffected := by
  intro source target read selected
  simp [ownRead, Ascent.FunctionalDependency.Program.edge] at read
  simpa [onlySourceAffected] using read.symm.trans selected

#print axioms Ascent.DependencyInvalidation.completed_frame
#print axioms Ascent.FunctionalDependency.Program.completed_frame

def sampleUpdates : List (Sigma fun _ : Bool => Nat) := [⟨true, 7⟩]
def sampleSource : State Bool (fun _ => Nat) := fun _ => 0

example : (Patch.setMany sampleUpdates).touched = [true] := by
  simpa [sampleUpdates] using Patch.setMany_touched sampleUpdates []

example : (Patch.setMany sampleUpdates).apply sampleSource false = 0 := by
  exact (Patch.setMany sampleUpdates).frame sampleSource false
    (by simp [Patch.setMany_touched, sampleUpdates])

example : (Patch.setMany sampleUpdates).apply sampleSource true = 7 := by
  simpa [sampleUpdates] using
    Patch.setMany_last ([] : List (Sigma fun _ : Bool => Nat)) true 7 sampleSource

def falseObligation : Obligation Bool (fun _ => Nat) :=
  resultObligation [false] (fun source => source false) (fun _ => 0) (by
    intro before after same
    exact ⟨same false (by simp), rfl⟩)

def certifiedSource : ProofObject Bool (fun _ => Nat) :=
  ⟨sampleSource, [falseObligation]⟩

theorem certifiedSource_ok : Certificate certifiedSource := by
  intro obligation member
  have h : obligation = falseObligation := by
    simpa [certifiedSource] using member
  subst obligation
  rfl

example : falseObligation.holds
    (append certifiedSource (Patch.setMany sampleUpdates)).state := by
  apply reuse_after_batch certifiedSource certifiedSource_ok falseObligation
  · simp [certifiedSource]
  · intro key member touched
    have h : key = false := by simpa [falseObligation, resultObligation] using member
    subst key
    simp [sampleUpdates] at touched

example : falseObligation ∉
    pending certifiedSource (Patch.setMany sampleUpdates) := by
  intro membership
  have selected := (pending_after_batch certifiedSource sampleUpdates [] falseObligation).mp membership
  rcases selected with ⟨_, key, depends, touched⟩ | added
  · have h : key = false := by simpa [falseObligation, resultObligation] using depends
    subst key
    simp [sampleUpdates] at touched
  · simp at added

/-- A changed source and its cached result are patched together. The old
    correctness obligation becomes pending and is proved for the new cut. -/
def pairedObligation : Obligation Bool (fun _ => Nat) :=
  resultObligation [true, false]
    (fun source => source true) (fun source => source false) (by
      intro before after same
      exact ⟨same true (by simp), same false (by simp)⟩)

def pairedSource : ProofObject Bool (fun _ => Nat) :=
  ⟨sampleSource, [pairedObligation]⟩

theorem pairedSource_ok : Certificate pairedSource := by
  intro obligation member
  have h : obligation = pairedObligation := by
    simpa [pairedSource] using member
  subst obligation
  rfl

def pairedUpdates : List (Sigma fun _ : Bool => Nat) :=
  [⟨true, 7⟩, ⟨false, 7⟩]

example : pairedObligation ∈
    pending pairedSource (Patch.setMany pairedUpdates) := by
  apply (pending_after_batch pairedSource pairedUpdates [] pairedObligation).mpr
  left
  refine ⟨by simp [pairedSource], true, ?_, ?_⟩
  · simp [pairedObligation, resultObligation]
  · simp [pairedUpdates]

theorem pairedSource_updated :
    pairedObligation.holds
      (append pairedSource (Patch.setMany pairedUpdates)).state := by
  simp [pairedObligation, resultObligation, append, pairedSource,
    pairedUpdates, Patch.setMany, Patch.composeAll, Patch.empty,
    Patch.then, Patch.set, sampleSource]

example : Certificate (append pairedSource (Patch.setMany pairedUpdates)) := by
  apply close_after_batch pairedSource pairedSource_ok pairedUpdates []
  intro obligation selected
  have owned : obligation ∈ pairedSource.obligations := by
    rcases (pending_after_batch pairedSource pairedUpdates [] obligation).mp selected with
      ⟨member, _, _, _⟩ | fresh
    · exact member
    · simp at fresh
  have same : obligation = pairedObligation := by
    simpa [pairedSource] using owned
  subst obligation
  exact pairedSource_updated

def fullAndBucket : State Bool (fun _ => List Nat) := fun _ => [1, 2]
def bindAny (_ : Unit) (_ : Nat) : Option Unit := some ()
def exactIndex : Obligation Bool (fun _ => List Nat) :=
  indexExactObligation bindAny ()
def indexObject : ProofObject Bool (fun _ => List Nat) :=
  ⟨fullAndBucket, [exactIndex]⟩

theorem indexObject_ok : Certificate indexObject := by
  intro obligation member
  have same : obligation = exactIndex := by
    simpa [indexObject] using member
  subst obligation
  constructor
  · intro value present
    exact present
  · intro value output present _
    exact present

example : StratifiedNegation.ClauseHolds
      (.negation (indexObject.state false) bindAny) () () ↔
    StratifiedNegation.ClauseHolds
      (.negation (indexObject.state true) bindAny) () () :=
  certified_indexed_negation bindAny () () indexObject indexObject_ok
    (by simp [indexObject, exactIndex])

def sourceOnly : List (Sigma fun _ : Bool => List Nat) :=
  [⟨true, [1, 2, 3]⟩]

example : exactIndex ∈ pending indexObject (Patch.setMany sourceOnly) := by
  apply (pending_after_batch indexObject sourceOnly [] exactIndex).mpr
  left
  refine ⟨by simp [indexObject], true, ?_, ?_⟩
  · simp [exactIndex, indexExactObligation]
  · simp [sourceOnly]

end Ascent.ProofTests

namespace Ascent.AtomicBinding.Tests

example : bind [.variable 0, .variable 0] [1, 2] [] = none := by decide
example : bind [.variable 0, .variable 0] [1, 1] [] = some [(0, 1)] := by decide
example : bind [.variable 0] [2] [(0, 1)] = none := by decide
example : bind [.literal false, .wildcard] [false, true] [] = some [] := by decide
example : bind ([] : List (Term Nat)) [] [] = some [] := by decide
example : bind [.variable 0] [1, 2] [] = none := by decide
example : bind [.variable 0, .wildcard] [1] [] = none := by decide

end Ascent.AtomicBinding.Tests

#print axioms Ascent.ProviderFrontier.concrete_partition
#print axioms Ascent.ProviderFrontier.new_fact_must_be_emitted
#print axioms Ascent.ProviderFrontier.binary_join_partition
#print axioms Ascent.ProviderFrontier.body_partition
#print axioms Ascent.ProviderFrontier.projected_partition
#print axioms Ascent.ProviderFrontier.projected_frontier
#print axioms Ascent.ProviderFrontier.new_consequence_pivot
#print axioms Ascent.SemiNaive.consequences_partition
#print axioms Ascent.SemiNaive.pivot_after_full
#print axioms Ascent.SemiNaive.iterations_equal

/-- Empty-body facts require the initial full execution; a pivot-only first
round cannot derive them, even though the concrete view is monotone. -/
def factRule : Ascent.SemiNaive.Rule Bool Bool Bool := ⟨[], false, fun _ => true⟩

example : Ascent.SemiNaive.fullStep [factRule]
    (fun _ _ _ _ => False) (fun _ => False) true := by
  exact Or.inr ⟨factRule, List.mem_cons_self, false, rfl, rfl⟩

example : ¬ Ascent.SemiNaive.pivotStep [factRule]
    (fun _ _ _ _ => False) (fun _ => False) (fun _ => False) true := by
  simp [Ascent.SemiNaive.pivotStep, Ascent.SemiNaive.freshConsequences,
    factRule, Ascent.ProviderFrontier.output, Ascent.ProviderFrontier.pivots]

/-- Repeated keys and multiple fresh occurrences yield a pivot derivation. -/
example : Ascent.ProviderFrontier.pivots
    (fun (_ : Bool) (a b : Bool) => a = b)
    (fun (_ : Bool) (_ _ : Bool) => True) [true, false, true] false true := by
  exact Or.inl ⟨true, ⟨True.intro, by decide⟩,
    true, True.intro, true, True.intro, rfl⟩

/-- Fresh witnesses are not necessarily fresh heads after projection. -/
example : ¬ Ascent.ProviderFrontier.delta
    (Ascent.ProviderFrontier.output
      (Ascent.ProviderFrontier.body (fun (_ : Bool) (a b : Bool) => a = b)
        [true, false, true] false) (fun _ => true))
    (Ascent.ProviderFrontier.output
      (Ascent.ProviderFrontier.body (fun (_ : Bool) (_ _ : Bool) => True)
        [true, false, true] false) (fun _ => true)) true := by
  intro fresh
  exact fresh.2 ⟨false, ⟨false, rfl, false, rfl, false, rfl, rfl⟩, rfl⟩

example (old next : Bool → Bool → Bool → Prop) (seed output : Bool) :
    ¬ Ascent.ProviderFrontier.pivots old next [] seed output := by
  simp [Ascent.ProviderFrontier.pivots]

#print axioms Ascent.TransitiveComponents.insertion_transitive
#print axioms Ascent.TransitiveComponents.insertion_least
#print axioms Ascent.TransitiveComponents.quotient_exact
#print axioms Ascent.SourceUpdateFrame.source_count_balance
#print axioms Ascent.SourceUpdateFrame.refused_source_budget
#print axioms Ascent.SourceUpdateFrame.admitted_source_budget
