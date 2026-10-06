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

#print axioms Ascent.PositiveTraversal.scan_vector_refines
#print axioms Ascent.PositiveTraversal.body_vector_refines
#print axioms Ascent.PositiveTraversal.compile_body_length
#print axioms Ascent.PositiveTraversal.compile_body_bounds
#print axioms Ascent.PositiveTraversal.finite_precompiled_refines

def vectorEmit (names : List Nat) (vector : Vector Bool 3) :=
  heads.map fun head => (head.1, observeVectorSlots head.2 names vector)

theorem vectorEmits (frame : Frame Bool) (vector : Vector Bool 3)
    (rep : VectorRep frame vector) :
    vectorEmit (compileBody body []).2 vector = slotEmit (compileBody body []).2 frame := by
  have finalNames : (compileBody body []).2 = [10, 20, 30] := by cbv
  rw [finalNames]
  simp only [vectorEmit, slotEmit]
  apply List.map_congr_left
  intro head _
  exact congrArg (fun row => (head.1, row))
    (vector_head_observations head.2 [10, 20, 30] frame vector rep (by decide))

/-- The theorem is exercised on arbitrary dirty cells, not just a clean frame. -/
example (vector : Vector Bool 3) :
    ∃ result, runBodyVector (compileBody body []).1 (compileBody body []).2 vectorEmit vector = some result ∧
      result.1 = reference body envEmit [] ∧
      VectorRep (runBody (compileBody body []).1 (compileBody body []).2 slotEmit
        (vectorFrame vector false)).2 result.2 ∧
      ∀ outside, Represents [] [] (vectorFrame result.2 outside) :=
  finite_precompiled_refines body slotEmit vectorEmit envEmit [] emits vectorEmits
    arity [] _ vector (emptyRep _) (vector_frame_rep vector false) (by decide)

example : (runBodyVector (compileBody body []).1 (compileBody body []).2
    vectorEmit #v[true, false, true]).map Prod.fst = some (reference body envEmit []) := by cbv

/-- Reuse the complete traversal's actual dirty return without resetting cells. -/
example : (do
    let first ← runBodyVector (compileBody body []).1 (compileBody body []).2 vectorEmit #v[true, false, true]
    let second ← runBodyVector (compileBody body []).1 (compileBody body []).2 vectorEmit first.2
    pure second.1) = some (reference body envEmit []) := by cbv

example : runBodyVector [⟨[], [[], []]⟩] []
    (fun _ _ => ([false, false] : List Bool)) (#v[] : Vector Bool 0) =
    some ([false, false, false, false], #v[]) := by cbv
example : runBodyVector ([] : List (SlotAtom Bool)) []
    (fun _ _ => ([true, true] : List Bool)) (#v[] : Vector Bool 0) =
    some ([true, true], #v[]) := by cbv

/-- Bounds failure propagates through a nested atom rather than becoming a
false match or allowing a partially emitted result to escape. -/
example : runBodyVector [⟨[.fresh 0], [[true]]⟩, ⟨[.fresh 1], [[false]]⟩] []
    (fun _ _ => ([7] : List Nat)) #v[false] = none := by cbv

/-- A larger caller vector retains every cell beyond the compiled extent. -/
example : (runBodyVector (compileBody body []).1 (compileBody body []).2
    (fun names (vector : Vector Bool 4) => heads.map fun head =>
      (head.1, observeVectorSlots head.2 names vector)) #v[true, false, true, true]).map
      (fun result => result.2[3]) = some true := by cbv

/-- A continuation that corrupts its parent's slot changes candidate reuse;
the finite model detects the same failure as the function-frame model. -/
example : scanVector ([.bound 0] : List (Action Bool))
    (fun vector => some (([7] : List Nat), vector.set 0 true))
    [[false], [false]] #v[false] = some ([7], #v[true]) := by cbv

/-- A nonempty initial prefix remains represented after the actual finite
return; only the existing false binding is fixed, newer cells are arbitrary. -/
example (vector : Vector Bool 3) (bound : vector[0] = false) :
    ∃ result, runBodyVector (compileBody body [10]).1 (compileBody body [10]).2 vectorEmit vector = some result ∧
      result.1 = reference body envEmit [(10, false)] ∧
      VectorRep (runBody (compileBody body [10]).1 (compileBody body [10]).2 slotEmit
        (vectorFrame vector false)).2 result.2 ∧
      ∀ outside, Represents [10] [(10, false)] (vectorFrame result.2 outside) := by
  have initial : Represents [10] [(10, false)] (vectorFrame vector false) := by
    intro name
    by_cases same : name = 10 <;> simp [lookup, slot, same, vectorFrame, bound]
  apply finite_precompiled_refines body slotEmit vectorEmit envEmit [10] emits
  · have finalNames : (compileBody body [10]).2 = (compileBody body []).2 := by cbv
    simpa only [finalNames] using vectorEmits
  · exact arity
  · exact initial
  · exact vector_frame_rep vector false
  · decide

end Ascent.PositiveTraversalTests
