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

/-- The native typed compiler materializes a bare source root with all columns
    in order. The concrete index/list correspondence is in RowRepresentation;
    this theorem establishes the relational IR law, including nullary rows. -/
theorem identity_projection_preserves_meaning (input : RelationalIR row) :
    interpret (.project id input) = interpret input := by
  funext result
  apply propext
  simp [interpret]

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

/-- Match higher-order.ss's source-root branch, leaving computed roots intact. -/
def materializeSourceRoot (input : RelationalIR row) : RelationalIR row :=
  match input with
  | .source rows => .project id (.source rows)
  | other => other

theorem source_root_materialization_preserves_meaning (input : RelationalIR row) :
    interpret (materializeSourceRoot input) = interpret input := by
  cases input <;> simp only [materializeSourceRoot]
  exact identity_projection_preserves_meaning _

theorem closed_materialized_relation_lowering
    (expression : Expression [] (.relation row)) :
    interpret (materializeSourceRoot (lower expression PUnit.unit)) =
      denote expression PUnit.unit := by
  exact (source_root_materialization_preserves_meaning
    (lower expression PUnit.unit)).trans (closed_relation_lowering expression)

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

/- Exact frontier extraction depends contravariantly on the base. This
separates the external set-difference boundary from a positive typed arrow;
S20 valid insertion changes may overlap the base and are not exact frontiers. -/
def exactInsertedFrontier (before added : row → Prop) : row → Prop :=
  fun value => added value ∧ ¬before value

theorem exact_frontier_not_positive_arrow
    (expression : Expression [] (.arrow (.relation Nat) (.relation Nat))) :
    ¬(∀ base row, denote expression PUnit.unit base row ↔
      exactInsertedFrontier base (fun n => n = 0) row) := by
  intro represents
  have empty : denote expression PUnit.unit (fun _ => False) 0 :=
    (represents _ 0).mpr ⟨rfl, id⟩
  have grown := closed_function_monotone expression (fun _ => False)
    (fun n => n = 0) (fun _ impossible => False.elim impossible) 0 empty
  exact ((represents _ 0).mp grown).2 rfl

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

namespace ProjectionRule

/-- Finite variable identities model the distinct variables emitted by
    fresh-variables. Decoding Gerbil symbols to these identities is separate. -/
def bindRow {α : Type} {arity : Nat} (row : List α) (length : row.length = arity) :
    Fin arity → α := fun column => row.get ⟨column.val, by omega⟩

def evaluatePattern {α : Type} {arity : Nat}
    (variables : List (Fin arity)) (assignment : Fin arity → α) : List α :=
  variables.map assignment

def bodyVariables (arity : Nat) : List (Fin arity) := List.finRange arity

theorem complete_body_length {α : Type} {arity : Nat} (assignment : Fin arity → α) :
    (evaluatePattern (bodyVariables arity) assignment).length = arity := by
  simp [evaluatePattern, bodyVariables]

theorem complete_body_lookup {α : Type} {arity : Nat}
    (assignment : Fin arity → α) (column : Fin arity) :
    (evaluatePattern (bodyVariables arity) assignment).get
      ⟨column.val, by simp [evaluatePattern, bodyVariables]⟩ = assignment column := by
  simp [evaluatePattern, bodyVariables, List.get_eq_getElem]

theorem bind_complete_row {α : Type} {arity : Nat}
    (row : List α) (length : row.length = arity) :
    evaluatePattern (bodyVariables arity) (bindRow row length) = row := by
  apply List.ext_getElem
  · simp [evaluatePattern, bodyVariables, length]
  · intro i h₁ h₂
    simp [evaluatePattern, bodyVariables, bindRow, List.get_eq_getElem]

/-- Exactly one positive body atom, with an arbitrary checked head pattern.
    This is the variable-only projection branch of lower-operator-graph. -/
def emitted (rows : List (List α)) (columns : List (Fin arity)) (output : List α) : Prop :=
  ∃ assignment : Fin arity → α,
    evaluatePattern (bodyVariables arity) assignment ∈ rows ∧
    evaluatePattern columns assignment = output

def descriptor (rows : List (List α)) (columns : List (Fin arity)) (output : List α) : Prop :=
  ∃ row, ∃ length : row.length = arity,
    row ∈ rows ∧ evaluatePattern columns (bindRow row length) = output

theorem emitted_projection_sound {α : Type} {arity : Nat}
    (rows : List (List α)) (columns : List (Fin arity)) (output : List α) :
    emitted rows columns output → descriptor rows columns output := by
  rintro ⟨assignment, member, result⟩
  refine ⟨evaluatePattern (bodyVariables arity) assignment,
    complete_body_length assignment, member, ?_⟩
  have same : bindRow (evaluatePattern (bodyVariables arity) assignment)
      (complete_body_length assignment) = assignment := by
    funext column
    exact complete_body_lookup assignment column
  rw [same]
  exact result

theorem emitted_projection_complete {α : Type} {arity : Nat}
    (rows : List (List α)) (columns : List (Fin arity)) (output : List α) :
    descriptor rows columns output → emitted rows columns output := by
  rintro ⟨row, length, member, result⟩
  refine ⟨bindRow row length, ?_, result⟩
  rw [bind_complete_row]
  exact member

theorem emitted_projection_iff_descriptor {α : Type} {arity : Nat}
    (rows : List (List α)) (columns : List (Fin arity)) (output : List α) :
    emitted rows columns output ↔ descriptor rows columns output :=
  ⟨emitted_projection_sound rows columns output,
   emitted_projection_complete rows columns output⟩

end ProjectionRule

namespace ProjectedJoinRule

/-- Left variables and fresh non-key right variables inhabit disjoint banks.
    The right key reuses exactly the left key's variable, as join-variables
    does. Native gensym/symbol decoding remains a separate premise. -/
def rightVariable (leftKey : Fin m) (rightKey : Fin n) (column : Fin n) :
    Sum (Fin m) (Fin n) :=
  if column = rightKey then .inl leftKey else .inr column

def leftBody (assignment : Sum (Fin m) (Fin n) → α) : Fin m → α :=
  fun column => assignment (.inl column)

def rightBody (leftKey : Fin m) (rightKey : Fin n)
    (assignment : Sum (Fin m) (Fin n) → α) : Fin n → α :=
  fun column => assignment (rightVariable leftKey rightKey column)

def headVariables (leftKey : Fin m) (rightKey : Fin n) :
    Fin (m + n) → Sum (Fin m) (Fin n) :=
  Fin.addCases Sum.inl (rightVariable leftKey rightKey)

def headValues (leftKey : Fin m) (rightKey : Fin n)
    (columns : List (Fin (m + n))) (assignment : Sum (Fin m) (Fin n) → α) : List α :=
  columns.map fun column => assignment (headVariables leftKey rightKey column)

theorem right_key_aliases_left (leftKey : Fin m) (rightKey : Fin n) :
    rightVariable leftKey rightKey rightKey = .inl leftKey := by
  simp [rightVariable]

theorem body_keys_equal (leftKey : Fin m) (rightKey : Fin n)
    (assignment : Sum (Fin m) (Fin n) → α) :
    leftBody assignment leftKey = rightBody leftKey rightKey assignment rightKey := by
  simp [leftBody, rightBody, right_key_aliases_left]

theorem matching_right_body_reconstruction (leftKey : Fin m) (rightKey : Fin n)
    (left : Fin m → α) (right : Fin n → α) (keys : left leftKey = right rightKey) :
    rightBody leftKey rightKey (Sum.elim left right) = right := by
  funext column
  by_cases same : column = rightKey
  · subst column
    simpa [rightBody, rightVariable] using keys
  · simp [rightBody, rightVariable, same]

theorem head_values_are_projected_body (leftKey : Fin m) (rightKey : Fin n)
    (columns : List (Fin (m + n))) (assignment : Sum (Fin m) (Fin n) → α) :
    headValues leftKey rightKey columns assignment =
      columns.map (Fin.addCases (leftBody assignment) (rightBody leftKey rightKey assignment)) := by
  have same : (fun column => assignment (headVariables leftKey rightKey column)) =
      Fin.addCases (leftBody assignment) (rightBody leftKey rightKey assignment) := by
    funext column
    apply Fin.addCases (m := m) (n := n) (motive := fun i =>
      assignment (headVariables leftKey rightKey i) =
        Fin.addCases (leftBody assignment) (rightBody leftKey rightKey assignment) i)
    · intro i
      simp [headVariables, leftBody]
    · intro i
      simp [headVariables, rightBody]
  exact congrArg (List.map · columns) same

def emitted (leftInput : (Fin m → α) → Prop) (rightInput : (Fin n → α) → Prop)
    (leftKey : Fin m) (rightKey : Fin n) (columns : List (Fin (m + n))) (output : List α) : Prop :=
  ∃ assignment, leftInput (leftBody assignment) ∧
    rightInput (rightBody leftKey rightKey assignment) ∧
    headValues leftKey rightKey columns assignment = output

def descriptor (leftInput : (Fin m → α) → Prop) (rightInput : (Fin n → α) → Prop)
    (leftKey : Fin m) (rightKey : Fin n) (columns : List (Fin (m + n))) (output : List α) : Prop :=
  ∃ left right, leftInput left ∧ rightInput right ∧ left leftKey = right rightKey ∧
    columns.map (Fin.addCases left right) = output

theorem emitted_projected_join_sound
    (leftInput : (Fin m → α) → Prop) (rightInput : (Fin n → α) → Prop)
    (leftKey : Fin m) (rightKey : Fin n) (columns : List (Fin (m + n))) (output : List α) :
    emitted leftInput rightInput leftKey rightKey columns output →
      descriptor leftInput rightInput leftKey rightKey columns output := by
  rintro ⟨assignment, leftMem, rightMem, result⟩
  refine ⟨leftBody assignment, rightBody leftKey rightKey assignment,
    leftMem, rightMem, body_keys_equal leftKey rightKey assignment, ?_⟩
  rw [← head_values_are_projected_body]
  exact result

theorem emitted_projected_join_complete
    (leftInput : (Fin m → α) → Prop) (rightInput : (Fin n → α) → Prop)
    (leftKey : Fin m) (rightKey : Fin n) (columns : List (Fin (m + n))) (output : List α) :
    descriptor leftInput rightInput leftKey rightKey columns output →
      emitted leftInput rightInput leftKey rightKey columns output := by
  rintro ⟨left, right, leftMem, rightMem, keys, result⟩
  have reconstructed := matching_right_body_reconstruction leftKey rightKey left right keys
  refine ⟨Sum.elim left right, leftMem, ?_, ?_⟩
  · rw [reconstructed]
    exact rightMem
  · rw [head_values_are_projected_body, reconstructed]
    exact result

theorem emitted_projected_join_iff_descriptor
    (leftInput : (Fin m → α) → Prop) (rightInput : (Fin n → α) → Prop)
    (leftKey : Fin m) (rightKey : Fin n) (columns : List (Fin (m + n))) (output : List α) :
    emitted leftInput rightInput leftKey rightKey columns output ↔
      descriptor leftInput rightInput leftKey rightKey columns output :=
  ⟨emitted_projected_join_sound leftInput rightInput leftKey rightKey columns output,
   emitted_projected_join_complete leftInput rightInput leftKey rightKey columns output⟩

theorem descriptor_iff_join_project_ir
    (leftInput : (Fin m → α) → Prop) (rightInput : (Fin n → α) → Prop)
    (leftKey : Fin m) (rightKey : Fin n) (columns : List (Fin (m + n))) (output : List α) :
    descriptor leftInput rightInput leftKey rightKey columns output ↔
      interpret (RelationalIR.project (fun pair => columns.map (Fin.addCases pair.1 pair.2))
        (RelationalIR.join (fun left right => left leftKey = right rightKey)
          (.source leftInput) (.source rightInput))) output := by
  constructor
  · rintro ⟨left, right, leftMem, rightMem, keys, result⟩
    exact ⟨(left, right), ⟨leftMem, rightMem, keys⟩, result⟩
  · rintro ⟨⟨left, right⟩, ⟨leftMem, rightMem, keys⟩, result⟩
    exact ⟨left, right, leftMem, rightMem, keys, result⟩

end ProjectedJoinRule

end Ascent.Lowering
