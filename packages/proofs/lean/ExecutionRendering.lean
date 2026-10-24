-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ExecutionPolicy

/-! Translation validation of the actual finite policy *code*, with correctness
for arbitrary environments. This is not enumeration of input values. Independent
prefix/infix parsers recover the AST printed for each installed definition;
kernel-checked AST equality then gives denotational equality for all arguments.
The target compilers' standard Boolean/comparison semantics remain trusted. -/
namespace Ascent.ExecutionRendering
open ExecutionPolicy

def flush (current : List Char) (out : List String) : List String :=
  if current.isEmpty then out else String.ofList current.reverse :: out
def lex : List Char → List Char → List String → List String
  | [], current, out => (flush current out).reverse
  | c :: rest, current, out =>
      if c == ' ' then lex rest [] (flush current out)
      else if c == '(' || c == ')' || c == '!' then
        lex rest [] (String.ofList [c] :: flush current out)
      else lex rest (c :: current) out
def tokens (source : String) : List String := lex source.toList [] []
def sourceName (name : String) : String :=
  let chars := name.toList
  let plain := if "policy-".toList.isPrefixOf chars then chars.drop 7 else chars
  String.ofList (plain.map fun c => if c == '-' then '_' else c)

def readNumber (name : String) : Number :=
  if name == "0" then .zero else .variable (sourceName name)

def prefixParse : Nat → List String → Option (Predicate × List String)
  | 0, _ => none
  | fuel + 1, "(" :: op :: rest => do
      if op == "<" || op == "=" then
        match rest with
        | left :: right :: ")" :: tail =>
            return (if op == "<" then .less (readNumber left) (readNumber right)
              else .equal (readNumber left) (readNumber right), tail)
        | _ => none
      else
        let (left, rest) ← prefixParse fuel rest
        if op == "not" then
          match rest with
          | ")" :: tail => return (.negate left, tail)
          | _ => none
        else
          let (right, rest) ← prefixParse fuel rest
          match rest with
          | ")" :: tail =>
              if op == "and" then return (.both left right, tail)
              else if op == "or" then return (.either left right, tail)
              else none
          | _ => none
  | _ + 1, name :: rest =>
      if name == ")" then none else some (.flag (sourceName name), rest)
  | _ + 1, [] => none

def infixParse : Nat → List String → Option (Predicate × List String)
  | 0, _ => none
  | fuel + 1, "not" :: "(" :: rest => do
      let (value, rest) ← infixParse fuel rest
      match rest with
      | ")" :: tail => return (.negate value, tail)
      | _ => none
  | fuel + 1, "(" :: "!" :: rest => do
      let (value, rest) ← infixParse fuel rest
      match rest with
      | ")" :: tail => return (.negate value, tail)
      | _ => none
  | fuel + 1, "(" :: rest => do
      let (left, rest) ← infixParse fuel rest
      match rest with
      | op :: rest =>
          let (right, rest) ← infixParse fuel rest
          match rest with
          | ")" :: tail =>
              if op == "&&" || op == "and" then return (.both left right, tail)
              else if op == "||" || op == "or" then return (.either left right, tail)
              else match left, right with
                | .flag left, .flag right =>
                    if op == "<" then return (.less (readNumber left) (readNumber right), tail)
                    else if op == "==" then return (.equal (readNumber left) (readNumber right), tail)
                    else none
                | _, _ => none
          | _ => none
      | _ => none
  | _ + 1, name :: rest => if name == ")" then none else some (.flag name, rest)
  | _ + 1, [] => none

def finish (parsed : Option (Predicate × List String)) : Option Predicate := do
  let (body, remaining) ← parsed
  if remaining.isEmpty then some body else none
def readScheme (source : String) : Option Predicate := finish (prefixParse 128 (tokens source))
def readInfix (source : String) : Option Predicate :=
  finish (infixParse 128 (tokens source))

def numberScoped (numbers : List String) : Number → Bool
  | .zero => true
  | .variable name => numbers.contains name

def wellScoped (numbers flags : List String) : Predicate → Bool
  | .flag name => flags.contains name
  | .less left right | .equal left right => numberScoped numbers left && numberScoped numbers right
  | .both left right | .either left right => wellScoped numbers flags left && wellScoped numbers flags right
  | .negate value => wellScoped numbers flags value

theorem installed_signatures : definitions.all (fun d =>
    wellScoped d.numbers d.flags d.body && decide (d.numbers ++ d.flags).Nodup) = true := by decide

theorem installed_bindings : definitions.all (fun d =>
    decide ((d.numbers ++ d.flags).map (fun name => sourceName (boundName name)) =
      d.numbers ++ d.flags)) = true := by decide

-- Kernel reduction of hygienic identifier strings; parser fuel and formal
-- exploration bounds are unchanged.
set_option maxRecDepth 4096 in
theorem installed_scheme_parses : definitions.all (fun d =>
    decide (readScheme (scheme d.body) = some d.body)) = true := by decide
theorem installed_rust_parses : definitions.all (fun d =>
    decide (readInfix (rust d.body) = some d.body)) = true := by decide
theorem installed_quint_parses : definitions.all (fun d =>
    decide (readInfix (quint d.body) = some d.body)) = true := by decide

theorem installed_scheme_refines (d : Definition) (member : d ∈ definitions)
    (numbers : String → Nat) (flags : String → Bool) :
    (readScheme (scheme d.body)).map (eval numbers flags) = some (eval numbers flags d.body) := by
  have parsed := List.all_eq_true.mp installed_scheme_parses d member
  have exactBody : readScheme (scheme d.body) = some d.body := of_decide_eq_true parsed
  simp [exactBody]

theorem installed_rust_refines (d : Definition) (member : d ∈ definitions)
    (numbers : String → Nat) (flags : String → Bool) :
    (readInfix (rust d.body)).map (eval numbers flags) = some (eval numbers flags d.body) := by
  have parsed := List.all_eq_true.mp installed_rust_parses d member
  have exactBody : readInfix (rust d.body) = some d.body := of_decide_eq_true parsed
  simp [exactBody]

theorem installed_quint_refines (d : Definition) (member : d ∈ definitions)
    (numbers : String → Nat) (flags : String → Bool) :
    (readInfix (quint d.body)).map (eval numbers flags) = some (eval numbers flags d.body) := by
  have parsed := List.all_eq_true.mp installed_quint_parses d member
  have exactBody : readInfix (quint d.body) = some d.body := of_decide_eq_true parsed
  simp [exactBody]

-- Translation validation refuses unsupported operators; changing a known
-- operator changes the recovered AST and fails the installed-code equality.
example : readInfix "(position > pivot)" = none := by decide
example : readInfix "(position == pivot)" ≠ some (.less "position" "pivot") := by decide
example : readScheme "(and has-pivot (<= position pivot))" = none := by decide

end Ascent.ExecutionRendering
