-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveTraversal

namespace Ascent.PositiveTraversalTests
open AtomicBinding PositiveSlots PositiveTraversal

#print axioms Ascent.PositiveTraversal.scan_refines
#print axioms Ascent.PositiveTraversal.precompiled_refines
#print axioms Ascent.PositiveTraversal.walk_reuse

def body : List (Atom Bool) :=
  [⟨[.variable 10], [[false], [true]]⟩,
   ⟨[.variable 20, .variable 10, .variable 20, .literal false],
     [[true, true, true, false], [false, false, false, false], [true, false, true, false]]⟩,
   ⟨[.variable 30, .variable 20, .variable 30, .variable 10],
     [[true, true, false, false], [false, false, false, false],
      [true, true, true, false], [false, true, false, true]]⟩]
def heads : List (Nat × List (Term Bool)) :=
  [(3, [.variable 10, .variable 20, .variable 30, .literal false]),
   (4, [.variable 30, .variable 20, .variable 10, .literal false]),
   (3, [.variable 10, .variable 20, .variable 30, .literal false])]
def envEmit (env : Env Bool) : List (Nat × List (Option Bool)) :=
  heads.map fun head => (head.1, observeHead head.2 env)
def slotEmit (names : List Nat) (frame : Frame Bool) : List (Nat × List (Option Bool)) :=
  heads.map fun head => (head.1, observeSlots head.2 names frame)

theorem emits (names : List Nat) (env : Env Bool) (frame : Frame Bool)
    (rep : Represents names env frame) : slotEmit names frame = envEmit env := by
  apply List.map_congr_left
  intro head _
  rw [head_observations head.2 names env frame rep]

theorem arity : Arity body := by
  simp [Arity, body]

/-- New slot contents can be arbitrary before the first traversal. -/
theorem emptyRep (frame : Frame Bool) : Represents [] [] frame := by
  intro name; rfl

example (frame : Frame Bool) :
    (runBody (compileBody body []).1 (compileBody body []).2 slotEmit frame).1 =
      reference body envEmit [] :=
  precompiled_refines body slotEmit envEmit emits arity [] [] frame (emptyRep frame)

example : (reference body envEmit []).length = 9 := by decide
example : reference body envEmit [] =
  [(3, [some false, some false, some false, some false]),
   (4, [some false, some false, some false, some false]),
   (3, [some false, some false, some false, some false]),
   (3, [some false, some true, some true, some false]),
   (4, [some true, some true, some false, some false]),
   (3, [some false, some true, some true, some false]),
   (3, [some true, some true, some false, some false]),
   (4, [some false, some true, some true, some false]),
   (3, [some true, some true, some false, some false])] := by decide

/-- A complete traversal reuses its actual returned dirty frame. -/
example (frame : Frame Bool) :
    (walk body [] slotEmit (walk body [] slotEmit frame).2).1 = reference body envEmit [] :=
  walk_refines body slotEmit envEmit emits arity [] [] _
    (walk_reuse body [] [] slotEmit frame (emptyRep frame))

/-- Empty and zero-arity bodies preserve duplicate literal emissions. -/
example (frame : Frame Bool) :
    (walk [⟨[], [[], []]⟩] [] (fun _ _ => ([false, false] : List Bool)) frame).1 =
      [false, false, false, false] := rfl

/-- Fault control: a suffix that overwrites the parent's bound slot destroys
candidate reuse. The prefix law is a necessary continuation obligation. -/
example : (scan ([.bound 0] : List (Action Bool))
    (fun frame => ([7], write frame 0 true)) [[false], [false]] (fun _ => false)).1 =
      ([7] : List Nat) := by decide
example : ([[false], [false]] : List (List Bool)).flatMap
    (fun row => match AtomicBinding.bind [.variable 10] row [(10, false)] with
      | none => [] | some _ => [7]) = ([7, 7] : List Nat) := by decide

end Ascent.PositiveTraversalTests
