-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveSlots

namespace Ascent.PositiveSlotsTests

open PositiveSlots AtomicBinding

#print axioms Ascent.PositiveSlots.compiled_binding
#print axioms Ascent.PositiveSlots.candidate_reuse
#print axioms Ascent.PositiveSlots.compiled_head
#print axioms Ascent.PositiveSlots.compile_slots_bounded

def names : List Nat := [10]
def input : Env Bool := [(10, false)]
def dirty : Frame Bool := fun _ => false
def terms : List (Term Bool) :=
  [.variable 20, .variable 10, .variable 20, .literal false, .wildcard]
def rejected : List Bool := [true, true, true, false, false]
def accepted : List Bool := [false, false, false, false, true]
def outputs : List (Term Bool) := [.variable 10, .variable 20, .literal false]

theorem inputRep : Represents names input dirty := by
  intro name
  by_cases same : name = 10 <;> simp [names, input, lookup, slot, dirty, same]

example : (compile terms names).1 =
    [.fresh 1, .bound 0, .bound 1, .literal false, .wildcard] := by decide
example : (compile terms names).2 = [10, 20] := by decide
example : (run (compile terms names).1 rejected dirty).1 = false := by decide
example : (run (compile terms names).1 rejected dirty).2 0 = false := by decide
example : (run (compile terms names).1 rejected dirty).2 1 = true := by decide

/-- The failed candidate wrote slot 1, but the same frame remains valid for
the original prefix. The next candidate must overwrite that dirty slot. -/
theorem rejectedRep : Represents names input (run (compile terms names).1 rejected dirty).2 :=
  candidate_reuse terms rejected names input dirty inputRep

example : (run (compile terms names).1 accepted
    (run (compile terms names).1 rejected dirty).2).1 = true := by decide
example : AtomicBinding.bind terms accepted input = some [(20, false), (10, false)] := by decide

example : observeSlots outputs (compile terms names).2
    (run (compile terms names).1 accepted
      (run (compile terms names).1 rejected dirty).2).2 =
      [some false, some false, some false] := by decide

/-- A genuinely dirty Boolean false is a bound value, not an absent binding. -/
example : (run (compile terms names).1 accepted
    (run (compile terms names).1 rejected dirty).2).1 = true ∧
    observeHead outputs [(20, false), (10, false)] =
      observeSlots outputs (compile terms names).2
        (run (compile terms names).1 accepted
          (run (compile terms names).1 rejected dirty).2).2 :=
  compiled_head terms outputs accepted names input _ _ (by decide) rejectedRep (by decide)

/-- Fault control: treating the first occurrence as bound reads the leftover
slot and rejects a valid row. It is precisely the missing overwrite law. -/
def badActions : List (Action Bool) :=
  [.bound 1, .bound 0, .bound 1, .literal false, .wildcard]

example : (run badActions accepted (run (compile terms names).1 rejected dirty).2).1 = false := by decide
example : AtomicBinding.bind terms accepted input ≠ none := by decide

/-- Repeated first-atom variables get one fresh slot followed by bound checks;
all used IDs fit the dense extent produced by lowering. -/
example : (compile ([.variable 42, .variable 42, .literal true] : List (Term Bool)) []).1 =
    [.fresh 0, .bound 0, .literal true] := by decide

example (action : Action Bool) (member : action ∈ (compile terms names).1) :
    action.InRange 2 := compile_slots_bounded terms names action member

#print axioms Ascent.PositiveSlots.vector_frame_rep
#print axioms Ascent.PositiveSlots.vector_write_rep
#print axioms Ascent.PositiveSlots.vector_run_refines
#print axioms Ascent.PositiveSlots.compiled_vector_refines

/-- Finite frames retain partial writes on rejection and overwrite them on reuse. -/
example : runVector (compile terms names).1 rejected #v[false, false] =
    some (false, #v[false, true]) := by decide
example : runVector (compile terms names).1 accepted #v[false, true] =
    some (true, #v[false, false]) := by decide
example : runVector (compile terms names).1 accepted #v[false, true, true] =
    some (true, #v[false, false, true]) := by decide

/-- Capacity failure is distinct from an ordinary false candidate. -/
example : runVector [.fresh 2] [true] #v[false, false] = none := by decide
example : runVector [.bound 0] [true] #v[false] = some (false, #v[false]) := by decide
example : runVector [.wildcard] [false] (#v[] : Vector Bool 0) =
    some (true, #v[]) := by decide

end Ascent.PositiveSlotsTests
