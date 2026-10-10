-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import AtomicBinding

/-!
Dense first-occurrence lowering and the callback-free in-place slot matcher.
Frames outside the known prefix may contain arbitrary stale values. Failure
keeps partial fresh writes, as in core/positive-plan.ss; it does not roll back.
The total frame function abstracts a sufficiently large native vector. Finite vector matching and head observation are now related to this model.
Native hash-map identity, actual compiled plan decoding and lawful native
scalar equality remain representation obligations.
-/

namespace Ascent.PositiveSlots

open AtomicBinding

inductive Action (Value : Type) where
  | fresh (slot : Nat)
  | bound (slot : Nat)
  | literal (value : Value)
  | wildcard
  deriving DecidableEq

variable {Value : Type}
abbrev Frame (Value : Type) := Nat → Value

def slot : Nat → List Nat → Option Nat
  | _, [] => none
  | name, first :: rest =>
      if name = first then some 0 else (slot name rest).map (· + 1)

def lower (term : Term Value) (names : List Nat) : Action Value × List Nat :=
  match term with
  | .literal value => (.literal value, names)
  | .wildcard => (.wildcard, names)
  | .variable name => match slot name names with
    | some index => (.bound index, names)
    | none => (.fresh names.length, names ++ [name])

def compile : List (Term Value) → List Nat → List (Action Value) × List Nat
  | [], names => ([], names)
  | term :: rest, names =>
      let next := lower term names
      let tail := compile rest next.2
      (next.1 :: tail.1, tail.2)

def write (frame : Frame Value) (index : Nat) (value : Value) : Frame Value :=
  fun key => if key = index then value else frame key

def run [DecidableEq Value] : List (Action Value) → List Value → Frame Value → Bool × Frame Value
  | [], _, frame => (true, frame)
  | _ :: _, [], frame => (false, frame)
  | action :: rest, value :: tail, frame =>
      match action with
      | .fresh index => run rest tail (write frame index value)
      | .bound index => if frame index = value then run rest tail frame else (false, frame)
      | .literal expected => if expected = value then run rest tail frame else (false, frame)
      | .wildcard => run rest tail frame

def Represents (names : List Nat) (env : Env Value) (frame : Frame Value) : Prop :=
  ∀ name, lookup name env = (slot name names).map frame

def PrefixEq (count : Nat) (before after : Frame Value) : Prop :=
  ∀ index, index < count → after index = before index

theorem slot_lt (name : Nat) (names : List Nat) (index : Nat)
    (found : slot name names = some index) : index < names.length := by
  induction names generalizing index with
  | nil => simp [slot] at found
  | cons first rest ih =>
      simp only [slot] at found
      split at found
      · cases found; simp
      · cases next : slot name rest with
        | none => simp [next] at found
        | some previous =>
            simp only [next, Option.map_some, Option.some.injEq] at found
            subst index
            have := ih previous next
            simpa using Nat.succ_lt_succ this

theorem slot_append (name fresh : Nat) (names : List Nat) :
    slot name (names ++ [fresh]) =
      match slot name names with
      | some index => some index
      | none => if name = fresh then some names.length else none := by
  induction names with
  | nil => simp [slot]
  | cons first rest ih =>
      by_cases same : name = first
      · simp [slot, same]
      · simp only [List.cons_append, slot, same, ↓reduceIte, ih]
        cases slot name rest <;> by_cases last : name = fresh <;> simp [last]

theorem represents_write (names : List Nat) (env : Env Value) (frame : Frame Value)
    (rep : Represents names env frame) (fresh : Nat) (value : Value)
    (absent : slot fresh names = none) :
    Represents (names ++ [fresh]) ((fresh, value) :: env)
      (write frame names.length value) := by
  intro name
  rw [lookup, slot_append]
  by_cases same : name = fresh
  · subst name
    simp [absent, write]
  · simp only [same, ↓reduceIte]
    cases found : slot name names with
    | none => simpa [found, same] using rep name
    | some index =>
        have bound := slot_lt name names index found
        have different : index ≠ names.length := by omega
        simpa [found, write, different] using rep name

theorem represents_prefix (names : List Nat) (env : Env Value)
    (before after : Frame Value) (rep : Represents names env before)
    (same : PrefixEq names.length before after) : Represents names env after := by
  intro name
  rw [rep name]
  cases found : slot name names with
  | none => rfl
  | some index =>
      simp only [Option.map_some]
      exact congrArg some (same index (slot_lt name names index found)).symm

def FreshAbove (count : Nat) (actions : List (Action Value)) : Prop :=
  ∀ index, Action.fresh index ∈ actions → count ≤ index

theorem lower_length (term : Term Value) (names : List Nat) :
    names.length ≤ (lower term names).2.length := by
  cases term <;> simp only [lower]
  · exact Nat.le_refl _
  · cases slot _ names <;> simp
  · exact Nat.le_refl _

theorem compile_length (terms : List (Term Value)) (names : List Nat) :
    names.length ≤ (compile terms names).2.length := by
  induction terms generalizing names with
  | nil => exact Nat.le_refl _
  | cons term rest ih => exact Nat.le_trans (lower_length term names) (ih _)

def Action.InRange (count : Nat) : Action Value → Prop
  | .fresh index | .bound index => index < count
  | .literal _ | .wildcard => True

theorem compile_slots_bounded (terms : List (Term Value)) (names : List Nat) :
    ∀ action ∈ (compile terms names).1,
      action.InRange (compile terms names).2.length := by
  induction terms generalizing names with
  | nil => simp [compile]
  | cons term rest ih =>
      intro action member
      simp only [compile, List.mem_cons] at member
      simp only [compile]
      rcases member with first | later
      · subst action
        have extent := compile_length rest (lower term names).2
        cases term with
        | literal value => trivial
        | wildcard => trivial
        | «variable» name =>
            cases found : slot name names with
            | none =>
                simp only [lower, found, Action.InRange, List.length_append,
                  List.length_singleton] at extent ⊢
                omega
            | some index =>
                have limit := slot_lt name names index found
                simp only [lower, found] at extent
                simpa [lower, found, Action.InRange] using Nat.lt_of_lt_of_le limit extent
      · exact ih _ action later

theorem compile_fresh_above (terms : List (Term Value)) (names : List Nat) :
    FreshAbove names.length (compile terms names).1 := by
  induction terms generalizing names with
  | nil => simp [FreshAbove, compile]
  | cons term rest ih =>
      intro index member
      simp only [compile, List.mem_cons] at member
      rcases member with first | later
      · cases term with
        | literal value => simp [lower] at first
        | wildcard => simp [lower] at first
        | «variable» name =>
            cases found : slot name names <;> simp [lower, found] at first
            omega
      · exact Nat.le_trans (lower_length term names) (ih _ index later)

/-- Every failure path preserves the pre-existing initialized prefix. New
slots may retain writes from a rejected candidate. -/
theorem run_preserves_prefix [DecidableEq Value] (actions : List (Action Value))
    (row : List Value) (frame : Frame Value) (count : Nat)
    (safe : FreshAbove count actions) : PrefixEq count frame (run actions row frame).2 := by
  induction actions generalizing row frame with
  | nil => intro index _; rfl
  | cons action rest ih =>
      have tailSafe : FreshAbove count rest :=
        fun index member => safe index (List.mem_cons_of_mem action member)
      cases row with
      | nil => intro index _; rfl
      | cons value tail =>
          cases action with
          | fresh index =>
              have limit := safe index List.mem_cons_self
              have kept := ih tail (write frame index value) tailSafe
              intro key bound
              have different : key ≠ index := by omega
              simpa [run, write, different] using kept key bound
          | bound index =>
              by_cases sameValue : frame index = value
              · simpa [run, sameValue] using ih tail frame tailSafe
              · intro key _; simp [run, sameValue]
          | literal expected =>
              by_cases sameValue : expected = value
              · simpa [run, sameValue] using ih tail frame tailSafe
              · intro key _; simp [run, sameValue]
          | wildcard => exact ih tail frame tailSafe

/-- Dense lowering agrees with ordinary association-list binding. A success
represents the complete extended environment; prior stale frame contents do
not affect the Boolean result. Arity is an admission premise. -/
theorem compiled_binding [DecidableEq Value] (terms : List (Term Value))
    (row : List Value) (names : List Nat) (env : Env Value) (frame : Frame Value)
    (arity : terms.length = row.length) (rep : Represents names env frame) :
    (run (compile terms names).1 row frame).1 = (AtomicBinding.bind terms row env).isSome ∧
    ∀ output, AtomicBinding.bind terms row env = some output →
      Represents (compile terms names).2 output (run (compile terms names).1 row frame).2 := by
  induction terms generalizing row names env frame with
  | nil =>
      cases row with
      | nil =>
          constructor
          · rfl
          · intro output success
            have same : env = output := by simpa [AtomicBinding.bind] using success
            subst output
            exact rep
      | cons _ _ => simp at arity
  | cons term rest ih =>
      cases row with
      | nil => simp at arity
      | cons value tail =>
          have tailArity : rest.length = tail.length := by simpa using arity
          cases term with
          | wildcard => simpa [compile, lower, run, AtomicBinding.bind] using ih tail names env frame tailArity rep
          | literal expected =>
              by_cases sameValue : expected = value
              · simpa [compile, lower, run, AtomicBinding.bind, sameValue] using ih tail names env frame tailArity rep
              · simp [compile, lower, run, AtomicBinding.bind, sameValue]
          | «variable» name =>
              cases found : slot name names with
              | none =>
                  have absent : lookup name env = none := by simpa [found] using rep name
                  have nextRep := represents_write names env frame rep name value found
                  simpa [compile, lower, run, AtomicBinding.bind, found, absent] using
                    ih tail (names ++ [name]) ((name, value) :: env)
                      (write frame names.length value) tailArity nextRep
              | some index =>
                  have bound : lookup name env = some (frame index) := by
                    simpa [found] using rep name
                  by_cases sameValue : frame index = value
                  · simpa [compile, lower, run, AtomicBinding.bind, found, bound, sameValue] using
                      ih tail names env frame tailArity rep
                  · simp [compile, lower, run, AtomicBinding.bind, found, bound, sameValue]

/-- Reusing a frame after any candidate, including a failed partial write,
still represents the original input environment at the next candidate. -/
theorem candidate_reuse [DecidableEq Value] (terms : List (Term Value))
    (row : List Value) (names : List Nat) (env : Env Value) (frame : Frame Value)
    (rep : Represents names env frame) :
    Represents names env (run (compile terms names).1 row frame).2 :=
  represents_prefix names env frame _ rep
    (run_preserves_prefix _ row frame names.length (compile_fresh_above terms names))

def observeHead (terms : List (Term Value)) (env : Env Value) : List (Option Value) :=
  terms.map (wanted env)

def observeSlots (terms : List (Term Value)) (names : List Nat)
    (frame : Frame Value) : List (Option Value) :=
  terms.map fun term => match term with
    | .literal value => some value
    | .variable name => (slot name names).map frame
    | .wildcard => none

/-- Declared bound variables and literals have identical ordered head values.
Wildcard/unbound outputs remain explicit `none`, outside native admission. -/
theorem head_observations (terms : List (Term Value)) (names : List Nat)
    (env : Env Value) (frame : Frame Value) (rep : Represents names env frame) :
    observeHead terms env = observeSlots terms names frame := by
  apply List.map_congr_left
  intro term _
  cases term with
  | literal value => rfl
  | wildcard => rfl
  | «variable» name => exact rep name

/-- The success branch supplies the same head observations as ordinary binding.
This is the emission boundary used by the positive traversal's continuation. -/
theorem compiled_head [DecidableEq Value] (terms outputs : List (Term Value))
    (row : List Value) (names : List Nat) (env result : Env Value) (frame : Frame Value)
    (arity : terms.length = row.length) (rep : Represents names env frame)
    (success : AtomicBinding.bind terms row env = some result) :
    (run (compile terms names).1 row frame).1 = true ∧
    observeHead outputs result = observeSlots outputs (compile terms names).2
      (run (compile terms names).1 row frame).2 := by
  have refined := compiled_binding terms row names env frame arity rep
  exact ⟨by simpa [success] using refined.1,
    head_observations outputs _ result _ (refined.2 result success)⟩

/- Finite vectors discharge the infinite-frame representation premise. Bounds
failure is separate from candidate mismatch; admitted compiled actions never
take that failure branch. Scalar equality and equal-arity native rows remain
separate decoding premises. -/
def VectorRep {n : Nat} (frame : Frame Value) (vector : Vector Value n) : Prop :=
  ∀ index (inside : index < n), vector[index] = frame index

/-- Extend a finite caller frame without imposing any value on unused cells. -/
def vectorFrame {n : Nat} (vector : Vector Value n) (outside : Value) : Frame Value :=
  fun index => if inside : index < n then vector[index] else outside

theorem vector_frame_rep {n : Nat} (vector : Vector Value n) (outside : Value) :
    VectorRep (vectorFrame vector outside) vector := by
  intro index inside
  simp [vectorFrame, inside]

def runVector [DecidableEq Value] {n : Nat} :
    List (Action Value) → List Value → Vector Value n → Option (Bool × Vector Value n)
  | [], _, vector => some (true, vector)
  | _ :: _, [], vector => some (false, vector)
  | action :: rest, value :: tail, vector =>
      match action with
      | .fresh index =>
          if inside : index < n then runVector rest tail (vector.set index value inside) else none
      | .bound index =>
          if inside : index < n then
            if vector[index] = value then runVector rest tail vector else some (false, vector)
          else none
      | .literal expected =>
          if expected = value then runVector rest tail vector else some (false, vector)
      | .wildcard => runVector rest tail vector

theorem vector_write_rep {n : Nat} (frame : Frame Value) (vector : Vector Value n)
    (rep : VectorRep frame vector) (index : Nat) (inside : index < n) (value : Value) :
    VectorRep (write frame index value) (vector.set index value inside) := by
  intro key bounded
  rw [Vector.getElem_set]
  by_cases same : key = index
  · subst key; simp [write]
  · simp [write, same, Ne.symm same, rep key bounded]

/-- Every native vector read/write is in bounds, and all cells (including dirty
cells left by failed candidates) refine the existing function-frame semantics. -/
theorem vector_run_refines [DecidableEq Value] {n : Nat}
    (actions : List (Action Value)) (row : List Value) (frame : Frame Value)
    (vector : Vector Value n) (rep : VectorRep frame vector)
    (bounded : ∀ action ∈ actions, action.InRange n) :
    ∃ result, runVector actions row vector = some result ∧
      result.1 = (run actions row frame).1 ∧ VectorRep (run actions row frame).2 result.2 := by
  induction actions generalizing row frame vector with
  | nil => exact ⟨(true, vector), rfl, rfl, rep⟩
  | cons action rest ih =>
      have tailBound : ∀ a ∈ rest, a.InRange n :=
        fun a member => bounded a (List.mem_cons_of_mem action member)
      cases row with
      | nil => exact ⟨(false, vector), rfl, rfl, rep⟩
      | cons value tail =>
          cases action with
          | fresh index =>
              have inside : index < n := bounded (.fresh index) List.mem_cons_self
              simpa [runVector, run, Action.InRange, inside] using
                ih tail (write frame index value) (vector.set index value inside)
                  (vector_write_rep frame vector rep index inside value) tailBound
          | bound index =>
              have inside : index < n := bounded (.bound index) List.mem_cons_self
              have sameCell := rep index inside
              by_cases same : frame index = value
              · simpa [runVector, run, Action.InRange, inside, sameCell, same] using
                  ih tail frame vector rep tailBound
              · exact ⟨(false, vector), by simp [runVector, inside, sameCell, same],
                  by simp [run, same], by simpa [run, same] using rep⟩
          | literal expected =>
              by_cases same : expected = value
              · simpa [runVector, run, same] using ih tail frame vector rep tailBound
              · exact ⟨(false, vector), by simp [runVector, same],
                  by simp [run, same], by simpa [run, same] using rep⟩
          | wildcard => exact ih tail frame vector rep tailBound

theorem compiled_vector_refines [DecidableEq Value] (terms : List (Term Value))
    {n : Nat} (names : List Nat) (row : List Value) (frame : Frame Value)
    (vector : Vector Value n) (rep : VectorRep frame vector)
    (extent : (compile terms names).2.length ≤ n) :
    ∃ result, runVector (compile terms names).1 row vector = some result ∧
      result.1 = (run (compile terms names).1 row frame).1 ∧
      VectorRep (run (compile terms names).1 row frame).2 result.2 :=
by
  apply vector_run_refines _ row frame vector rep
  intro action member
  have bounded := compile_slots_bounded terms names action member
  cases action <;> simp only [Action.InRange] at bounded ⊢
  · exact Nat.lt_of_lt_of_le bounded extent
  · exact Nat.lt_of_lt_of_le bounded extent

/-- Finite head observations read only the declared name prefix. Missing or
wildcard outputs remain explicit none, matching the existing head boundary. -/
def observeVectorSlots {n : Nat} (terms : List (Term Value)) (names : List Nat)
    (vector : Vector Value n) : List (Option Value) :=
  terms.map fun term => match term with
    | .literal value => some value
    | .variable name => (slot name names).bind (fun index => vector[index]?)
    | .wildcard => none

theorem vector_head_observations {n : Nat} (terms : List (Term Value))
    (names : List Nat) (frame : Frame Value) (vector : Vector Value n)
    (rep : VectorRep frame vector) (extent : names.length ≤ n) :
    observeVectorSlots terms names vector = observeSlots terms names frame := by
  apply List.map_congr_left
  intro term _
  cases term with
  | literal value => rfl
  | wildcard => rfl
  | «variable» name =>
      cases found : slot name names with
      | none => simp [found]
      | some index =>
          have inside := Nat.lt_of_lt_of_le (slot_lt name names index found) extent
          simp [found, inside, rep index inside]

theorem vector_represents {n : Nat} (names : List Nat) (env : Env Value)
    (frame : Frame Value) (vector : Vector Value n) (outside : Value)
    (represented : Represents names env frame) (rep : VectorRep frame vector)
    (extent : names.length ≤ n) : Represents names env (vectorFrame vector outside) := by
  intro name
  rw [represented name]
  cases found : slot name names with
  | none => rfl
  | some index =>
      have inside := Nat.lt_of_lt_of_le (slot_lt name names index found) extent
      simp [vectorFrame, inside, rep index inside]

/-- Head lowering admits only literals and variables already present in the
compiled body scope. It never allocates a fresh slot. -/
def lowerHead (term : Term Value) (names : List Nat) : Option (Action Value) :=
  match term with
  | .literal value => some (.literal value)
  | .variable name => (slot name names).map Action.bound
  | .wildcard => none

def compileHead : List (Term Value) → List Nat → Option (List (Action Value))
  | [], _ => some []
  | term :: terms, names => do
      let action ← lowerHead term names
      let rest ← compileHead terms names
      pure (action :: rest)

/-- Decode the stored literal/bound head actions as finite values, refusing
missing cells or body-only constructors instead of silently emitting a row. -/
def readHeadVector {n : Nat} : List (Action Value) → Vector Value n → Option (List Value)
  | [], _ => some []
  | .literal value :: rest, vector => (readHeadVector rest vector).map (value :: ·)
  | .bound index :: rest, vector => do
      let value ← vector[index]?
      let tail ← readHeadVector rest vector
      pure (value :: tail)
  | _ :: _, _ => none

theorem compiled_head_vector_refines {n : Nat} (terms : List (Term Value))
    (names : List Nat) (vector : Vector Value n) :
    (compileHead terms names).bind (fun actions => readHeadVector actions vector) =
      (observeVectorSlots terms names vector).mapM id := by
  induction terms with
  | nil => rfl
  | cons term terms ih =>
      cases term with
      | literal value =>
          change _ = (some value :: observeVectorSlots terms names vector).mapM id
          rw [List.mapM_cons]
          simp only [id_eq, Option.bind_some]
          rw [← ih]
          cases tail : compileHead terms names with
          | none => simp [compileHead, lowerHead, tail]
          | some actions =>
              cases values : readHeadVector actions vector <;>
                simp [compileHead, lowerHead, readHeadVector, tail, values]
      | wildcard =>
          change _ = (none :: observeVectorSlots terms names vector).mapM id
          simp [compileHead, lowerHead]
      | «variable» name =>
          change _ = ((slot name names).bind (fun index => vector[index]?) ::
            observeVectorSlots terms names vector).mapM id
          rw [List.mapM_cons, ← ih]
          cases found : slot name names <;>
            cases tail : compileHead terms names <;>
              simp [compileHead, lowerHead, readHeadVector, found, tail]

/-- Stored output actions read precisely the ordinary declared head under the
same represented environment, with no allocation or fresh-cell observation. -/
theorem compiled_head_binding_refines {n : Nat} (terms : List (Term Value))
    (names : List Nat) (env : Env Value) (frame : Frame Value)
    (vector : Vector Value n) (represented : Represents names env frame)
    (rep : VectorRep frame vector) (extent : names.length ≤ n) :
    (compileHead terms names).bind (fun actions => readHeadVector actions vector) =
      (observeHead terms env).mapM id := by
  rw [compiled_head_vector_refines,
    vector_head_observations terms names frame vector rep extent,
    head_observations terms names env frame represented]

end Ascent.PositiveSlots
