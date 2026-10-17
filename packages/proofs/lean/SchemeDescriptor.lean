-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DescriptorKernel

/-! Scheme wildcard descriptors carry a payload which Scheme equal? preserves.
Contextual decoding must not erase a mismatched wildcard payload. `invalid`
includes malformed pairs, unknown tags and non-exact/nonnegative slot values;
the host pair/integer/equality primitives remain representation assumptions. -/
namespace Ascent.SchemeDescriptor
open AtomicBinding DescriptorStream DescriptorKernel

inductive Source (Value : Type) where
  | variable (name : Nat)
  | literal (value : Value)
  | wildcard (payload : Value)

inductive Datum (Value : Type) where
  | fresh (slot : Nat)
  | bound (slot : Nat)
  | literal (value : Value)
  | wildcard (payload : Value)
  | invalid

def term : Source Value → Term Value
  | .variable name => .variable name
  | .literal value => .literal value
  | .wildcard _ => .wildcard

def decodeFor [DecidableEq Value] (source : Source Value) : Datum Value → EncodedAction Value
  | .fresh slot => .fresh slot
  | .bound slot => .bound slot
  | .literal value => .literal value
  | .wildcard payload => match source with
    | .wildcard expected => if payload = expected then .wildcard else .invalid
    | _ => .invalid
  | .invalid => .invalid

def schemeStep [DecidableEq Value] (code : Code) (head : Bool)
    (source : Source Value) (actual : Datum Value) (symbols : Symbols) : Option Symbols :=
  match source, actual with
  | .literal expected, .literal actual => if actual = expected then some symbols else none
  | .wildcard expected, .wildcard actual => if actual = expected then some symbols else none
  | .variable name, _ =>
      applyMove (run ⟨symbols.find name, symbols.count, head, decodeFor source actual⟩ code) symbols name
  | _, _ => none

theorem source_decoder_exact [DecidableEq Value] (source : Source Value)
    (actual : Datum Value) (symbols : Symbols) (head : Bool) :
    schemeStep variableCode head source actual symbols =
      executeOne variableCode head (term source) (decodeFor source actual) symbols := by
  cases source <;> cases actual <;>
    simp [schemeStep, executeOne, term, decodeFor, decode, checkOne, lowerMap]
  all_goals split <;> simp_all

end Ascent.SchemeDescriptor
