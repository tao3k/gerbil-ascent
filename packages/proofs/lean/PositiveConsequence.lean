-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveTraversal
import SemiNaive

/-! Connect ordered dirty-slot traversal to positive-body consequence membership.
Rows are frozen finite lists. Native row encoding, actual index lookup and pivot
selection remain separate. List multiplicity is retained by traversal; Set
membership is the observation used by the consequence calculus. -/
namespace Ascent.PositiveConsequence
open AtomicBinding PositiveSlots PositiveTraversal
variable {Key Value Output : Type} [DecidableEq Value]

structure Atom (Key Value : Type) where
  source : Key
  terms : List (Term Value)

def instantiate (atoms : List (Atom Key Value))
    (rows : Key → List (List Value)) : List (PositiveTraversal.Atom Value) :=
  atoms.map fun atom => ⟨atom.terms, rows atom.source⟩

def transition (rows : Key → List (List Value)) (atom : Atom Key Value)
    (input result : Env Value) : Prop :=
  ∃ row ∈ rows atom.source, bind atom.terms row input = some result

theorem reference_membership (atoms : List (Atom Key Value))
    (rows : Key → List (List Value)) (emit : Env Value → List Output)
    (input : Env Value) (value : Output) :
    value ∈ reference (instantiate atoms rows) emit input ↔
      ∃ result, ProviderFrontier.body (transition rows) atoms input result ∧
        value ∈ emit result := by
  induction atoms generalizing input with
  | nil => simp [instantiate, reference, ProviderFrontier.body]
  | cons atom rest ih =>
      simp only [instantiate, List.map_cons, reference, List.mem_flatMap]
      constructor
      · rintro ⟨row, member, emitted⟩
        cases found : bind atom.terms row input with
        | none => simp [found] at emitted
        | some middle =>
            simp only [found] at emitted
            obtain ⟨result, tail, head⟩ := (ih middle).mp emitted
            exact ⟨result, ⟨middle, ⟨row, member, found⟩, tail⟩, head⟩
      · rintro ⟨result, ⟨middle, ⟨row, member, found⟩, tail⟩, head⟩
        refine ⟨row, member, ?_⟩
        simp only [found]
        exact (ih middle).mpr ⟨result, tail, head⟩

/-- Precompiled slot outputs, after observing membership, are exactly the
concrete environment-path output relation used by ProviderFrontier. -/
theorem precompiled_membership (atoms : List (Atom Key Value))
    (rows : Key → List (List Value)) (head : Env Value → Output)
    (slotEmit : List Nat → Frame Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = [head env])
    (arity : Arity (instantiate atoms rows)) (names : List Nat)
    (input : Env Value) (frame : Frame Value) (rep : Represents names input frame)
    (value : Output) :
    value ∈ (runBody (compileBody (instantiate atoms rows) names).1
      (compileBody (instantiate atoms rows) names).2 slotEmit frame).1 ↔
      ProviderFrontier.output
        (ProviderFrontier.body (transition rows) atoms input) head value := by
  rw [precompiled_refines (instantiate atoms rows) slotEmit (fun env => [head env])
    emits arity names input frame rep]
  rw [reference_membership]
  simp only [List.mem_singleton, ProviderFrontier.output]
  constructor
  · rintro ⟨result, body, eq⟩
    exact ⟨result, body, eq.symm⟩
  · rintro ⟨result, body, eq⟩
    exact ⟨result, body, eq.symm⟩

/-- Binder transitions are monotone because added rows preserve successful
witnesses. This derives the view premise; no callback monotonicity is assumed. -/
theorem transition_monotone (before after : Key → List (List Value))
    (included : ∀ key row, row ∈ before key → row ∈ after key)
    (atom : Atom Key Value) (input result : Env Value)
    (success : transition before atom input result) :
    transition after atom input result := by
  obtain ⟨row, member, bound⟩ := success
  exact ⟨row, included atom.source row member, bound⟩

/-- Faithful enumeration within a fixed admitted finite tuple domain supplies
SemiNaive's monotone concrete view. Facts outside that domain are not read;
no enumeration of arbitrary infinite databases is assumed. -/
def view (enumerate : SemiNaive.Database (Key × List Value) → Key → List (List Value)) :
    SemiNaive.View (Atom Key Value) (Env Value) (Key × List Value) :=
  fun database => transition (enumerate database)

theorem enumerated_view_monotone
    (enumerate : SemiNaive.Database (Key × List Value) → Key → List (List Value))
    (tupleDomain : List (Key × List Value))
    (faithful : ∀ database key row, row ∈ enumerate database key ↔
      (key, row) ∈ tupleDomain ∧ database (key, row)) :
    SemiNaive.ViewMonotone (view enumerate) := by
  intro before after included atom input result success
  apply transition_monotone (enumerate before) (enumerate after) _ atom input result success
  intro key row member
  have admitted := (faithful before key row).mp member
  exact (faithful after key row).mpr ⟨admitted.1, included (key, row) admitted.2⟩

/-- The iteration theorem now applies to the same row/binder view as the
traversal bridge, with monotonicity derived from faithful row enumeration. -/
theorem binder_iterations_equal
    (enumerate : SemiNaive.Database (Key × List Value) → Key → List (List Value))
    (tupleDomain : List (Key × List Value))
    (faithful : ∀ database key row, row ∈ enumerate database key ↔
      (key, row) ∈ tupleDomain ∧ database (key, row))
    (rules : List (SemiNaive.Rule (Atom Key Value) (Env Value) (Key × List Value)))
    (initial : SemiNaive.Database (Key × List Value)) (n : Nat) :
    SemiNaive.semiNaive rules (view enumerate) initial n =
      (SemiNaive.naive rules (view enumerate) initial n,
       SemiNaive.naive rules (view enumerate) initial (n + 1)) :=
  SemiNaive.iterations_equal rules (view enumerate)
    (enumerated_view_monotone enumerate tupleDomain faithful) initial n

/-- A mathematical enumerator for the declared tuple domain. Classical
membership here specifies semantics; it is not emitted Scheme code. -/
noncomputable def admittedRows (tupleDomain : List (Key × List Value))
    (database : SemiNaive.Database (Key × List Value)) (key : Key) : List (List Value) := by
  classical
  exact tupleDomain.filterMap fun tagged =>
    if tagged.1 = key ∧ database tagged then some tagged.2 else none

theorem admitted_rows_faithful (tupleDomain : List (Key × List Value))
    (database : SemiNaive.Database (Key × List Value)) (key : Key) (row : List Value) :
    row ∈ admittedRows tupleDomain database key ↔
      (key, row) ∈ tupleDomain ∧ database (key, row) := by
  classical
  constructor
  · intro member
    obtain ⟨tagged, present, found⟩ := List.mem_filterMap.mp member
    change (if tagged.1 = key ∧ database tagged then some tagged.2 else none) = some row at found
    split at found
    · rename_i kept
      have rowsEq := Option.some.inj found
      have pairEq : tagged = (key, row) := Prod.ext kept.1 rowsEq
      simpa [pairEq] using And.intro present kept.2
    · contradiction
  · rintro ⟨present, kept⟩
    apply List.mem_filterMap.mpr
    exact ⟨(key, row), present, by simp [admittedRows, kept]⟩

theorem admitted_binder_iterations_equal (tupleDomain : List (Key × List Value))
    (rules : List (SemiNaive.Rule (Atom Key Value) (Env Value) (Key × List Value)))
    (initial : SemiNaive.Database (Key × List Value)) (n : Nat) :
    SemiNaive.semiNaive rules (view (admittedRows tupleDomain)) initial n =
      (SemiNaive.naive rules (view (admittedRows tupleDomain)) initial n,
       SemiNaive.naive rules (view (admittedRows tupleDomain)) initial (n + 1)) :=
  binder_iterations_equal (admittedRows tupleDomain) tupleDomain
    (admitted_rows_faithful tupleDomain) rules initial n

end Ascent.PositiveConsequence
