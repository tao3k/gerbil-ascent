-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
/-! Closed expression lowering under the same canonical primitive bindings.
Primitive results include errors. This theorem covers the expression transform,
not Gerbil expansion, reader admission, or arbitrary Scheme syntax. Native tests
must establish those representation and ownership obligations separately. -/
namespace Ascent.ClosedDslLowering
inductive Value where
  | boolean (b : Bool)
  | scalar (n : Int)
  | text (s : String)
  | empty
  | pair (head tail : Value)
  deriving DecidableEq, Repr
abbrev Result := Except String Value
def truth : Value → Bool
  | .boolean false => false
  | _ => true
inductive Expr where
  | literal (v : Value)
  | variable (n : Nat)
  | unary (op : Nat) (a : Expr)
  | binary (op : Nat) (a b : Expr)
  | andThen (a b : Expr)
  | orElse (a b : Expr)
abbrev Env := Nat → Result
abbrev Unary := Nat → Value → Result
abbrev Binary := Nat → Value → Value → Result
def eval (u : Unary) (b : Binary) (env : Env) : Expr → Result
  | .literal v => .ok v
  | .variable n => env n
  | .unary op a => (eval u b env a).bind (u op)
  | .binary op a c => (eval u b env a).bind fun x => (eval u b env c).bind (b op x)
  | .andThen a c => (eval u b env a).bind fun x => if truth x then eval u b env c else .ok x
  | .orElse a c => (eval u b env a).bind fun x => if truth x then .ok x else eval u b env c
def compile (u : Unary) (b : Binary) : Expr → Env → Result
  | .literal v => fun _ => .ok v
  | .variable n => fun env => env n
  | .unary op a => let child := compile u b a; fun env => (child env).bind (u op)
  | .binary op a c => let left := compile u b a; let right := compile u b c
                     fun env => (left env).bind fun x => (right env).bind (b op x)
  | .andThen a c => let left := compile u b a; let right := compile u b c
                      fun env => (left env).bind fun x => if truth x then right env else .ok x
  | .orElse a c => let left := compile u b a; let right := compile u b c
                     fun env => (left env).bind fun x => if truth x then .ok x else right env
 theorem equivalent (u : Unary) (b : Binary) (e : Expr) :
    ∀ env, compile u b e env = eval u b env e := by
  induction e <;> intro env <;> simp_all [compile, eval]
example : truth (.scalar 0) = true := rfl
example (u : Unary) (b : Binary) (env : Env) (e : Expr) :
    eval u b env (.andThen (.literal (.boolean false)) e) = .ok (.boolean false) := rfl
example (u : Unary) (b : Binary) (env : Env) (e : Expr) :
    eval u b env (.orElse (.literal (.scalar 0)) e) = .ok (.scalar 0) := rfl
def structuralEquality (_ : Nat) (left right : Value) : Result :=
  .ok (.boolean (decide (left = right)))
example (u : Unary) (env : Env) :
    compile u structuralEquality
      (.binary 0 (.literal (.pair (.text "a") (.pair (.scalar 1) .empty)))
                 (.literal (.pair (.text "a") (.pair (.scalar 1) .empty)))) env =
      .ok (.boolean true) := rfl
example (u : Unary) (env : Env) :
    compile u structuralEquality (.binary 0 (.literal (.text "1"))
      (.literal (.scalar 1))) env = .ok (.boolean false) := rfl
-- Closed Evidence selection is all-or-nothing. Admission stores declarations,
-- not a previously constructed result. Every accepted call invokes the same
-- declaration constructor as the macro, with its current invocation identity.
def closedScope {D V : Type} (construct : D → Nat → V)
    (declarations : List D) (index : Nat) (invocation : Nat) : Option V :=
  (declarations[index]?).map (fun declaration => construct declaration invocation)
theorem scope_constructor_equivalent {D V : Type} (construct : D → Nat → V)
    (declarations : List D) (index invocation : Nat) :
    closedScope construct declarations index invocation =
      (declarations[index]?).map (fun declaration => construct declaration invocation) := rfl
theorem distinct_invocations {D : Type} (declarations : List D) (index first second : Nat)
    (present : ∃ declaration, declarations[index]? = some declaration)
    (different : first ≠ second) :
    closedScope (fun (_ : D) invocation => invocation) declarations index first ≠
      closedScope (fun (_ : D) invocation => invocation) declarations index second := by
  obtain ⟨declaration, found⟩ := present
  simp [closedScope, found, different]
-- A compiler-resolved reader takes the current store on every invocation.
-- Replacing lookup by a previously read value would not satisfy this contract.
def exportReader {S V : Type} (lookup : S → V) : S → V := fun store => lookup store
theorem export_current_binding {S V : Type} (lookup : S → V) (store : S) :
    exportReader lookup store = lookup store := rfl
end Ascent.ClosedDslLowering
