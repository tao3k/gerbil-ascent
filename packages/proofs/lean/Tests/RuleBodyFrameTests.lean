-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import RuleBodyFrame

namespace Ascent.RuleBodyFrameTests

open RuleBodyFrame DependencyInvalidation

#print axioms Ascent.RuleBodyFrame.evalBody_congr
#print axioms Ascent.RuleBodyFrame.step_local
#print axioms Ascent.RuleBodyFrame.completed_reuse

/-- The same eight-relation chain as the native stratified Session fixture.
Unary sources use a zero second field; bindings are the current row pair. -/
abbrev Pair := Nat × Nat
abbrev FixtureRule := Rule (Fin 8) Pair Pair

def keepRow (row : Pair) (_ : Pair) : Option Pair := some row

def joinRow (row env : Pair) : Option Pair :=
  if row.1 = env.2 then some (env.1, row.2) else none

def fixture : List FixtureRule :=
  [{ heads := [⟨4, id⟩], body := [.atom 0 keepRow], seed := (0, 0) },
   { heads := [⟨4, id⟩], body := [.atom 4 keepRow, .atom 0 joinRow], seed := (0, 0) },
   { heads := [⟨5, id⟩]
     body := [.atom 4 keepRow,
       .negation 1 (fun row env => if row.1 = env.2 then some env else none)]
     seed := (0, 0) },
   { heads := [⟨6, id⟩]
     body := [.atom 5 keepRow, .atom 2 joinRow,
       .guard (fun env => env.2 % 2 == 0), .binding (fun env => (env.1, env.2 * 2))]
     seed := (0, 0) },
   { heads := [⟨7, id⟩]
     body := [.atom 3 keepRow,
       .aggregate 6 (fun row env => if row.1 = env.1 then some row else none)
         (fun tuples env => [(env.1, tuples.foldl (fun sum row => sum + row.2) 0)])]
     seed := (0, 0) }]

def fixtureAdmit (target : Fin 8) (old emitted : List Pair) : List Pair :=
  if target.val < 4 then old else emitted.eraseDups

def fixtureStep := step fixture fixtureAdmit

def fixtureCut : SourceUpdateFrame.Cut 8 Pair where
  base := fun key =>
    if key = 0 then [(0, 1)]
    else if key = 2 then [(1, 2), (2, 4)]
    else if key = 3 then [(0, 0)] else []
  newestFirstAppends := fun key => if key = 0 then [(1, 2)] else []
  candidate := fun key =>
    if key = 0 then [(0, 1), (1, 2)]
    else if key = 1 then [(2, 0)]
    else if key = 2 then [(1, 3), (2, 4)]
    else if key = 3 then [(0, 0)] else []

example : fixtureCut.seeds = [1, 2] := by decide
example : ¬ SourceUpdateFrame.affected (plans fixture) fixtureCut 4 := by
  unfold SourceUpdateFrame.affected NativeBitmapWorklist.marked
  decide
example : SourceUpdateFrame.affected (plans fixture) fixtureCut 5 := by
  unfold SourceUpdateFrame.affected NativeBitmapWorklist.marked
  decide
example : SourceUpdateFrame.affected (plans fixture) fixtureCut 7 := by
  unfold SourceUpdateFrame.affected NativeBitmapWorklist.marked
  decide

def oldResult := iterate fixtureStep 6 fixtureCut.before
def newResult := iterate fixtureStep 5 fixtureCut.candidate

example : oldResult 7 = [(0, 12)] := by decide
example : newResult 7 = [(0, 0)] := by decide
example : oldResult 4 = [(0, 1), (1, 2), (0, 2)] := by decide
example : newResult 5 = [(0, 1)] := by decide
example : newResult 6 = [] := by decide

theorem oldStable : fixtureStep oldResult = oldResult := by
  have same : ∀ key, fixtureStep oldResult key = oldResult key := by decide
  exact funext same

theorem newStable : fixtureStep newResult = newResult := by
  have same : ∀ key, fixtureStep newResult key = newResult key := by decide
  exact funext same

/-- Actual nontrivial recursive/negative/aggregate completed runs instantiate
the composed theorem, including different completion round counts. -/
example : AgreeOutside (SourceUpdateFrame.affected (plans fixture) fixtureCut)
    oldResult newResult :=
  completed_reuse fixture fixtureAdmit fixtureCut 6 5 oldStable newStable

/-- Repeated and distinct heads share one body traversal. The negative check,
guard and binding preserve ordered branching and emit each selected head. -/
def multiHead : Rule (Fin 3) Nat Nat where
  heads := [⟨1, id⟩, ⟨2, fun value => value + 10⟩, ⟨1, id⟩]
  body := [.atom 0 (fun row _ => some row),
    .guard (fun value => value % 2 == 0), .binding (fun value => value * 2)]
  seed := 0

def multiSource : Fin 3 → List Nat := fun key => if key = 0 then [1, 2, 4] else []

example : multiHead.outputs 1 multiSource = [4, 4, 8, 8] := by decide
example : multiHead.outputs 2 multiSource = [14, 18] := by decide
example : RuleGraphClosure.ReadsInto (plans [multiHead]) 0 2 := by
  rw [← RuleGraphClosure.mem_ruleSuccessors_iff]
  decide
example : ¬ RuleGraphClosure.ReadsInto (plans [multiHead]) 1 2 := by
  rw [← RuleGraphClosure.mem_ruleSuccessors_iff]
  decide

namespace OmittedReads

def cut : SourceUpdateFrame.Cut 2 Nat where
  base := fun _ => []
  newestFirstAppends := fun _ => []
  candidate := fun key => if key = 0 then [1] else []

def admit (target : Fin 2) (old emitted : List Nat) : List Nat :=
  if target = 0 then old else emitted

def negative : Rule (Fin 2) Nat Nat where
  heads := [⟨1, id⟩]
  body := [.negation 0 (fun _ env => some env)]
  seed := 7

def aggregate : Rule (Fin 2) Nat Nat where
  heads := [⟨1, id⟩]
  body := [.aggregate 0 (fun row _ => some row)
    (fun values _ => [values.foldl (· + ·) 0])]
  seed := 0

/-- Fault graph: its head is present, but the reading body was dropped. -/
def badPlans : List (RuleGraphClosure.Rule (Fin 2)) := [⟨[1], []⟩]

theorem unselected : ¬ SourceUpdateFrame.affected badPlans cut 1 := by
  unfold SourceUpdateFrame.affected NativeBitmapWorklist.marked
  decide
example : SourceUpdateFrame.affected (plans [negative]) cut 1 := by
  unfold SourceUpdateFrame.affected NativeBitmapWorklist.marked
  decide
example : SourceUpdateFrame.affected (plans [aggregate]) cut 1 := by
  unfold SourceUpdateFrame.affected NativeBitmapWorklist.marked
  decide

example : step [negative] admit cut.before 1 = [7] := by decide
example : step [negative] admit cut.candidate 1 = [] := by decide
example : step [aggregate] admit cut.before 1 = [0] := by decide
example : step [aggregate] admit cut.candidate 1 = [1] := by decide

/-- Both fault controls reach completed fixed points after one round. -/
theorem completed (rule : Rule (Fin 2) Nat Nat)
    (kind : rule = negative ∨ rule = aggregate)
    (state : Fin 2 → List Nat) :
    step [rule] admit (step [rule] admit state) = step [rule] admit state := by
  rcases kind with rfl | rfl <;> funext key
  · have cases : key = 0 ∨ key = 1 := by omega
    rcases cases with rfl | rfl <;> rfl
  · have cases : key = 0 ∨ key = 1 := by omega
    rcases cases with rfl | rfl <;> rfl

theorem stale_negative : ¬ AgreeOutside (SourceUpdateFrame.affected badPlans cut)
    (step [negative] admit cut.before) (step [negative] admit cut.candidate) := by
  intro frame
  have wrong := frame 1 unselected
  have different : step [negative] admit cut.before 1 ≠
      step [negative] admit cut.candidate 1 := by decide
  exact different wrong

theorem stale_aggregate : ¬ AgreeOutside (SourceUpdateFrame.affected badPlans cut)
    (step [aggregate] admit cut.before) (step [aggregate] admit cut.candidate) := by
  intro frame
  have wrong := frame 1 unselected
  have different : step [aggregate] admit cut.before 1 ≠
      step [aggregate] admit cut.candidate 1 := by decide
  exact different wrong

end OmittedReads
end Ascent.RuleBodyFrameTests
