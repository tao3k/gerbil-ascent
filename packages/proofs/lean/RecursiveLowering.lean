/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Scoped positive relation feedback after lexical function elimination. This
kernel is not extraction of Scheme rule emission or semi-naive execution.
-/
import Std
namespace Ascent.RecursiveLowering

def Included {row : Type} (a b : row → Prop) := ∀ x, a x → b x

def least {row : Type} (step : (row → Prop) → row → Prop) : row → Prop :=
  fun x => ∀ candidate, Included (step candidate) candidate → candidate x

def Monotone {row : Type} (step : (row → Prop) → row → Prop) :=
  ∀ a b, Included a b → Included (step a) (step b)

theorem least_below (step : (row → Prop) → row → Prop)
    (candidate : row → Prop) (closed : Included (step candidate) candidate) :
    Included (least step) candidate := fun _ h => h candidate closed

theorem least_prefixed (step : (row → Prop) → row → Prop) (mono : Monotone step) :
    Included (step (least step)) (least step) := by
  intro x hx candidate closed
  exact closed x (mono (least step) candidate (least_below step candidate closed) x hx)

theorem least_fixed (step : (row → Prop) → row → Prop) (mono : Monotone step) :
    step (least step) = least step := by
  have backward := least_prefixed step mono
  have forward := least_below step (step (least step))
    (mono (step (least step)) (least step) backward)
  funext x
  exact propext ⟨backward x, forward x⟩

theorem least_monotone (left right : (row → Prop) → row → Prop)
    (included : ∀ candidate, Included (left candidate) (right candidate)) :
    Included (least left) (least right) := by
  intro x hx candidate closed
  exact hx candidate (fun y hy => closed y (included candidate y hy))

inductive Variable : List Type → Type → Type 1 where
  | here : Variable (row :: context) row
  | there : Variable context row → Variable (other :: context) row

def Environment : List Type → Type
  | [] => PUnit
  | row :: context => (row → Prop) × Environment context

def lookup : Variable context row → Environment context → row → Prop
  | .here, env => env.1
  | .there index, env => lookup index env.2

inductive PositiveExpression : List Type → Type → Type 1 where
  | source (rows : row → Prop) : PositiveExpression context row
  | parameter : Variable context row → PositiveExpression context row
  | union : PositiveExpression context row → PositiveExpression context row → PositiveExpression context row
  | join (keys : left → right → Prop) : PositiveExpression context left → PositiveExpression context right → PositiveExpression context (left × right)
  | project (columns : input → output) : PositiveExpression context input → PositiveExpression context output
  | select (predicate : row → Prop) : PositiveExpression context row → PositiveExpression context row
  | flatmap (table : input → output → Prop) : PositiveExpression context input → PositiveExpression context output
  | feedback : PositiveExpression (row :: context) row → PositiveExpression context row

inductive ScopedIR : List Type → Type → Type 1 where
  | source (rows : row → Prop) : ScopedIR context row
  | parameter : Variable context row → ScopedIR context row
  | union : ScopedIR context row → ScopedIR context row → ScopedIR context row
  | join (keys : left → right → Prop) : ScopedIR context left → ScopedIR context right → ScopedIR context (left × right)
  | project (columns : input → output) : ScopedIR context input → ScopedIR context output
  | select (predicate : row → Prop) : ScopedIR context row → ScopedIR context row
  | flatmap (table : input → output → Prop) : ScopedIR context input → ScopedIR context output
  | feedback : ScopedIR (row :: context) row → ScopedIR context row

def denote : PositiveExpression context row → Environment context → row → Prop
  | .source rows, _ => rows
  | .parameter index, env => lookup index env
  | .union left right, env => fun x => denote left env x ∨ denote right env x
  | .join keys left right, env => fun x => denote left env x.1 ∧ denote right env x.2 ∧ keys x.1 x.2
  | .project columns input, env => fun x => ∃ original, denote input env original ∧ columns original = x
  | .select predicate input, env => fun x => denote input env x ∧ predicate x
  | .flatmap table input, env => fun x => ∃ original, denote input env original ∧ table original x
  | .feedback body, env => least (fun candidate => denote body (candidate, env))

def interpret : ScopedIR context row → Environment context → row → Prop
  | .source rows, _ => rows
  | .parameter index, env => lookup index env
  | .union left right, env => fun x => interpret left env x ∨ interpret right env x
  | .join keys left right, env => fun x => interpret left env x.1 ∧ interpret right env x.2 ∧ keys x.1 x.2
  | .project columns input, env => fun x => ∃ original, interpret input env original ∧ columns original = x
  | .select predicate input, env => fun x => interpret input env x ∧ predicate x
  | .flatmap table input, env => fun x => ∃ original, interpret input env original ∧ table original x
  | .feedback body, env => least (fun candidate => interpret body (candidate, env))

def lower : PositiveExpression context row → ScopedIR context row
  | .source rows => .source rows
  | .parameter index => .parameter index
  | .union a b => .union (lower a) (lower b)
  | .join keys a b => .join keys (lower a) (lower b)
  | .project columns input => .project columns (lower input)
  | .select predicate input => .select predicate (lower input)
  | .flatmap table input => .flatmap table (lower input)
  | .feedback body => .feedback (lower body)

theorem lowering_preserves_meaning (expression : PositiveExpression context row)
    (env : Environment context) : interpret (lower expression) env = denote expression env := by
  induction expression with
  | source rows => rfl
  | parameter index => rfl
  | union a b ia ib => simp only [lower, interpret, denote, ia env, ib env]
  | join keys a b ia ib => simp only [lower, interpret, denote, ia env, ib env]
  | project columns input ih => simp only [lower, interpret, denote, ih env]
  | select predicate input ih => simp only [lower, interpret, denote, ih env]
  | flatmap table input ih => simp only [lower, interpret, denote, ih env]
  | feedback body ih =>
    change least (fun candidate => interpret (lower body) (candidate, env)) = _
    have h : (fun candidate => interpret (lower body) (candidate, env)) =
        (fun candidate => denote body (candidate, env)) := funext (fun candidate => ih (candidate, env))
    rw [h]
    rfl

def EnvironmentsIncluded : (context : List Type) → Environment context → Environment context → Prop
  | [], _, _ => True
  | _ :: context, a, b => Included a.1 b.1 ∧ EnvironmentsIncluded context a.2 b.2

theorem lookup_monotone (index : Variable context row) (a b : Environment context)
    (related : EnvironmentsIncluded context a b) : Included (lookup index a) (lookup index b) := by
  induction index with
  | here => exact related.1
  | there index ih => exact ih a.2 b.2 related.2

theorem denotation_monotone (expression : PositiveExpression context row)
    (a b : Environment context) (related : EnvironmentsIncluded context a b) :
    Included (denote expression a) (denote expression b) := by
  induction expression with
  | source rows => exact fun _ h => h
  | parameter index => exact lookup_monotone index a b related
  | union left right il ir =>
    intro x h
    cases h with
    | inl h => exact Or.inl (il a b related x h)
    | inr h => exact Or.inr (ir a b related x h)
  | join keys left right il ir =>
    intro x h
    exact ⟨il a b related x.1 h.1, ir a b related x.2 h.2.1, h.2.2⟩
  | project columns input ih =>
    intro x h
    obtain ⟨original, member, mapped⟩ := h
    exact ⟨original, ih a b related original member, mapped⟩
  | select predicate input ih =>
    intro x h
    exact ⟨ih a b related x h.1, h.2⟩
  | flatmap table input ih =>
    intro x h
    obtain ⟨original, member, mapped⟩ := h
    exact ⟨original, ih a b related original member, mapped⟩
  | feedback body ih =>
    apply least_monotone
    intro candidate
    exact ih (candidate, a) (candidate, b) ⟨(fun _ h => h), related⟩

theorem environments_reflexive (context : List Type) (env : Environment context) :
    EnvironmentsIncluded context env env := by
  induction context with
  | nil => trivial
  | cons t context ih => exact ⟨(fun _ h => h), ih env.2⟩

theorem feedback_body_monotone (body : PositiveExpression (row :: context) row)
    (env : Environment context) : Monotone (fun candidate => denote body (candidate, env)) := by
  intro a b included
  apply denotation_monotone body (a, env) (b, env)
  exact ⟨included, environments_reflexive context env⟩

theorem feedback_is_fixed (body : PositiveExpression (row :: context) row) (env : Environment context) :
    denote body (denote (.feedback body) env, env) = denote (.feedback body) env :=
  least_fixed _ (feedback_body_monotone body env)

theorem lowered_feedback_is_least (body : PositiveExpression (row :: context) row)
    (env : Environment context) (candidate : row → Prop)
    (closed : Included (denote body (candidate, env)) candidate) :
    Included (interpret (lower (.feedback body)) env) candidate := by
  rw [lowering_preserves_meaning]
  exact least_below _ candidate closed

/-- The reference loop appends current rows to the body result. This does
    not change the least closure, even when the body is not inflationary. -/
theorem accumulating_least (step : (row → Prop) → row → Prop) :
    least (fun candidate x => candidate x ∨ step candidate x) = least step := by
  funext x
  apply propext
  constructor
  · intro h candidate closed
    exact h candidate (fun y hy => hy.elim id (closed y))
  · intro h candidate closed
    exact h candidate (fun y hy => closed y (Or.inr hy))

def iterate {row : Type} (step : (row → Prop) → row → Prop) : Nat → row → Prop
  | 0 => fun _ => False
  | n + 1 => fun x => iterate step n x ∨ step (iterate step n) x

theorem iteration_below_least (step : (row → Prop) → row → Prop)
    (mono : Monotone step) (count : Nat) : Included (iterate step count) (least step) := by
  induction count with
  | zero => exact fun _ h => False.elim h
  | succ n ih =>
    intro x h
    cases h with
    | inl old => exact ih x old
    | inr new => exact least_prefixed step mono x (mono _ _ ih x new)

/-- Completion means actual stationarity, not merely exhausting a bound. -/
theorem completed_iteration_is_least (step : (row → Prop) → row → Prop)
    (mono : Monotone step) (count : Nat)
    (stationary : iterate step (count + 1) = iterate step count) :
    iterate step count = least step := by
  have backward := iteration_below_least step mono count
  have closed : Included (step (iterate step count)) (iterate step count) := by
    intro x h
    have combined : iterate step (count + 1) x := Or.inr h
    rw [stationary] at combined
    exact combined
  have forward := least_below step (iterate step count) closed
  funext x
  exact propext ⟨backward x, forward x⟩

end Ascent.RecursiveLowering
