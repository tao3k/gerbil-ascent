-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ScalarEncoding

namespace Ascent.ScalarEncodingTests
open AtomicBinding PositiveSlots ScalarEncoding

#print axioms ScalarEncoding.decoder_faithful
#print axioms ScalarEncoding.bind_encoding
#print axioms ScalarEncoding.run_encoding
#print axioms ScalarEncoding.compile_encoding
#print axioms ScalarEncoding.observations_encoding
#print axioms ScalarEncoding.compiled_run_encoding
#print axioms ScalarEncoding.key_encoding

-- An option encoding keeps false distinct from absence and true.
def encode (value : Bool) : Option Bool := some value
example : Function.Injective encode := decoder_faithful encode id (fun _ => rfl)

def terms : List (Term Bool) := [.variable 20, .variable 10, .variable 20, .literal false]
def env : Env Bool := [(10, false)]
def dirty : Frame Bool := fun _ => false

-- A rejected candidate keeps its fresh true write, not a fabricated rollback.
example : (run ((compile terms [10]).1.map (action encode))
    ([true, true, true, false].map encode) (fun key => encode (dirty key))).1 = false := by decide
example : (run ((compile terms [10]).1.map (action encode))
    ([true, true, true, false].map encode) (fun key => encode (dirty key))).2 1 = some true := by decide
example : bind (terms.map (term encode)) ([false, false, false, false].map encode)
    (environment encode env) = some [(20, some false), (10, some false)] := by decide

-- Fault discriminator: collapsing false/true admits an invalid repeated value.
def collapse (_ : Bool) : Nat := 0
example : bind ([.variable 1, .variable 1] : List (Term Bool)) [false, true] [] = none := by decide
example : bind (([.variable 1, .variable 1] : List (Term Bool)).map (term collapse))
    ([false, true].map collapse) [] = some [(1, 0)] := by decide
example : observeSlots ([.variable 1, .wildcard, .literal false] : List (Term Bool))
    [1] dirty = [some false, none, some false] := by decide
example : observeSlots (([.variable 1, .wildcard, .literal false] : List (Term Bool)).map (term encode))
    [1] (fun key => encode (dirty key)) = [some (some false), none, some (some false)] := by decide
end Ascent.ScalarEncodingTests
