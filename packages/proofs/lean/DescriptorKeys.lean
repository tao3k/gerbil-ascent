-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DescriptorKernel

/-! Index admission reads the private map BEFORE the atom's term checker.
A repeated variable introduced by this atom cannot become a lookup key.
This module connects the complete ordered key list to CompiledCertificate;
rendering and host primitive faithfulness remain separate obligations. -/
namespace Ascent.DescriptorKeys
open AtomicBinding PositiveSlots DescriptorStream IndexedPositiveTraversal
variable {Value : Type} [DecidableEq Value]

/-- The logical name list is a finite-map enumeration, not merely a count.
This invariant is needed before relating its length to Rust HashMap::len. -/
theorem slot_none_iff (name : Nat) (names : List Nat) :
    slot name names = none ↔ name ∉ names := by
  induction names with
  | nil => simp [slot]
  | cons first rest ih =>
      by_cases same : name = first
      · simp [slot, same]
      · simp [slot, same, ih]

omit [DecidableEq Value] in
theorem lower_names_nodup (term : Term Value) (names : List Nat) (unique : names.Nodup) :
    (lower term names).2.Nodup := by
  cases term with
  | literal => exact unique
  | wildcard => exact unique
  | «variable» name =>
      cases found : slot name names with
      | some index => simpa [lower, found] using unique
      | none =>
          have fresh := (slot_none_iff name names).mp found
          simp only [lower, found, List.nodup_append]
          refine ⟨unique, by simp, ?_⟩
          intro a member b singleton same
          have : b = name := by simpa using singleton
          subst b
          subst a
          exact fresh member

omit [DecidableEq Value] in
theorem compile_names_nodup (terms : List (Term Value)) (names : List Nat)
    (unique : names.Nodup) : (compile terms names).2.Nodup := by
  induction terms generalizing names with
  | nil => exact unique
  | cons term terms ih => exact ih _ (lower_names_nodup term names unique)

def readKey (symbols : Symbols) : Term Value → Option (Action Value)
  | .literal value => some (.literal value)
  | .wildcard => none
  | .variable name => (symbols.find name).map Action.bound

def collect (terms : List (Term Value)) (symbols : Symbols) : List Nat → Option (List (Action Value))
  | [] => some []
  | column :: columns => do
      let term ← terms[column]?
      let key ← readKey symbols term
      let rest ← collect terms symbols columns
      pure (key :: rest)

def readable (terms : List (Term Value)) (names : List Nat) (column : Nat) : Bool :=
  match terms[column]? with
  | none => false
  | some term => match term with
    | .literal _ => true
    | .wildcard => false
    | .variable name => (slot name names).isSome

private instance (names : List Nat) (term : Term Value) : Decidable (Indexable names term) := by
  cases term <;> unfold Indexable <;> infer_instance

omit [DecidableEq Value] in
theorem read_exact (term : Term Value) (names : List Nat) :
    readKey (canonical names) term =
      if Indexable names term then some (lower term names).1 else none := by
  cases term with
  | literal => simp [readKey, Indexable, lower]
  | wildcard => simp [readKey, Indexable]
  | «variable» name =>
      cases found : slot name names <;> simp [readKey, canonical, lower, Indexable, found]

omit [DecidableEq Value] in
theorem collect_exact (terms : List (Term Value)) (columns names : List Nat) :
    collect terms (canonical names) columns =
      if columns.all (readable terms names)
      then some (columns.filterMap (fun column => (compile terms names).1[column]?))
      else none := by
  induction columns with
  | nil => simp [collect]
  | cons column columns ih =>
      cases located : terms[column]? with
      | none => simp [collect, readable, located]
      | some term =>
          by_cases known : Indexable names term
          · have compiled := compile_known_at terms names column term located known
            have readableTrue : readable terms names column = true := by
              cases term <;> simp_all [readable, Indexable]
            simp [collect, located, read_exact, known, ih, readableTrue, compiled]
            split <;> rfl
          · have readableFalse : readable terms names column = false := by
              cases term <;> simp_all [readable, Indexable]
            simp [collect, located, read_exact, known, readableFalse]

/-- Complete decoded descriptor gate, including final symbol names and ordered
keys. This is equality with accept, not only a soundness implication. -/
def check (terms : List (Term Value)) (columns names : List Nat)
    (actual : CompiledCertificate.Descriptor Value) : Bool :=
  (DescriptorStream.check terms actual.actions (canonical names)).isSome &&
    decide (actual.names = (compile terms names).2) &&
    decide (collect terms (canonical names) columns = some actual.keys)

theorem check_accept (terms : List (Term Value)) (columns names : List Nat)
    (actual : CompiledCertificate.Descriptor Value) :
    check terms columns names actual = CompiledCertificate.accept terms columns names actual := by
  have accept_form : CompiledCertificate.accept terms columns names actual =
      (decide (actual = CompiledCertificate.expected terms columns names) &&
        columns.all (readable terms names)) := rfl
  rw [accept_form, check, DescriptorStream.stream_exact, collect_exact]
  cases actual with
  | mk actions keys output =>
      by_cases a : actions = (compile terms names).1
      · by_cases n : output = (compile terms names).2
        · subst actions; subst output
          simp only [↓reduceIte, decide_true]
          cases columns.all (readable terms names) <;>
            simp [CompiledCertificate.expected, eq_comm]
        · simp [n, CompiledCertificate.expected]
      · simp [a, CompiledCertificate.expected]

def schemeSource : String := DescriptorKernel.schemeSource ++
  "(export gerbil-ascent-certificate-keys?)\n(def (gerbil-ascent-certificate-keys? sources columns keys slots)\n  (let/cc reject\n    (unless (and (list? columns) (list? keys) (= (length columns) (length keys))) (reject #f))\n    (unless (null? columns)\n      (let* ((view (list->vector sources)) (width (vector-length view)))\n        (for-each\n          (lambda (column key)\n            (unless (and (exact-integer? column) (<= 0 column) (< column width)) (reject #f))\n            (let (source (vector-ref view column))\n              (case (car source)\n                ((literal) (unless (equal? key source) (reject #f)))\n                ((variable)\n                  (let (known (hash-get slots (cdr source)))\n                    (unless (and known (pair? key) (eq? (car key) 'bound) (eqv? (cdr key) known)) (reject #f))))\n                (else (reject #f))))) columns keys)))\n    #t))\n"

def rustSource : String := DescriptorKernel.rustSource ++
  "\n#[rustfmt::skip]\npub(super) fn check_keys(source: &[Term], actual: &[usize], names: &HashMap<u32, usize>) -> bool {\n    source.iter().enumerate().filter_map(|(column, term)| match term {\n        Term::Literal(_) => Some(column),\n        Term::Variable(name) if names.contains_key(name) => Some(column),\n        _ => None,\n    }).eq(actual.iter().copied())\n}\n"

end Ascent.DescriptorKeys
