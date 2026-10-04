/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Typed lexical lowering to positive relational IR. This formal kernel models
source/parameter/function/apply and the five positive primitive branches in
program/higher-order.ss. It is not an extraction of that Scheme implementation.
Relation fixed-point feedback, admission, tuple encoding and budgets are separate.
-/
import Std

namespace Ascent.Lowering

universe u

inductive Signature where
  | relation (row : Type)
  | arrow (input output : Signature)

def Meaning : Signature → Type
  | .relation row => row → Prop
  | .arrow input output => Meaning input → Meaning output

inductive Variable : List Signature → Signature → Type 1 where
  | here : Variable (t :: context) t
  | there : Variable context t → Variable (other :: context) t

def Environment (value : Signature → Type u) : List Signature → Type u
  | [] => PUnit
  | t :: context => value t × Environment value context

def lookup {value : Signature → Type u} :
    Variable context t → Environment value context → value t
  | .here, env => env.1
  | .there index, env => lookup index env.2

inductive Expression : List Signature → Signature → Type 1 where
  | source {row : Type} (rows : row → Prop) : Expression context (.relation row)
  | parameter : Variable context t → Expression context t
  | function : Expression (input :: context) output → Expression context (.arrow input output)
  | apply : Expression context (.arrow input output) → Expression context input → Expression context output
  | union {row : Type} : Expression context (.relation row) → Expression context (.relation row) → Expression context (.relation row)
  | join {left right : Type} (keys : left → right → Prop) :
      Expression context (.relation left) → Expression context (.relation right) → Expression context (.relation (left × right))
  | project {input output : Type} (columns : input → output) :
      Expression context (.relation input) → Expression context (.relation output)
  | select {row : Type} (predicate : row → Prop) :
      Expression context (.relation row) → Expression context (.relation row)
  | flatmap {input output : Type} (table : input → output → Prop) :
      Expression context (.relation input) → Expression context (.relation output)

/- The target contains no lexical lambda/application nodes. Predicate functions
   here denote frozen source/table membership and selected columns; they are not
   an admission mechanism for runtime Scheme callbacks. -/
inductive RelationalIR : Type → Type 1 where
  | source {row : Type} (rows : row → Prop) : RelationalIR row
  | union : RelationalIR row → RelationalIR row → RelationalIR row
  | join {left right : Type} (keys : left → right → Prop) :
      RelationalIR left → RelationalIR right → RelationalIR (left × right)
  | project {input output : Type} (columns : input → output) : RelationalIR input → RelationalIR output
  | select {row : Type} (predicate : row → Prop) : RelationalIR row → RelationalIR row
  | flatmap {input output : Type} (table : input → output → Prop) : RelationalIR input → RelationalIR output

def interpret : RelationalIR row → row → Prop
  | .source rows => rows
  | .union left right => fun row => interpret left row ∨ interpret right row
  | .join keys left right => fun row => interpret left row.1 ∧ interpret right row.2 ∧ keys row.1 row.2
  | .project columns input => fun row => ∃ original, interpret input original ∧ columns original = row
  | .select predicate input => fun row => interpret input row ∧ predicate row
  | .flatmap table input => fun row => ∃ original, interpret input original ∧ table original row

def Compiled : Signature → Type 1
  | .relation row => RelationalIR row
  | .arrow input output => Compiled input → Compiled output

def denote : Expression context t → Environment Meaning context → Meaning t
  | .source rows, _ => rows
  | .parameter index, env => lookup index env
  | .function body, env => fun argument => denote body (argument, env)
  | .apply function argument, env => denote function env (denote argument env)
  | .union left right, env => fun row => denote left env row ∨ denote right env row
  | .join keys left right, env => fun row => denote left env row.1 ∧ denote right env row.2 ∧ keys row.1 row.2
  | .project columns input, env => fun row => ∃ original, denote input env original ∧ columns original = row
  | .select predicate input, env => fun row => denote input env row ∧ predicate row
  | .flatmap table input, env => fun row => ∃ original, denote input env original ∧ table original row

/- Arrow values in this mathematical model stand for reified compiler closures.
   They capture the defining environment, not the caller's current environment. -/
def lower : Expression context t → Environment Compiled context → Compiled t
  | .source rows, _ => .source rows
  | .parameter index, env => lookup index env
  | .function body, env => fun argument => lower body (argument, env)
  | .apply function argument, env => lower function env (lower argument env)
  | .union left right, env => .union (lower left env) (lower right env)
  | .join keys left right, env => .join keys (lower left env) (lower right env)
  | .project columns input, env => .project columns (lower input env)
  | .select predicate input, env => .select predicate (lower input env)
  | .flatmap table input, env => .flatmap table (lower input env)

/- A logical relation admits higher-order inputs and returned closures rather
   than comparing function identities or testing only observed arguments. -/
def Realizes : (t : Signature) → Compiled t → Meaning t → Prop
  | .relation _, compiled, meaning => interpret compiled = meaning
  | .arrow input output, compiled, meaning =>
      ∀ argument value, Realizes input argument value → Realizes output (compiled argument) (meaning value)

def EnvironmentsRelated : (context : List Signature) →
    Environment Compiled context → Environment Meaning context → Prop
  | [], _, _ => True
  | t :: context, compiled, meaning => Realizes t compiled.1 meaning.1 ∧ EnvironmentsRelated context compiled.2 meaning.2

theorem lookup_realizes (index : Variable context t)
    (compiled : Environment Compiled context) (meaning : Environment Meaning context)
    (related : EnvironmentsRelated context compiled meaning) :
    Realizes t (lookup index compiled) (lookup index meaning) := by
  induction index with
  | here => exact related.1
  | there index ih => exact ih compiled.2 meaning.2 related.2

theorem lowering_preserves_meaning (expression : Expression context t)
    (compiled : Environment Compiled context) (meaning : Environment Meaning context)
    (related : EnvironmentsRelated context compiled meaning) :
    Realizes t (lower expression compiled) (denote expression meaning) := by
  induction expression with
  | source rows => rfl
  | parameter index => exact lookup_realizes index compiled meaning related
  | function body ih =>
    intro argument value argumentRelated
    exact ih (argument, compiled) (value, meaning) ⟨argumentRelated, related⟩
  | apply function argument functionIH argumentIH =>
    exact functionIH compiled meaning related
      (lower argument compiled) (denote argument meaning) (argumentIH compiled meaning related)
  | union left right leftIH rightIH =>
    change (fun row => interpret (lower left compiled) row ∨ interpret (lower right compiled) row) = _
    rw [leftIH compiled meaning related, rightIH compiled meaning related]
    rfl
  | join keys left right leftIH rightIH =>
    change interpret (RelationalIR.join keys (lower left compiled) (lower right compiled)) = _
    simp only [interpret]
    rw [leftIH compiled meaning related, rightIH compiled meaning related]
    rfl
  | project columns input ih =>
    change (fun row => ∃ original, interpret (lower input compiled) original ∧ columns original = row) = _
    rw [ih compiled meaning related]
    rfl
  | select predicate input ih =>
    change (fun row => interpret (lower input compiled) row ∧ predicate row) = _
    rw [ih compiled meaning related]
    rfl
  | flatmap table input ih =>
    change (fun row => ∃ original, interpret (lower input compiled) original ∧ table original row) = _
    rw [ih compiled meaning related]
    rfl

theorem closed_relation_lowering (expression : Expression [] (.relation row)) :
    interpret (lower expression PUnit.unit) = denote expression PUnit.unit :=
  lowering_preserves_meaning expression PUnit.unit PUnit.unit trivial

def compiledBottom : (t : Signature) → Compiled t
  | .relation _ => .source (fun _ => False)
  | .arrow _ output => fun _ => compiledBottom output

def semanticBottom : (t : Signature) → Meaning t
  | .relation _ => fun _ => False
  | .arrow _ output => fun _ => semanticBottom output

theorem bottom_realizes (t : Signature) : Realizes t (compiledBottom t) (semanticBottom t) := by
  induction t with
  | relation row => rfl
  | arrow input output _ ih => exact fun _ _ _ => ih

def unroll {α : Type u} (step : α → α) (initial : α) : Nat → α
  | 0 => initial
  | n + 1 => step (unroll step initial n)

/-- Full finite unrolling preserves meaning at every argument, including
    function arguments. Height sufficiency and admission are separate premises. -/
theorem unrolling_preserves_meaning (t : Signature)
    (compiled : Compiled (.arrow t t)) (meaning : Meaning (.arrow t t))
    (related : Realizes (.arrow t t) compiled meaning) (count : Nat) :
    Realizes t (unroll compiled (compiledBottom t) count)
      (unroll meaning (semanticBottom t) count) := by
  induction count with
  | zero => exact bottom_realizes t
  | succ n ih => exact related _ _ ih

/- Logical monotonicity restricts higher-order arguments through their own
   relation; arbitrary nonmonotone host functions do not receive this law. -/
def MonotoneRelated : (t : Signature) → Meaning t → Meaning t → Prop
  | .relation _, left, right => ∀ row, left row → right row
  | .arrow input output, left, right =>
      ∀ a b, MonotoneRelated input a b → MonotoneRelated output (left a) (right b)

def MonotoneEnvironments : (context : List Signature) →
    Environment Meaning context → Environment Meaning context → Prop
  | [], _, _ => True
  | t :: context, left, right => MonotoneRelated t left.1 right.1 ∧ MonotoneEnvironments context left.2 right.2

theorem lookup_monotone (index : Variable context t)
    (left right : Environment Meaning context)
    (related : MonotoneEnvironments context left right) :
    MonotoneRelated t (lookup index left) (lookup index right) := by
  induction index with
  | here => exact related.1
  | there index ih => exact ih left.2 right.2 related.2

theorem denotation_monotone (expression : Expression context t)
    (left right : Environment Meaning context)
    (related : MonotoneEnvironments context left right) :
    MonotoneRelated t (denote expression left) (denote expression right) := by
  induction expression with
  | source rows => exact fun _ h => h
  | parameter index => exact lookup_monotone index left right related
  | function body ih =>
    intro a b arguments
    exact ih (a, left) (b, right) ⟨arguments, related⟩
  | apply function argument functionIH argumentIH =>
    exact functionIH left right related _ _ (argumentIH left right related)
  | union a b aIH bIH =>
    intro row h
    rcases h with h | h
    · exact Or.inl (aIH left right related row h)
    · exact Or.inr (bIH left right related row h)
  | join keys a b aIH bIH =>
    intro row h
    exact ⟨aIH left right related row.1 h.1, bIH left right related row.2 h.2.1, h.2.2⟩
  | project columns input ih =>
    intro row h
    obtain ⟨original, present, projected⟩ := h
    exact ⟨original, ih left right related original present, projected⟩
  | select predicate input ih =>
    intro row h
    exact ⟨ih left right related row h.1, h.2⟩
  | flatmap table input ih =>
    intro row h
    obtain ⟨original, present, mapped⟩ := h
    exact ⟨original, ih left right related original present, mapped⟩

theorem closed_function_monotone
    (expression : Expression [] (.arrow (.relation input) (.relation output)))
    (left right : input → Prop) (included : ∀ row, left row → right row) :
    ∀ row, denote expression PUnit.unit left row → denote expression PUnit.unit right row :=
  denotation_monotone expression PUnit.unit PUnit.unit trivial left right included

/- Concrete finite tuple layout for join concatenation and projection. Scalar
   encoding into Fin atoms, descriptor validation and native list construction
   remain implementation obligations; these laws quantify over every tuple. -/
abbrev Tuple (width atoms : Nat) := Fin width → Fin atoms

def concatenate {m n atoms : Nat} (left : Tuple m atoms) (right : Tuple n atoms) : Tuple (m + n) atoms :=
  Fin.addCases left right

def leftPart {m n atoms : Nat} (row : Tuple (m + n) atoms) : Tuple m atoms :=
  fun column => row (Fin.castAdd n column)

def rightPart {m n atoms : Nat} (row : Tuple (m + n) atoms) : Tuple n atoms :=
  fun column => row (Fin.natAdd m column)

theorem concatenate_left {m n atoms : Nat} (left : Tuple m atoms) (right : Tuple n atoms) :
    leftPart (concatenate left right) = left := by
  funext column
  simpa only [leftPart, concatenate] using
    (Fin.addCases_left (motive := fun _ : Fin (m + n) => Fin atoms) (left := left) (right := right) column)

theorem concatenate_right {m n atoms : Nat} (left : Tuple m atoms) (right : Tuple n atoms) :
    rightPart (concatenate left right) = right := by
  funext column
  simpa only [rightPart, concatenate] using
    (Fin.addCases_right (motive := fun _ : Fin (m + n) => Fin atoms) (left := left) (right := right) column)

theorem concatenate_parts {m n atoms : Nat} (row : Tuple (m + n) atoms) :
    concatenate (leftPart row) (rightPart row) = row := by
  funext column
  apply Fin.addCases (m := m) (n := n) (motive := fun i => concatenate (leftPart row) (rightPart row) i = row i)
  · intro i
    exact Fin.addCases_left i
  · intro i
    exact Fin.addCases_right i

/-- Pair-valued formal join and concatenated finite native rows have the same
    membership after encoding. No sample-based tuple comparison is involved. -/
theorem join_tuple_encoding {m n atoms : Nat}
    (left : RelationalIR (Tuple m atoms)) (right : RelationalIR (Tuple n atoms))
    (leftKey : Fin m) (rightKey : Fin n) (row : Tuple (m + n) atoms) :
    interpret (RelationalIR.project (fun pair => concatenate pair.1 pair.2)
      (RelationalIR.join (fun a b => a leftKey = b rightKey) left right)) row ↔
    interpret left (leftPart row) ∧ interpret right (rightPart row) ∧
      leftPart row leftKey = rightPart row rightKey := by
  constructor
  · intro h
    obtain ⟨⟨a, b⟩, ⟨ha, hb, keys⟩, encoded⟩ := h
    change concatenate a b = row at encoded
    subst row
    simpa only [concatenate_left, concatenate_right] using And.intro ha (And.intro hb keys)
  · intro h
    exact ⟨(leftPart row, rightPart row), h, concatenate_parts row⟩

end Ascent.Lowering
