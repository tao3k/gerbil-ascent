-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveSlots

/-! Equality-preserving value representation for the callback-free binder and
slot machine. Variable identities and slot addresses are unchanged. Injectivity
is required: identifying two distinct admitted values can change acceptance.
This does not assert that arbitrary Scheme values or user hashes are lawful. -/
namespace Ascent.ScalarEncoding
open AtomicBinding PositiveSlots

variable {Value Encoded : Type}

/-- A partial native decoder can reject values outside admission. Round-trip
correctness on admitted values suffices to establish the comparison premise. -/
theorem decoder_faithful (encode : Value → Encoded) (decode : Encoded → Option Value)
    (roundTrip : ∀ value, decode (encode value) = some value) : Function.Injective encode := by
  intro a b equal
  have decoded := congrArg decode equal
  rw [roundTrip, roundTrip] at decoded
  exact Option.some.inj decoded

def term (encode : Value → Encoded) : Term Value → Term Encoded
  | .literal value => .literal (encode value)
  | .variable name => .variable name
  | .wildcard => .wildcard

def environment (encode : Value → Encoded) (env : Env Value) : Env Encoded :=
  env.map fun entry => (entry.1, encode entry.2)

def action (encode : Value → Encoded) : Action Value → Action Encoded
  | .literal value => .literal (encode value)
  | .fresh index => .fresh index
  | .bound index => .bound index
  | .wildcard => .wildcard

theorem lookup_encoding (encode : Value → Encoded) (name : Nat) (env : Env Value) :
    lookup name (environment encode env) = (lookup name env).map encode := by
  induction env with
  | nil => rfl
  | cons entry rest ih =>
      simp only [environment, List.map_cons, lookup]
      split <;> simp_all [environment]

/-- Both acceptance and the complete resulting substitution commute with a
faithful encoding, including false-like values, repeated names and literals. -/
theorem bind_encoding [DecidableEq Value] [DecidableEq Encoded]
    (encode : Value → Encoded) (faithful : Function.Injective encode)
    (terms : List (Term Value)) (row : List Value) (env : Env Value) :
    AtomicBinding.bind (terms.map (term encode)) (row.map encode) (environment encode env) =
      (AtomicBinding.bind terms row env).map (environment encode) := by
  induction terms generalizing row env with
  | nil => cases row <;> rfl
  | cons first rest ih =>
      cases row with
      | nil => cases first <;> rfl
      | cons value tail =>
          cases first with
          | wildcard => exact ih tail env
          | literal expected =>
              by_cases same : expected = value
              · simp [AtomicBinding.bind, term, same, ih]
              · have different : encode expected ≠ encode value := fun h => same (faithful h)
                simp [AtomicBinding.bind, term, same, different]
          | «variable» name =>
              simp only [List.map_cons, term, AtomicBinding.bind, lookup_encoding]
              cases found : lookup name env with
              | none => simpa [found, environment] using ih tail ((name, value) :: env)
              | some previous =>
                  by_cases same : previous = value
                  · simp [same, ih]
                  · have different : encode previous ≠ encode value := fun h => same (faithful h)
                    simp [same, different]

theorem write_encoding (encode : Value → Encoded) (frame : Frame Value)
    (index : Nat) (value : Value) :
    write (fun key => encode (frame key)) index (encode value) =
      fun key => encode (write frame index value key) := by
  funext key
  by_cases same : key = index <;> simp [write, same]

/-- Failed candidates retain exactly the encoded partial fresh writes. No
rollback or clean-frame premise is needed, so this law composes across reuse. -/
theorem run_encoding [DecidableEq Value] [DecidableEq Encoded]
    (encode : Value → Encoded) (faithful : Function.Injective encode)
    (actions : List (Action Value)) (row : List Value) (frame : Frame Value) :
    run (actions.map (action encode)) (row.map encode) (fun key => encode (frame key)) =
      ((run actions row frame).1, fun key => encode ((run actions row frame).2 key)) := by
  induction actions generalizing row frame with
  | nil => rfl
  | cons first rest ih =>
      cases row with
      | nil => rfl
      | cons value tail =>
          cases first with
          | wildcard => exact ih tail frame
          | fresh index => simpa [action, run, write_encoding] using ih tail (write frame index value)
          | bound index =>
              by_cases same : frame index = value
              · simpa [action, run, same] using ih tail frame
              · have different : encode (frame index) ≠ encode value := fun h => same (faithful h)
                simp [action, run, same, different]
          | literal expected =>
              by_cases same : expected = value
              · simpa [action, run, same] using ih tail frame
              · have different : encode expected ≠ encode value := fun h => same (faithful h)
                simp [action, run, same, different]

/-- First-occurrence slot allocation depends only on identity, never value
encoding; every fresh/bound address and the resulting name roster is retained. -/
theorem lower_encoding (encode : Value → Encoded) (input : Term Value) (names : List Nat) :
    lower (term encode input) names =
      (action encode (lower input names).1, (lower input names).2) := by
  cases input with
  | literal value => rfl
  | wildcard => rfl
  | «variable» name => cases found : slot name names <;> simp [term, lower, found, action]

theorem compile_encoding (encode : Value → Encoded) (terms : List (Term Value)) (names : List Nat) :
    compile (terms.map (term encode)) names =
      ((compile terms names).1.map (action encode), (compile terms names).2) := by
  induction terms generalizing names with
  | nil => rfl
  | cons first rest ih => simp [compile, lower_encoding, ih]

/-- Ordered head/key observations preserve absence separately from any encoded
value. This law does not need injectivity because it performs no comparison. -/
theorem observations_encoding (encode : Value → Encoded) (terms : List (Term Value))
    (names : List Nat) (frame : Frame Value) :
    observeSlots (terms.map (term encode)) names (fun key => encode (frame key)) =
      (observeSlots terms names frame).map (Option.map encode) := by
  simp only [observeSlots, List.map_map]
  apply List.map_congr_left
  intro input _
  cases input with
  | literal value => rfl
  | wildcard => rfl
  | «variable» name => simp [term, Function.comp_def, Option.map_map]

/-- The actual first-occurrence compilation and execution compose with the
representation law, rather than requiring callers to supply encoded actions. -/
theorem compiled_run_encoding [DecidableEq Value] [DecidableEq Encoded]
    (encode : Value → Encoded) (faithful : Function.Injective encode)
    (terms : List (Term Value)) (names : List Nat) (row : List Value) (frame : Frame Value) :
    run (compile (terms.map (term encode)) names).1 (row.map encode)
        (fun key => encode (frame key)) =
      ((run (compile terms names).1 row frame).1,
        fun key => encode ((run (compile terms names).1 row frame).2 key)) := by
  rw [compile_encoding]
  exact run_encoding encode faithful _ row frame

theorem wanted_encoding (encode : Value → Encoded) (input : Term Value) (env : Env Value) :
    wanted (environment encode env) (term encode input) = (wanted env input).map encode := by
  cases input <;> simp [wanted, term, lookup_encoding]

/-- Known-column lookup retains order and multiplicity. Missing names and
wildcards contribute no key field, whereas a bound false-like value does. -/
theorem key_encoding (encode : Value → Encoded) (terms : List (Term Value)) (env : Env Value) :
    termKey (environment encode env) (terms.map (term encode)) =
      (termKey env terms).map encode := by
  induction terms with
  | nil => rfl
  | cons first rest ih =>
      simp only [termKey, List.map_cons, List.filterMap_cons, wanted_encoding]
      cases found : wanted env first <;> simp [termKey] at ih ⊢ <;> exact ih

end Ascent.ScalarEncoding
