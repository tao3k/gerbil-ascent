-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import CompiledCertificate

/-! Streaming translation validation, including the symbol-table state.
The lookup/update interface is the finite-map primitive boundary. In particular,
the checker does not assume that the compiler's own symbol table is correct.
Failure has no admitted post-state; successful prefixes preserve the complete
first-occurrence map, not merely its size. -/
namespace Ascent.DescriptorStream
open AtomicBinding PositiveSlots
variable {Value : Type} [DecidableEq Value]

structure Symbols where
  find : Nat → Option Nat
  count : Nat

theorem symbols_ext {a b : Symbols} (find : a.find = b.find) (count : a.count = b.count) : a = b := by
  cases a; cases b; cases find; cases count; rfl

def canonical (names : List Nat) : Symbols := ⟨fun name => slot name names, names.length⟩

def insert (symbols : Symbols) (name : Nat) : Symbols :=
  ⟨fun wanted => if wanted = name then some symbols.count else symbols.find wanted,
    symbols.count + 1⟩

theorem insert_canonical (names : List Nat) (name : Nat)
    (fresh : slot name names = none) :
    insert (canonical names) name = canonical (names ++ [name]) := by
  apply symbols_ext
  · funext wanted
    simp only [insert, canonical, slot_append]
    by_cases same : wanted = name
    · subst wanted; simp [fresh]
    · cases found : slot wanted names with
      | none => simp [same]
      | some index => simp [same]
  · simp [insert, canonical]

def lowerMap (term : Term Value) (symbols : Symbols) : Action Value × Symbols :=
  match term with
  | .literal value => (.literal value, symbols)
  | .wildcard => (.wildcard, symbols)
  | .variable name => match symbols.find name with
    | some index => (.bound index, symbols)
    | none => (.fresh symbols.count, insert symbols name)

omit [DecidableEq Value] in
theorem lower_map_refines (term : Term Value) (names : List Nat) :
    lowerMap term (canonical names) =
      ((lower term names).1, canonical (lower term names).2) := by
  cases term with
  | literal => rfl
  | wildcard => rfl
  | «variable» name =>
    cases found : slot name names with
    | none =>
      simp only [lowerMap, lower, canonical, found]
      exact congrArg (fun next => ((Action.fresh names.length : Action Value), next))
        (insert_canonical names name found)
    | some index => simp [lowerMap, lower, canonical, found]

def checkOne (term : Term Value) (actual : Action Value) (symbols : Symbols) : Option Symbols :=
  let next := lowerMap term symbols
  if actual = next.1 then some next.2 else none

def check : List (Term Value) → List (Action Value) → Symbols → Option Symbols
  | [], [], symbols => some symbols
  | term :: terms, actual :: actions, symbols =>
      (checkOne term actual symbols).bind (fun next => check terms actions next)
  | _, _, _ => none

/-- Exact equality for arbitrary term/action streams, including every failed
prefix and malformed length. No enumeration of term values or program sizes. -/
theorem stream_exact (terms : List (Term Value)) (actions : List (Action Value))
    (names : List Nat) :
    check terms actions (canonical names) =
      if actions = (compile terms names).1 then some (canonical (compile terms names).2) else none := by
  induction terms generalizing actions names with
  | nil => cases actions <;> simp [check, compile]
  | cons term terms ih =>
    cases actions with
    | nil => simp [check, compile]
    | cons actual actions =>
      simp only [check, checkOne, lower_map_refines]
      by_cases same : actual = (lower term names).1
      · simp [same, ih, compile]
      · simp [same, compile]

theorem stream_accepts_iff (terms : List (Term Value)) (actions : List (Action Value))
    (names : List Nat) :
    (check terms actions (canonical names)).isSome = true ↔
      actions = (compile terms names).1 := by
  rw [stream_exact]
  split <;> simp_all

/-- Scheme descriptor decoding must distinguish a missing slot from slot zero.
It must also preserve fresh/bound tags rather than erase their distinction. -/
inductive EncodedAction (Value : Type) where
  | fresh (slot : Nat)
  | bound (slot : Nat)
  | literal (value : Value)
  | wildcard
  | invalid
  deriving DecidableEq

def decode : EncodedAction Value → Option (Action Value)
  | .fresh index => some (.fresh index)
  | .bound index => some (.bound index)
  | .literal value => some (.literal value)
  | .wildcard => some .wildcard
  | .invalid => none

def encode : Action Value → EncodedAction Value
  | .fresh index => .fresh index
  | .bound index => .bound index
  | .literal value => .literal value
  | .wildcard => .wildcard

omit [DecidableEq Value] in
theorem decode_encode (action : Action Value) : decode (encode action) = some action := by
  cases action <;> rfl

def decodeAll : List (EncodedAction Value) → Option (List (Action Value))
  | [] => some []
  | action :: rest => (decode action).bind (fun decoded => (decodeAll rest).map (decoded :: ·))

def checkEncoded : List (Term Value) → List (EncodedAction Value) → Symbols → Option Symbols
  | [], [], symbols => some symbols
  | term :: terms, encoded :: rest, symbols =>
      (decode encoded).bind (fun action =>
        (checkOne term action symbols).bind (fun next => checkEncoded terms rest next))
  | _, _, _ => none

theorem fused_decode_exact (terms : List (Term Value)) (actions : List (EncodedAction Value))
    (symbols : Symbols) :
    checkEncoded terms actions symbols = (decodeAll actions).bind (fun decoded => check terms decoded symbols) := by
  induction actions generalizing terms symbols with
  | nil => cases terms <;> rfl
  | cons encoded rest ih =>
    cases decoded : decode encoded with
    | none => cases terms <;> simp [checkEncoded, decodeAll, decoded]
    | some action =>
      cases terms with
      | nil =>
        cases tail : decodeAll rest <;> simp [checkEncoded, decodeAll, decoded, tail, check]
      | cons term terms =>
        simp only [checkEncoded, decodeAll, decoded]
        change (checkOne term action symbols).bind (fun next => checkEncoded terms rest next) =
          ((decodeAll rest).map (List.cons action)).bind (fun decoded => check (term :: terms) decoded symbols)
        cases step : checkOne term action symbols with
        | none => cases decodeAll rest <;> simp [step, check]
        | some next =>
          change checkEncoded terms rest next = _
          rw [ih]
          cases decodeAll rest <;> simp [step, check]

theorem encoded_accepts_iff (terms : List (Term Value)) (actions : List (EncodedAction Value))
    (names : List Nat) :
    (checkEncoded terms actions (canonical names)).isSome = true ↔
      decodeAll actions = some (compile terms names).1 := by
  rw [fused_decode_exact]
  cases decoded : decodeAll actions with
  | none => simp
  | some actual => simp [stream_accepts_iff, Option.some.injEq]

end Ascent.DescriptorStream
