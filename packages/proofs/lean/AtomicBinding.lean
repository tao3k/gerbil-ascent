-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import StratifiedNegation

/-! Callback-free atom binding on admitted equal-arity rows. Variable identities
are represented by naturals, not printed names. This models the ordinary
association-list branch of core/rule-semantics.ss, not its private fresh-variable
optimization or the positive-plan slot machine. Native decoding, lawful scalar
equality and arity admission remain representation obligations. -/
namespace Ascent.AtomicBinding

inductive Term (Value : Type) where
  | literal (value : Value)
  | variable (identity : Nat)
  | wildcard
  deriving DecidableEq

abbrev Env (Value : Type) := List (Nat × Value)

def lookup : Nat → Env Value → Option Value
  | _, [] => none
  | name, (key, value) :: rest =>
      if name = key then some value else lookup name rest

def Extends (before after : Env Value) : Prop :=
  ∀ name value, lookup name before = some value → lookup name after = some value

def bind [DecidableEq Value] : List (Term Value) → List Value → Env Value → Option (Env Value)
  | [], [], input => some input
  | .wildcard :: terms, _ :: row, input => bind terms row input
  | .literal expected :: terms, value :: row, input =>
      if expected = value then bind terms row input else none
  | .variable name :: terms, value :: row, input =>
      match lookup name input with
      | some previous => if previous = value then bind terms row input else none
      | none => bind terms row ((name, value) :: input)
  | _, _, _ => none

/-- Declarative satisfaction observes the final substitution, including all
occurrences of a repeated variable. It is independent of binding order. -/
def Matches : List (Term Value) → List Value → Env Value → Prop
  | [], [], _ => True
  | .wildcard :: terms, _ :: row, output => Matches terms row output
  | .literal expected :: terms, value :: row, output =>
      expected = value ∧ Matches terms row output
  | .variable name :: terms, value :: row, output =>
      lookup name output = some value ∧ Matches terms row output
  | _, _, _ => False

theorem extends_refl (input : Env Value) : Extends input input := by
  intro name value present; exact present

theorem extends_trans {a b c : Env Value}
    (first : Extends a b) (second : Extends b c) : Extends a c := by
  intro name value present; exact second name value (first name value present)

theorem extends_fresh (input : Env Value) (name : Nat) (value : Value)
    (absent : lookup name input = none) : Extends input ((name, value) :: input) := by
  intro key observed present
  by_cases same : key = name
  · subst key; rw [absent] at present; contradiction
  · simpa [lookup, same] using present

theorem bind_sound [DecidableEq Value] (terms : List (Term Value))
    (row : List Value) (input output : Env Value)
    (success : bind terms row input = some output) :
    Extends input output ∧ Matches terms row output := by
  induction terms generalizing row input output with
  | nil =>
      cases row <;> simp [bind] at success
      subst output
      exact ⟨extends_refl input, trivial⟩
  | cons term rest ih =>
      cases row with
      | nil => cases term <;> simp [bind] at success
      | cons value tail =>
          cases term with
          | wildcard => exact ih tail input output success
          | literal expected =>
              by_cases same : expected = value
              · have result := ih tail input output (by simpa [bind, same] using success)
                exact ⟨result.1, same, result.2⟩
              · simp [bind, same] at success
          | «variable» name =>
              cases found : lookup name input with
              | none =>
                  have result := ih tail ((name, value) :: input) output
                    (by simpa [bind, found] using success)
                  exact ⟨extends_trans (extends_fresh input name value found) result.1,
                    result.1 name value (by simp [lookup]), result.2⟩
              | some previous =>
                  by_cases same : previous = value
                  · have result := ih tail input output
                      (by simpa [bind, found, same] using success)
                    exact ⟨result.1, result.1 name value (by simpa [same] using found), result.2⟩
                  · simp [bind, found, same] at success

/-- Every declarative solution extending the input admits an operational
binding, and that binding remains consistent with the same solution. -/
theorem bind_complete [DecidableEq Value] (terms : List (Term Value))
    (row : List Value) (input witness : Env Value)
    (extension : Extends input witness) (satisfied : Matches terms row witness) :
    ∃ output, bind terms row input = some output ∧ Extends output witness := by
  induction terms generalizing row input with
  | nil =>
      cases row with
      | nil => exact ⟨input, rfl, extension⟩
      | cons _ _ => contradiction
  | cons term rest ih =>
      cases row with
      | nil => cases term <;> contradiction
      | cons value tail =>
          cases term with
          | wildcard => exact ih tail input extension satisfied
          | literal expected =>
              obtain ⟨output, success, covered⟩ := ih tail input extension satisfied.2
              exact ⟨output, by simpa [bind, satisfied.1] using success, covered⟩
          | «variable» name =>
              cases found : lookup name input with
              | some previous =>
                  have same : previous = value := by
                    have equal := extension name previous found
                    rw [satisfied.1] at equal
                    exact Option.some.inj equal.symm
                  obtain ⟨output, success, covered⟩ := ih tail input extension satisfied.2
                  exact ⟨output, by simpa [bind, found, same] using success, covered⟩
              | none =>
                  have covered : Extends ((name, value) :: input) witness := by
                    intro key observed present
                    by_cases same : key = name
                    · subst key
                      have equal : value = observed := by simpa [lookup] using present
                      simpa [equal] using satisfied.1
                    · exact extension key observed (by simpa [lookup, same] using present)
                  obtain ⟨output, success, covered⟩ :=
                    ih tail ((name, value) :: input) covered satisfied.2
                  exact ⟨output, by simpa [bind, found] using success, covered⟩

def wanted (input : Env Value) : Term Value → Option Value
  | .literal value => some value
  | .variable name => lookup name input
  | .wildcard => none

/-- Arbitrary indexed columns are safe if their values were known before
this atom. Newly bound or repeated local variables are checked by binding. -/
theorem matched_column [DecidableEq Value]
    (terms : List (Term Value)) (row : List Value) (input output : Env Value)
    (success : bind terms row input = some output)
    (term : Term Value) (value expected : Value)
    (column : (term, value) ∈ terms.zip row)
    (known : wanted input term = some expected) : value = expected := by
  obtain ⟨preserved, matched⟩ := bind_sound terms row input output success
  have satisfies : ∀ term value, (term, value) ∈ terms.zip row →
      match term with
      | .literal expected => expected = value
      | .variable name => lookup name output = some value
      | .wildcard => True := by
    clear success preserved known column
    induction terms generalizing row with
    | nil => simp
    | cons head rest ih =>
        cases row with
        | nil => simp
        | cons observed tail =>
            intro term value member
            simp only [List.zip_cons_cons, List.mem_cons] at member
            rcases member with equal | later
            · cases equal
              cases head <;> simp_all [Matches]
            · apply ih tail (by cases head <;> simp_all [Matches]) term value later
  have fact := satisfies term value column
  cases term with
  | literal literal => simp only [wanted, Option.some.injEq] at known; simpa [known] using fact.symm
  | «variable» name =>
      have initial : lookup name input = some expected := known
      have final := preserved name expected initial
      rw [fact] at final
      exact Option.some.inj final
  | wildcard => simp [wanted] at known

def termKey (input : Env Value) (terms : List (Term Value)) : List Value :=
  terms.filterMap (wanted input)

def rowKey (input : Env Value) (terms : List (Term Value)) (row : List Value) : List Value :=
  (terms.zip row).filterMap (fun (term, value) => (wanted input term).map (fun _ => value))

theorem matches_key (terms : List (Term Value)) (row : List Value)
    (input output : Env Value) (preserved : Extends input output)
    (satisfied : Matches terms row output) :
    rowKey input terms row = termKey input terms := by
  induction terms generalizing row with
  | nil => simp [rowKey, termKey]
  | cons term rest ih =>
      cases row with
      | nil => cases term <;> contradiction
      | cons value tail =>
          cases term with
          | wildcard =>
              simpa only [rowKey, termKey, List.zip_cons_cons, List.filterMap_cons,
                wanted, Option.map_none] using ih tail satisfied
          | literal expected =>
              simpa only [rowKey, termKey, List.zip_cons_cons, List.filterMap_cons,
                wanted, Option.map_some, satisfied.1, List.cons.injEq, true_and]
                using ih tail satisfied.2
          | «variable» name =>
              cases found : lookup name input with
              | none =>
                  simpa only [rowKey, termKey, List.zip_cons_cons, List.filterMap_cons,
                    wanted, found, Option.map_none] using ih tail satisfied.2
              | some expected =>
                  have same := preserved name expected found
                  rw [satisfied.1] at same
                  have equal : value = expected := Option.some.inj same
                  simpa only [rowKey, termKey, List.zip_cons_cons, List.filterMap_cons,
                    wanted, found, Option.map_some, equal, List.cons.injEq, true_and]
                    using ih tail satisfied.2

theorem bind_key [DecidableEq Value] (terms : List (Term Value)) (row : List Value)
    (input output : Env Value) (success : bind terms row input = some output) :
    rowKey input terms row = termKey input terms :=
  matches_key terms row input output (bind_sound terms row input output success).1
    (bind_sound terms row input output success).2

/-- Composes binder soundness with the existing physical-bucket membership
invariant. Extra candidates may be rechecked; no matching row may be omitted. -/
theorem indexed_atom_iff [DecidableEq Value]
    (terms : List (Term Value)) (full : List (List Value))
    (buckets : StratifiedNegation.Buckets (List Value) (List Value))
    (input output : Env Value)
    (rep : StratifiedNegation.BucketRep full (rowKey input terms) buckets) :
    StratifiedNegation.ClauseHolds
        (.atom (buckets (termKey input terms)) (fun env row => bind terms row env)) input output ↔
      StratifiedNegation.ClauseHolds
        (.atom full (fun env row => bind terms row env)) input output := by
  apply StratifiedNegation.atom_indexed_iff
  exact StratifiedNegation.bucket_index_exact full (rowKey input terms) buckets rep
    (fun env row => bind terms row env) input (termKey input terms)
    (fun row result success => bind_key terms row input result success)

end Ascent.AtomicBinding
