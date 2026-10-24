-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DescriptorStream

/-! The variable-decoding procedure, rather than a predicate supplied by the
caller. The tree includes the insertion effect and rejection before mutation.
Both host term-stream implementations are emitted from this definition.
Finite-map lookup/update, typed constructor projection and scalar equality are
the primitive representation boundary; no compiler-owned symbol map is read. -/
namespace Ascent.DescriptorKernel
open AtomicBinding PositiveSlots DescriptorStream

inductive Test where
  | known | head | bound | fresh
  deriving DecidableEq, Repr
inductive Move where
  | accept | reject | insert
  deriving DecidableEq, Repr
inductive Code where
  | finish (move : Move)
  | branch (test : Test) (yes no : Code)
  deriving DecidableEq, Repr

structure Context (Value : Type) where
  known : Option Nat
  count : Nat
  head : Bool
  action : EncodedAction Value

def test (context : Context Value) : Test → Bool
  | .known => context.known.isSome
  | .head => context.head
  | .bound => match context.action, context.known with
      | .bound actual, some expected => actual == expected
      | _, _ => false
  | .fresh => match context.action with
      | .fresh actual => actual == context.count
      | _ => false

def run (context : Context Value) : Code → Move
  | .finish move => move
  | .branch predicate yes no => if test context predicate then run context yes else run context no

def variableCode : Code :=
  .branch .known
    (.branch .bound (.finish .accept) (.finish .reject))
    (.branch .head (.finish .reject)
      (.branch .fresh (.finish .insert) (.finish .reject)))

def applyMove (move : Move) (symbols : Symbols) (name : Nat) : Option Symbols :=
  match move with
  | .accept => some symbols
  | .reject => none
  | .insert => some (insert symbols name)

def variableStep (name : Nat) (action : EncodedAction Value) (symbols : Symbols)
    (head : Bool) : Option Symbols :=
  applyMove (run ⟨symbols.find name, symbols.count, head, action⟩ variableCode) symbols name

def admittedOne [DecidableEq Value] (term : Term Value) (action : EncodedAction Value)
    (symbols : Symbols) (head : Bool) : Option Symbols :=
  if head && (match term with | .variable name => (symbols.find name).isNone | _ => false)
  then none else (decode action).bind (fun actual => checkOne term actual symbols)

theorem variable_exact [DecidableEq Value] (name : Nat) (action : EncodedAction Value)
    (symbols : Symbols) (head : Bool) :
    variableStep name action symbols head = admittedOne (.variable name) action symbols head := by
  cases found : symbols.find name <;> cases action <;> cases head <;>
    simp [variableStep, admittedOne, applyMove, run, variableCode, test, decode,
      checkOne, lowerMap, found, beq_iff_eq]
  all_goals split <;> simp_all
  all_goals split at * <;> simp_all

def streamOne [DecidableEq Value] (term : Term Value) (action : EncodedAction Value)
    (symbols : Symbols) (head : Bool) : Option Symbols :=
  match term with
  | .variable name => variableStep name action symbols head
  | _ => (decode action).bind (fun actual => checkOne term actual symbols)

theorem stream_one_exact [DecidableEq Value] (term : Term Value)
    (action : EncodedAction Value) (symbols : Symbols) (head : Bool) :
    streamOne term action symbols head = admittedOne term action symbols head := by
  cases term <;> simp [streamOne, admittedOne, variable_exact]

def loop [DecidableEq Value] : List (Term Value) → List (EncodedAction Value) → Symbols → Option Symbols
  | [], [], symbols => some symbols
  | term :: terms, action :: actions, symbols =>
      (streamOne term action symbols false).bind (fun next => loop terms actions next)
  | _, _, _ => none

theorem emitted_loop_exact [DecidableEq Value] (terms : List (Term Value))
    (actions : List (EncodedAction Value)) (symbols : Symbols) :
    loop terms actions symbols = checkEncoded terms actions symbols := by
  induction terms generalizing actions symbols with
  | nil => cases actions <;> rfl
  | cons term terms ih =>
    cases actions with
    | nil => rfl
    | cons action actions =>
      simp only [loop, stream_one_exact, admittedOne, Bool.false_and, Bool.false_eq_true, ↓reduceIte,
        checkEncoded, Option.bind_assoc]
      exact congrArg (fun continuation => (decode action).bind continuation)
        (funext fun actual => congrArg (fun continuation => (checkOne term actual symbols).bind continuation)
          (funext fun next => ih actions next))

theorem emitted_stream_accepts_iff [DecidableEq Value] (terms : List (Term Value))
    (actions : List (EncodedAction Value)) (names : List Nat) :
    (loop terms actions (canonical names)).isSome = true ↔
      decodeAll actions = some (compile terms names).1 := by
  rw [emitted_loop_exact]
  exact encoded_accepts_iff terms actions names

def executeOne [DecidableEq Value] (code : Code) (head : Bool)
    (term : Term Value) (action : EncodedAction Value) (symbols : Symbols) : Option Symbols :=
  match term with
  | .variable name =>
    applyMove (run ⟨symbols.find name, symbols.count, head, action⟩ code) symbols name
  | _ => (decode action).bind (fun actual => checkOne term actual symbols)

def execute [DecidableEq Value] (code : Code) (head : Bool) :
    List (Term Value) → List (EncodedAction Value) → Symbols → Option Symbols
  | [], [], symbols => some symbols
  | term :: terms, action :: actions, symbols =>
    (executeOne code head term action symbols).bind (fun next => execute code head terms actions next)
  | _, _, _ => none

theorem execute_variable [DecidableEq Value] (terms : List (Term Value))
    (actions : List (EncodedAction Value)) (symbols : Symbols) :
    execute variableCode false terms actions symbols = loop terms actions symbols := by
  induction terms generalizing actions symbols with
  | nil => cases actions <;> rfl
  | cons term terms ih =>
    cases actions with
    | nil => rfl
    | cons action actions =>
      have step : executeOne variableCode false term action symbols = streamOne term action symbols false := by
        cases term <;> rfl
      simp only [execute, loop, step]
      exact congrArg (fun continuation => (streamOne term action symbols false).bind continuation)
        (funext fun next => ih actions next)

def schemeTest : Test → String
  | .known => "known"
  | .head => "head?"
  | .bound => "(and (eq? (car action) 'bound) (eqv? (cdr action) known))"
  | .fresh => "(and (eq? (car action) 'fresh) (eqv? (cdr action) count))"

def schemeCode : Code → String
  | .finish .accept => "(void)"
  | .finish .reject => "(reject #f)"
  | .finish .insert => "(begin (hash-put! slots (cdr source) count) (set! count (+ count 1)))"
  | .branch predicate yes no => s!"(if {schemeTest predicate} {schemeCode yes} {schemeCode no})"

def rustTest : Test → String
  | .known => "known.is_some()"
  | .head => "head"
  | .bound => "known == Some(*slot as usize)"
  | .fresh => "names.len() == *slot as usize"

def rustCode : Code → String
  | .finish .accept => "Some(())"
  | .finish .reject => "None"
  | .finish .insert => "names.insert(*name, names.len()); Some(())"
  | .branch predicate yes (.branch next yes' no') =>
      s!"if {rustTest predicate} \{ {rustCode yes} } else {rustCode (.branch next yes' no')}"
  | .branch predicate yes no => s!"if {rustTest predicate} \{ {rustCode yes} } else \{ {rustCode no} }"

def schemeSource : String :=
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Generated by DescriptorKernel.lean; the private map is not the compiler map.\n" ++
  "(export gerbil-ascent-certificate-terms!)\n" ++
  "(def (gerbil-ascent-certificate-terms! sources actions slots count head?)\n  (let/cc reject\n    (unless (and (list? actions) (= (length sources) (length actions))) (reject #f))\n    (for-each\n      (lambda (source action)\n        (unless (pair? action) (reject #f))\n        (case (car source)\n          ((literal wildcard) (unless (equal? source action) (reject #f)))\n          ((variable)\n            (let (known (hash-get slots (cdr source)))\n              " ++ schemeCode variableCode ++ "))\n          (else (reject #f)))) sources actions)\n    count))\n"

def rustSource : String :=
  "// SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n// SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n// Generated by DescriptorKernel.lean; typed projections and map primitives remain host operations.\n" ++
  "use crate::{Term, execution::{Pattern, Values}};\nuse std::collections::HashMap;\n\n#[rustfmt::skip]\npub(super) fn check_terms(source: &[Term], actual: &[Pattern], values: &Values, names: &mut HashMap<u32, usize>, head: bool) -> bool {\n    source.len() == actual.len() && source.iter().zip(actual).all(|(source, actual)| {\n        (match (source, actual) {\n            (Term::Wildcard, Pattern::Wildcard) => Some(()),\n            (Term::Literal(wanted), Pattern::Literal(cell)) => (values.scalar(*cell) == wanted).then_some(()),\n            (Term::Variable(name), Pattern::Variable(slot)) => {\n                let known = names.get(name).copied();\n                " ++ rustCode variableCode ++ "\n            }\n            _ => None,\n        }).is_some()\n    })\n}\n"

end Ascent.DescriptorKernel
