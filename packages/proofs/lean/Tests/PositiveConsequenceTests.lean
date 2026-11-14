-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveConsequence

namespace Ascent.PositiveConsequenceTests
open AtomicBinding PositiveSlots PositiveTraversal PositiveConsequence

#print axioms Ascent.PositiveConsequence.reference_membership
#print axioms Ascent.PositiveConsequence.precompiled_membership
#print axioms Ascent.PositiveConsequence.enumerated_view_monotone
#print axioms Ascent.PositiveConsequence.binder_iterations_equal
#print axioms Ascent.PositiveConsequence.admitted_rows_faithful
#print axioms Ascent.PositiveConsequence.admitted_binder_iterations_equal

def atoms : List (PositiveConsequence.Atom Bool Bool) :=
  [⟨false, [.variable 10]⟩,
   ⟨true, [.variable 20, .variable 10, .literal false]⟩]
def rows : Bool → List (List Bool)
  | false => [[false], [true]]
  | true => [[true, true, true], [false, false, false],
             [true, false, false], [false, false, false]]
def head (env : Env Bool) := (lookup 10 env, lookup 20 env)
def slotHead (names : List Nat) (frame : Frame Bool) :=
  [((slot 10 names).map frame, (slot 20 names).map frame)]

theorem emits (names : List Nat) (env : Env Bool) (frame : Frame Bool)
    (rep : Represents names env frame) : slotHead names frame = [head env] := by
  simp only [slotHead, head, rep 10, rep 20]

theorem arity : Arity (instantiate atoms rows) := by
  simp [Arity, instantiate, atoms, rows]

theorem emptyRep (frame : Frame Bool) : Represents [] [] frame := by
  intro name
  rfl

/-- Literal failure after fresh writes must not corrupt the next candidate;
distinct body witnesses and duplicate rows remain ordered before Set admission. -/
example : (runBody (compileBody (instantiate atoms rows) []).1
    (compileBody (instantiate atoms rows) []).2 slotHead (fun _ => true)).1 =
    [(some false, some false), (some false, some true), (some false, some false)] := by
  decide

example (frame : Frame Bool) (value : Option Bool × Option Bool) :
    value ∈ (runBody (compileBody (instantiate atoms rows) []).1
      (compileBody (instantiate atoms rows) []).2 slotHead frame).1 ↔
      ProviderFrontier.output
        (ProviderFrontier.body (transition rows) atoms []) head value :=
  precompiled_membership atoms rows head slotHead emits arity [] [] frame
    (emptyRep frame) value

/-- A continuation can produce duplicate projected heads without new Set facts. -/
example : (reference (instantiate atoms rows) (fun _ => [true, true]) []).length = 6 := by
  decide

end Ascent.PositiveConsequenceTests
