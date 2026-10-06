-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveSlots

/-! Raw-row positive traversal. Candidate failure and recursive return both
thread the dirty frame into the next candidate, with no rollback. The provider
is a fixed finite row list per atom. The finite-vector traversal below refines
the same computation; indexes, delta selection and native plan decoding remain
separate obligations. -/
namespace Ascent.PositiveTraversal
open AtomicBinding PositiveSlots
variable {Value Output : Type} [DecidableEq Value]
abbrev Result (Value Output : Type) := List Output × Frame Value

def scan (actions : List (Action Value))
    (next : Frame Value → Result Value Output) : List (List Value) → Frame Value → Result Value Output
  | [], frame => ([], frame)
  | row :: rows, frame =>
      let matched := run actions row frame
      let branch := if matched.1 then next matched.2 else ([], matched.2)
      let rest := scan actions next rows branch.2
      (branch.1 ++ rest.1, rest.2)

omit [DecidableEq Value] in
theorem prefix_trans (count : Nat) (a b c : Frame Value)
    (ab : PrefixEq count a b) (bc : PrefixEq count b c) : PrefixEq count a c :=
  fun index bound => (bc index bound).trans (ab index bound)

omit [DecidableEq Value] in
theorem prefix_weaken (small large : Nat) (a b : Frame Value)
    (order : small ≤ large) (same : PrefixEq large a b) : PrefixEq small a b :=
  fun index bound => same index (Nat.lt_of_lt_of_le bound order)

theorem scan_prefix (actions : List (Action Value))
    (next : Frame Value → Result Value Output) (rows : List (List Value))
    (count : Nat) (safe : FreshAbove count actions)
    (kept : ∀ frame, PrefixEq count frame (next frame).2) (frame : Frame Value) :
    PrefixEq count frame (scan actions next rows frame).2 := by
  induction rows generalizing frame with
  | nil => intro index _; rfl
  | cons row rows ih =>
      have matched := run_preserves_prefix actions row frame count safe
      simp only [scan]
      split
      · exact prefix_trans count frame _ _
          (prefix_trans count frame _ _ matched (kept _)) (ih _)
      · exact prefix_trans count frame _ _ matched (ih _)

/-- A continuation may leave arbitrary newer slots dirty. Its only frame
obligation is to preserve the parent prefix; output equality is proved for
successful bindings, without consulting failed candidate contents. -/
theorem scan_refines (terms : List (Term Value)) (names : List Nat)
    (env : Env Value) (rows : List (List Value))
    (next : Frame Value → Result Value Output) (reference : Env Value → List Output)
    (arity : ∀ row ∈ rows, terms.length = row.length)
    (kept : ∀ frame, PrefixEq names.length frame (next frame).2)
    (refined : ∀ output frame, Represents (compile terms names).2 output frame →
      (next frame).1 = reference output)
    (frame : Frame Value) (rep : Represents names env frame) :
    (scan (compile terms names).1 next rows frame).1 =
      rows.flatMap (fun row => match AtomicBinding.bind terms row env with
        | none => [] | some output => reference output) := by
  induction rows generalizing frame with
  | nil => rfl
  | cons row rows ih =>
      have binding := compiled_binding terms row names env frame (arity row List.mem_cons_self) rep
      have reuse := candidate_reuse terms row names env frame rep
      have tailArity : ∀ row ∈ rows, terms.length = row.length :=
        fun candidate member => arity candidate (List.mem_cons_of_mem row member)
      cases found : AtomicBinding.bind terms row env with
      | none =>
          have failed : (run (compile terms names).1 row frame).1 = false := by
            simpa [found] using binding.1
          simpa [scan, failed, found] using ih tailArity _ reuse
      | some output =>
          have passed : (run (compile terms names).1 row frame).1 = true := by
            simpa [found] using binding.1
          have emits := refined output _ (binding.2 output found)
          have returned := represents_prefix names env _ _ reuse (kept _)
          have tail := ih tailArity _ returned
          simp only [scan, passed, ↓reduceIte, List.flatMap_cons, found]
          rw [emits, tail]

structure Atom (Value : Type) where
  terms : List (Term Value)
  rows : List (List Value)

/-- Compilation is deterministic at each body position. The names passed to
its suffix are the compiler's complete names after the current atom. -/
def walk (body : List (Atom Value)) (names : List Nat)
    (emit : List Nat → Frame Value → List Output) (frame : Frame Value) : Result Value Output :=
  match body with
  | [] => (emit names frame, frame)
  | atom :: rest =>
      let lowered := compile atom.terms names
      scan lowered.1 (walk rest lowered.2 emit) atom.rows frame

def reference (body : List (Atom Value)) (emit : Env Value → List Output)
    (env : Env Value) : List Output :=
  match body with
  | [] => emit env
  | atom :: rest => atom.rows.flatMap fun row =>
      match AtomicBinding.bind atom.terms row env with
      | none => [] | some output => reference rest emit output

def Arity (body : List (Atom Value)) : Prop :=
  ∀ atom ∈ body, ∀ row ∈ atom.rows, atom.terms.length = row.length

theorem walk_prefix (body : List (Atom Value)) (names : List Nat)
    (emit : List Nat → Frame Value → List Output) (frame : Frame Value) :
    PrefixEq names.length frame (walk body names emit frame).2 := by
  induction body generalizing names frame with
  | nil => intro index _; rfl
  | cons atom rest ih =>
      apply scan_prefix
      · exact compile_fresh_above atom.terms names
      · intro candidate
        exact prefix_weaken _ _ _ _ (compile_length atom.terms names) (ih _ candidate)

/-- Full ordered traversal correspondence, including nested success returns,
failed partial writes, duplicate emissions and reuse of a dirty frame. -/
theorem walk_refines (body : List (Atom Value))
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (arity : Arity body) (names : List Nat) (env : Env Value) (frame : Frame Value)
    (rep : Represents names env frame) :
    (walk body names slotEmit frame).1 = reference body envEmit env := by
  induction body generalizing names env frame with
  | nil => exact emits names env frame rep
  | cons atom rest ih =>
      apply scan_refines atom.terms names env atom.rows
      · exact arity atom List.mem_cons_self
      · intro candidate
        exact prefix_weaken _ _ _ _ (compile_length atom.terms names)
          (walk_prefix rest _ slotEmit candidate)
      · intro output candidate represented
        exact ih (fun next member => arity next (List.mem_cons_of_mem atom member)) _ _ _ represented
      · exact rep

theorem walk_reuse (body : List (Atom Value)) (names : List Nat) (env : Env Value)
    (emit : List Nat → Frame Value → List Output) (frame : Frame Value)
    (rep : Represents names env frame) : Represents names env (walk body names emit frame).2 :=
  represents_prefix names env frame _ rep (walk_prefix body names emit frame)

structure SlotAtom (Value : Type) where
  actions : List (Action Value)
  rows : List (List Value)

def compileBody : List (Atom Value) → List Nat → List (SlotAtom Value) × List Nat
  | [], names => ([], names)
  | atom :: rest, names =>
      let lowered := compile atom.terms names
      let tail := compileBody rest lowered.2
      (⟨lowered.1, atom.rows⟩ :: tail.1, tail.2)

def runBody (body : List (SlotAtom Value)) (finalNames : List Nat)
    (emit : List Nat → Frame Value → List Output) (frame : Frame Value) : Result Value Output :=
  match body with
  | [] => (emit finalNames frame, frame)
  | atom :: rest => scan atom.actions (runBody rest finalNames emit) atom.rows frame

/-- Precompiling once and then traversing the stored actions is exactly the
same computation as position-wise deterministic lowering. -/
theorem precompiled_walk (body : List (Atom Value)) (names : List Nat)
    (emit : List Nat → Frame Value → List Output) :
    runBody (compileBody body names).1 (compileBody body names).2 emit =
      walk body names emit := by
  induction body generalizing names with
  | nil => rfl
  | cons atom rest ih =>
      simp only [compileBody, runBody, walk]
      rw [ih]

theorem precompiled_refines (body : List (Atom Value))
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (arity : Arity body) (names : List Nat) (env : Env Value) (frame : Frame Value)
    (rep : Represents names env frame) :
    (runBody (compileBody body names).1 (compileBody body names).2 slotEmit frame).1 =
      reference body envEmit env := by
  rw [precompiled_walk]
  exact walk_refines body slotEmit envEmit emits arity names env frame rep

/-! Finite mutable-frame correspondence for complete precompiled traversal.
Bounds failure remains distinct from a candidate mismatch. Every recursive
return, including partial writes on rejection, threads the actual vector. -/
abbrev VectorResult (Value Output : Type) (n : Nat) := List Output × Vector Value n

def ResultRep {n : Nat} (reference : Result Value Output)
    (actual : VectorResult Value Output n) : Prop :=
  actual.1 = reference.1 ∧ VectorRep reference.2 actual.2

def scanVector {n : Nat} (actions : List (Action Value))
    (next : Vector Value n → Option (VectorResult Value Output n)) :
    List (List Value) → Vector Value n → Option (VectorResult Value Output n)
  | [], frame => some ([], frame)
  | row :: rows, frame => do
      let matched ← runVector actions row frame
      let branch ← if matched.1 then next matched.2 else some ([], matched.2)
      let rest ← scanVector actions next rows branch.2
      pure (branch.1 ++ rest.1, rest.2)

theorem scan_vector_refines {n : Nat} (actions : List (Action Value))
    (next : Frame Value → Result Value Output)
    (vectorNext : Vector Value n → Option (VectorResult Value Output n))
    (bounded : ∀ action ∈ actions, action.InRange n)
    (continues : ∀ frame vector, VectorRep frame vector →
      ∃ result, vectorNext vector = some result ∧ ResultRep (next frame) result)
    (rows : List (List Value)) (frame : Frame Value) (vector : Vector Value n)
    (rep : VectorRep frame vector) :
    ∃ result, scanVector actions vectorNext rows vector = some result ∧
      ResultRep (scan actions next rows frame) result := by
  induction rows generalizing frame vector with
  | nil => exact ⟨([], vector), rfl, rfl, rep⟩
  | cons row rows ih =>
      obtain ⟨matched, matchedRun, accepted, matchedRep⟩ :=
        vector_run_refines actions row frame vector rep bounded
      cases success : (run actions row frame).1 with
      | false =>
          have failed : matched.1 = false := accepted.trans success
          obtain ⟨tail, tailRun, tailRep⟩ := ih (run actions row frame).2 matched.2 matchedRep
          refine ⟨tail, ?_, ?_⟩
          · simp [scanVector, matchedRun, failed, tailRun]
          · simpa [scan, success, ResultRep] using tailRep
      | true =>
          have passed : matched.1 = true := accepted.trans success
          obtain ⟨branch, branchRun, branchRep⟩ := continues _ _ matchedRep
          obtain ⟨tail, tailRun, tailRep⟩ := ih (next (run actions row frame).2).2 branch.2 branchRep.2
          refine ⟨(branch.1 ++ tail.1, tail.2), ?_, ?_⟩
          · simp [scanVector, matchedRun, passed, branchRun, tailRun]
          · constructor
            · simp only [scan, success, ↓reduceIte]
              rw [branchRep.1, tailRep.1]
            · simpa [scan, success] using tailRep.2

def runBodyVector {n : Nat} (body : List (SlotAtom Value)) (finalNames : List Nat)
    (emit : List Nat → Vector Value n → List Output) :
    Vector Value n → Option (VectorResult Value Output n) :=
  match body with
  | [] => fun frame => some (emit finalNames frame, frame)
  | atom :: rest => scanVector atom.actions (runBodyVector rest finalNames emit) atom.rows

def BodyBounds (n : Nat) (body : List (SlotAtom Value)) : Prop :=
  ∀ atom ∈ body, ∀ action ∈ atom.actions, action.InRange n

theorem body_vector_refines {n : Nat} (body : List (SlotAtom Value))
    (finalNames : List Nat) (emit : List Nat → Frame Value → List Output)
    (vectorEmit : List Nat → Vector Value n → List Output)
    (emits : ∀ frame vector, VectorRep frame vector →
      vectorEmit finalNames vector = emit finalNames frame)
    (bounded : BodyBounds n body) (frame : Frame Value) (vector : Vector Value n)
    (rep : VectorRep frame vector) :
    ∃ result, runBodyVector body finalNames vectorEmit vector = some result ∧
      ResultRep (runBody body finalNames emit frame) result := by
  induction body generalizing frame vector with
  | nil => exact ⟨(vectorEmit finalNames vector, vector), rfl, emits _ _ rep, rep⟩
  | cons atom rest ih =>
      apply scan_vector_refines atom.actions (runBody rest finalNames emit)
      · exact bounded atom List.mem_cons_self
      · intro candidate actual represented
        exact ih (fun a member => bounded a (List.mem_cons_of_mem atom member)) candidate actual represented
      · exact rep

omit [DecidableEq Value] in
theorem compile_body_length (body : List (Atom Value)) (names : List Nat) :
    names.length ≤ (compileBody body names).2.length := by
  induction body generalizing names with
  | nil => exact Nat.le_refl _
  | cons atom rest ih =>
      exact Nat.le_trans (compile_length atom.terms names) (ih _)

omit [DecidableEq Value] in
theorem compile_body_bounds (body : List (Atom Value)) (names : List Nat) :
    BodyBounds (compileBody body names).2.length (compileBody body names).1 := by
  induction body generalizing names with
  | nil => intro atom member; cases member
  | cons atom rest ih =>
      intro compiled member action present
      simp only [compileBody] at member ⊢
      rcases List.mem_cons.mp member with head | tail
      · subst compiled
        have slotBound := compile_slots_bounded atom.terms names action present
        have extent := compile_body_length rest (compile atom.terms names).2
        cases action <;> simp only [Action.InRange] at slotBound ⊢
        · exact Nat.lt_of_lt_of_le slotBound extent
        · exact Nat.lt_of_lt_of_le slotBound extent
      · exact ih _ compiled tail action present

/-- Complete finite traversal composes with ordinary binding: the emitted list
is equal in order and multiplicity, and every returned vector cell represents
the actual dirty function-frame return. No successful-completion premise is
assumed for this structurally finite traversal. -/
theorem finite_precompiled_refines {n : Nat} (body : List (Atom Value))
    (slotEmit : List Nat → Frame Value → List Output)
    (vectorEmit : List Nat → Vector Value n → List Output)
    (envEmit : Env Value → List Output) (names : List Nat)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (vectorEmits : ∀ frame vector, VectorRep frame vector →
      vectorEmit (compileBody body names).2 vector = slotEmit (compileBody body names).2 frame)
    (arity : Arity body) (env : Env Value)
    (frame : Frame Value) (vector : Vector Value n)
    (rep : Represents names env frame) (vectorRep : VectorRep frame vector)
    (extent : (compileBody body names).2.length ≤ n) :
    ∃ result, runBodyVector (compileBody body names).1 (compileBody body names).2 vectorEmit vector = some result ∧
      result.1 = reference body envEmit env ∧
      VectorRep (runBody (compileBody body names).1 (compileBody body names).2 slotEmit frame).2 result.2 ∧
      ∀ outside, Represents names env (vectorFrame result.2 outside) := by
  have bounded : BodyBounds n (compileBody body names).1 := by
    intro atom member action present
    have slotBound := compile_body_bounds body names atom member action present
    cases action <;> simp only [Action.InRange] at slotBound ⊢
    · exact Nat.lt_of_lt_of_le slotBound extent
    · exact Nat.lt_of_lt_of_le slotBound extent
  obtain ⟨result, actual, represented⟩ := body_vector_refines _ _ slotEmit vectorEmit
    vectorEmits bounded frame vector vectorRep
  have kept : Represents names env
      (runBody (compileBody body names).1 (compileBody body names).2 slotEmit frame).2 := by
    rw [precompiled_walk]
    exact walk_reuse body names env slotEmit frame rep
  exact ⟨result, actual,
    represented.1.trans (precompiled_refines body slotEmit envEmit emits arity names env frame rep),
    represented.2, fun outside => vector_represents names env _ result.2 outside kept
      represented.2 (Nat.le_trans (compile_body_length body names) extent)⟩

end Ascent.PositiveTraversal
