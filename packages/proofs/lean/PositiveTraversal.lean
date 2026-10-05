-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveSlots

/-! Raw-row positive traversal. Candidate failure and recursive return both
thread the dirty frame into the next candidate, with no rollback. The provider
is a fixed finite row list per atom; indexes, delta selection and native vector
representation remain separate obligations. -/
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

end Ascent.PositiveTraversal
