-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PositiveTraversal
import ProviderFrontier

/-! Ordered physical bucket selection and per-occurrence delta lanes are
composed with the dirty-slot traversal. Canonical buckets retain source order;
custom providers may reorder candidates. ProviderAdmission proves their checked
key-matching occurrence counts; ordered callback traces additionally require a
receiver-order premise. Snapshots remain fixed throughout a traversal. -/
namespace Ascent.IndexedPositiveTraversal
open AtomicBinding PositiveSlots PositiveTraversal
variable {Value Output : Type} [DecidableEq Value]

def envKey (terms : List (Term Value)) (columns : List Nat) (env : Env Value) :
    List (Option Value) := columns.map fun i => terms[i]?.bind (wanted env)
def frameKey (terms : List (Term Value)) (columns names : List Nat) (frame : Frame Value) :
    List (Option Value) := columns.map fun i => terms[i]?.bind fun term =>
      match term with
      | .literal value => some value
      | .variable name => (slot name names).map frame
      | .wildcard => none
def projectedKey (columns : List Nat) (row : List Value) : List (Option Value) :=
  columns.map fun i => row[i]?
def KnownColumns (terms : List (Term Value)) (columns : List Nat) (env : Env Value) : Prop :=
  ∀ i ∈ columns, ∃ term value, terms[i]? = some term ∧ wanted env term = some value

omit [DecidableEq Value] in
theorem key_refines (terms : List (Term Value)) (columns names : List Nat)
    (env : Env Value) (frame : Frame Value) (rep : Represents names env frame) :
    frameKey terms columns names frame = envKey terms columns env := by
  apply List.map_congr_left
  intro i _
  cases terms[i]? with
  | none => rfl
  | some term =>
      cases term with
      | literal value => rfl
      | wildcard => rfl
      | «variable» name => exact (rep name).symm

def Indexable (names : List Nat) : Term Value → Prop
  | .literal _ => True
  | .variable name => (slot name names).isSome = true
  | .wildcard => False

omit [DecidableEq Value] in
theorem slot_lower (term : Term Value) (names : List Nat) (name index : Nat)
    (found : slot name names = some index) : slot name (lower term names).2 = some index := by
  cases term with
  | literal value => exact found
  | wildcard => exact found
  | «variable» fresh =>
      cases atFresh : slot fresh names with
      | some previous => simpa [lower, atFresh] using found
      | none => simp [lower, atFresh, slot_append, found]

omit [DecidableEq Value] in
theorem lower_indexable (term previous : Term Value) (names : List Nat)
    (known : Indexable names term) :
    Indexable (lower previous names).2 term ∧ (lower term (lower previous names).2).1 = (lower term names).1 := by
  cases term with
  | literal value => exact ⟨trivial, rfl⟩
  | wildcard => contradiction
  | «variable» name =>
      cases found : slot name names with
      | none => simp [Indexable, found] at known
      | some index =>
          have preserved := slot_lower previous names name index found
          generalize nextEq : (lower previous names).2 = next at *
          exact ⟨by simp [Indexable, preserved], by simp [lower, preserved, found]⟩

omit [DecidableEq Value] in
theorem compile_known_at (terms : List (Term Value)) (names : List Nat) (i : Nat) (term : Term Value)
    (atTerm : terms[i]? = some term) (known : Indexable names term) :
    (compile terms names).1[i]? = some (lower term names).1 := by
  induction terms generalizing names i with
  | nil => simp at atTerm
  | cons previous rest ih =>
      cases i with
      | zero =>
          have same : previous = term := by simpa using atTerm
          subst previous; rfl
      | succ i =>
          have tail : rest[i]? = some term := by simpa using atTerm
          have stable := lower_indexable term previous names known
          simpa [compile, stable.2] using ih (lower previous names).2 i tail stable.1

def actionValue (frame : Frame Value) : Action Value → Option Value
  | .literal value => some value
  | .fresh index | .bound index => some (frame index)
  | .wildcard => none

def compiledKey (terms : List (Term Value)) (columns names : List Nat) (frame : Frame Value) :
    List (Option Value) := columns.map fun i => (compile terms names).1[i]?.bind (actionValue frame)

omit [DecidableEq Value] in
/-- The physical key reads actual selected compiled actions. Known columns
cannot read fresh slots left over from previous candidates. -/
theorem compiled_key_refines (terms : List (Term Value)) (columns names : List Nat)
    (env : Env Value) (frame : Frame Value) (rep : Represents names env frame)
    (known : KnownColumns terms columns env) : compiledKey terms columns names frame = envKey terms columns env := by
  apply List.map_congr_left
  intro i member
  obtain ⟨term, value, located, wantedValue⟩ := known i member
  have readable : Indexable names term := by
    cases term with
    | literal expected => trivial
    | wildcard => simp [wanted] at wantedValue
    | «variable» name =>
        have represented := rep name
        cases found : slot name names <;> simp_all [wanted, Indexable]
  have compiled := compile_known_at terms names i term located readable
  rw [compiled, located]
  cases term with
  | literal expected => rfl
  | wildcard => contradiction
  | «variable» name =>
      cases found : slot name names with
      | none => simp [Indexable, found] at readable
      | some index => simpa [lower, found, actionValue, wanted] using (rep name).symm

theorem bind_columns (terms : List (Term Value)) (columns : List Nat) (row : List Value)
    (env output : Env Value) (arity : terms.length = row.length)
    (known : KnownColumns terms columns env) (success : AtomicBinding.bind terms row env = some output) :
    projectedKey columns row = envKey terms columns env := by
  apply List.map_congr_left
  intro i member
  obtain ⟨term, expected, located, wantedValue⟩ := known i member
  have limit := (List.getElem?_eq_some_iff.mp located).1
  cases atRow : row[i]? with
  | none =>
      have outside := List.getElem?_eq_none_iff.mp atRow
      omega
  | some value =>
      have memberZip : (term, value) ∈ terms.zip row :=
        List.mem_of_getElem? (List.getElem?_zip_eq_some.mpr ⟨located, atRow⟩)
      have equal := matched_column terms row env output success term value expected memberZip wantedValue
      simp only [located, Option.bind_some, wantedValue]
      exact congrArg some equal

/-- Removing only rows whose binder fails preserves order and multiplicity. -/
theorem filter_binding (terms : List (Term Value)) (rows : List (List Value))
    (env : Env Value) (keep : List Value → Bool) (emit : Env Value → List Output)
    (complete : ∀ row ∈ rows, ∀ output, AtomicBinding.bind terms row env = some output → keep row = true) :
    (rows.filter keep).flatMap (fun row => match AtomicBinding.bind terms row env with
      | none => [] | some output => emit output) =
    rows.flatMap (fun row => match AtomicBinding.bind terms row env with
      | none => [] | some output => emit output) := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
      have tail := ih (fun r member => complete r (List.mem_cons_of_mem row member))
      cases found : AtomicBinding.bind terms row env with
      | none => cases kept : keep row <;> simp [kept, found, tail]
      | some output =>
          have kept := complete row List.mem_cons_self output found
          simp [kept, found, tail]

structure Atom (Value : Type) where
  terms : List (Term Value)
  columns : List Nat
  allRows : List (List Value)
  deltaRows : List (List Value)
  oldRows : List (List Value)

/-- Exactly one occurrence uses delta; absent/out-of-range pivots use all. -/
def lane (atom : Atom Value) (pivot : Option Nat) (depth : Nat) : List (List Value) :=
  if pivot = some depth then atom.deltaRows else atom.allRows

def selectedRows (atom : Atom Value) (pivot : Option Nat) (depth : Nat)
    (names : List Nat) (frame : Frame Value) : List (List Value) :=
  let rows := lane atom pivot depth
  if atom.columns.isEmpty || rows.length < 32 then rows else
    rows.filter fun row => decide (projectedKey atom.columns row = compiledKey atom.terms atom.columns names frame)

def walk (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat) (names : List Nat)
    (emit : List Nat → Frame Value → List Output) (frame : Frame Value) : Result Value Output :=
  match body with
  | [] => (emit names frame, frame)
  | atom :: rest =>
      let lowered := compile atom.terms names
      scan lowered.1 (walk rest pivot (depth + 1) lowered.2 emit)
        (selectedRows atom pivot depth names frame) frame

def rawBody (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat) : List (PositiveTraversal.Atom Value) :=
  match body with
  | [] => []
  | atom :: rest => ⟨atom.terms, lane atom pivot depth⟩ :: rawBody rest pivot (depth + 1)

def Admitted (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat) (names : List Nat) : Prop :=
  match body with
  | [] => True
  | atom :: rest =>
      (∀ row ∈ lane atom pivot depth, atom.terms.length = row.length) ∧
      (∀ env frame, Represents names env frame → KnownColumns atom.terms atom.columns env) ∧
      Admitted rest pivot (depth + 1) (compile atom.terms names).2

theorem walk_prefix (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat) (names : List Nat)
    (emit : List Nat → Frame Value → List Output) (frame : Frame Value) :
    PrefixEq names.length frame (walk body pivot depth names emit frame).2 := by
  induction body generalizing depth names frame with
  | nil => intro i _; rfl
  | cons atom rest ih =>
      apply scan_prefix
      · exact compile_fresh_above atom.terms names
      · intro candidate
        exact prefix_weaken _ _ _ _ (compile_length atom.terms names) (ih _ _ candidate)

theorem indexed_pivot_refines (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat)
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (names : List Nat) (env : Env Value) (frame : Frame Value)
    (admitted : Admitted body pivot depth names) (rep : Represents names env frame) :
    (walk body pivot depth names slotEmit frame).1 =
      PositiveTraversal.reference (rawBody body pivot depth) envEmit env := by
  induction body generalizing depth names env frame with
  | nil => exact emits names env frame rep
  | cons atom rest ih =>
      have filtered := filter_binding atom.terms (lane atom pivot depth) env
        (fun row => decide (projectedKey atom.columns row = compiledKey atom.terms atom.columns names frame))
        (PositiveTraversal.reference (rawBody rest pivot (depth + 1)) envEmit)
        (fun row member output success => by
          simp only [decide_eq_true_eq]
          rw [compiled_key_refines atom.terms atom.columns names env frame rep (admitted.2.1 env frame rep)]
          exact bind_columns atom.terms atom.columns row env output
            (admitted.1 row member) (admitted.2.1 env frame rep) success)
      have scanExact := scan_refines atom.terms names env (selectedRows atom pivot depth names frame)
        (walk rest pivot (depth + 1) (compile atom.terms names).2 slotEmit)
        (PositiveTraversal.reference (rawBody rest pivot (depth + 1)) envEmit)
        (fun row member => admitted.1 row (by
          dsimp only [selectedRows] at member
          split at member
          · exact member
          · exact (List.mem_filter.mp member).1))
        (fun candidate => prefix_weaken _ _ _ _ (compile_length atom.terms names)
          (walk_prefix rest pivot (depth + 1) _ slotEmit candidate))
        (fun output candidate represented => ih _ _ _ _ admitted.2.2 represented) frame rep
      change (scan _ _ _ _).1 = _
      rw [scanExact]
      dsimp only [selectedRows]
      split
      · rfl
      · exact filtered

theorem indexed_reuse (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat)
    (names : List Nat) (env : Env Value) (emit : List Nat → Frame Value → List Output)
    (frame : Frame Value) (rep : Represents names env frame) :
    Represents names env (walk body pivot depth names emit frame).2 :=
  represents_prefix names env frame _ rep (walk_prefix body pivot depth names emit frame)

structure StoredAtom (Value : Type) where
  original : Atom Value
  actions : List (Action Value)
  keys : List (Option (Action Value))

def compileBody : List (Atom Value) → List Nat → List (StoredAtom Value) × List Nat
  | [], names => ([], names)
  | atom :: rest, names =>
      let lowered := compile atom.terms names
      let tail := compileBody rest lowered.2
      (⟨atom, lowered.1, atom.columns.map (fun i => lowered.1[i]?)⟩ :: tail.1, tail.2)

def storedRows (atom : StoredAtom Value) (pivot : Option Nat) (depth : Nat)
    (frame : Frame Value) : List (List Value) :=
  let rows := lane atom.original pivot depth
  if atom.original.columns.isEmpty || rows.length < 32 then rows else
    rows.filter fun row => decide (projectedKey atom.original.columns row =
      atom.keys.map (fun action => action.bind (actionValue frame)))

def runBody (body : List (StoredAtom Value)) (pivot : Option Nat) (depth : Nat)
    (finalNames : List Nat) (emit : List Nat → Frame Value → List Output)
    (frame : Frame Value) : Result Value Output :=
  match body with
  | [] => (emit finalNames frame, frame)
  | atom :: rest => scan atom.actions (runBody rest pivot (depth + 1) finalNames emit)
      (storedRows atom pivot depth frame) frame

theorem precompiled_walk (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat)
    (names : List Nat) (emit : List Nat → Frame Value → List Output) :
    runBody (compileBody body names).1 pivot depth (compileBody body names).2 emit =
      walk body pivot depth names emit := by
  induction body generalizing depth names with
  | nil => rfl
  | cons atom rest ih =>
      simp only [compileBody, runBody, walk, storedRows, selectedRows, compiledKey, List.map_map]
      rw [ih]
      rfl

theorem precompiled_indexed_pivot_refines (body : List (Atom Value)) (pivot : Option Nat) (depth : Nat)
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (names : List Nat) (env : Env Value) (frame : Frame Value)
    (admitted : Admitted body pivot depth names) (rep : Represents names env frame) :
    (runBody (compileBody body names).1 pivot depth (compileBody body names).2 slotEmit frame).1 =
      PositiveTraversal.reference (rawBody body pivot depth) envEmit env := by
  rw [precompiled_walk]
  exact indexed_pivot_refines body pivot depth slotEmit envEmit emits names env frame admitted rep

def transition (rows : Atom Value → List (List Value)) (atom : Atom Value)
    (input output : Env Value) : Prop :=
  ∃ row ∈ rows atom, AtomicBinding.bind atom.terms row input = some output

def DeltaExact (body : List (Atom Value)) : Prop :=
  ∀ atom ∈ body, (∀ row ∈ atom.oldRows, row ∈ atom.allRows) ∧
    (∀ row, row ∈ atom.deltaRows ↔ row ∈ atom.allRows ∧ row ∉ atom.oldRows)

/-- BYODS coverage permits overlap with old rows. No new concrete row may
skip delta, and delta may not contain rows outside the current snapshot. -/
def DeltaCovers (body : List (Atom Value)) : Prop :=
  ∀ atom ∈ body, (∀ row ∈ atom.oldRows, row ∈ atom.allRows) ∧
    (∀ row, row ∈ atom.allRows → row ∉ atom.oldRows → row ∈ atom.deltaRows) ∧
    (∀ row ∈ atom.deltaRows, row ∈ atom.allRows)

omit [DecidableEq Value] in
theorem exact_covers (body : List (Atom Value)) (exactDelta : DeltaExact body) :
    DeltaCovers body := by
  intro atom member
  have exactAtom := exactDelta atom member
  exact ⟨exactAtom.1, fun row current absent => (exactAtom.2 row).mpr ⟨current, absent⟩,
    fun row fresh => ((exactAtom.2 row).mp fresh).1⟩

def rowPivots : List (Atom Value) → Env Value → Env Value → Prop
  | [], _, _ => False
  | atom :: rest, input, output =>
      (∃ middle, transition Atom.deltaRows atom input middle ∧
        ProviderFrontier.body (transition Atom.allRows) rest middle output) ∨
      (∃ middle, transition Atom.allRows atom input middle ∧ rowPivots rest middle output)

/-- A new environment transition has a concrete new-row witness. Different
rows may collapse to one environment (e.g. wildcards), so the converse is not
assumed: row pivots can legitimately rederive old heads. -/
theorem changed_to_delta (atom : Atom Value) (input output : Env Value)
    (covered : ∀ row, row ∈ atom.allRows → row ∉ atom.oldRows → row ∈ atom.deltaRows)
    (changed : ProviderFrontier.changed (transition Atom.oldRows atom)
      (transition Atom.allRows atom) input output) :
    transition Atom.deltaRows atom input output := by
  obtain ⟨⟨row, member, bound⟩, absent⟩ := changed
  exact ⟨row, covered row member (fun old => absent ⟨row, old, bound⟩), bound⟩

theorem frontier_to_rows (body : List (Atom Value)) (input output : Env Value)
    (covered : DeltaCovers body)
    (fresh : ProviderFrontier.pivots (transition Atom.oldRows) (transition Atom.allRows) body input output) :
    rowPivots body input output := by
  induction body generalizing input with
  | nil => exact fresh
  | cons atom rest ih =>
      rcases fresh with first | later
      · obtain ⟨middle, changed, tail⟩ := first
        exact Or.inl ⟨middle, changed_to_delta atom input middle
          (covered atom List.mem_cons_self).2.1 changed, tail⟩
      · obtain ⟨middle, all, tail⟩ := later
        exact Or.inr ⟨middle, all, ih middle
          (fun next member => covered next (List.mem_cons_of_mem atom member)) tail⟩

def rawTransition (atom : PositiveTraversal.Atom Value) (input output : Env Value) : Prop :=
  ∃ row ∈ atom.rows, AtomicBinding.bind atom.terms row input = some output

theorem raw_all (body : List (Atom Value)) (depth : Nat) (input output : Env Value) :
    ProviderFrontier.body rawTransition (rawBody body none depth) input output ↔
      ProviderFrontier.body (transition Atom.allRows) body input output := by
  induction body generalizing depth input with
  | nil => rfl
  | cons atom rest ih =>
      simp only [rawBody, ProviderFrontier.body]
      simp only [rawTransition, lane, reduceCtorEq, ↓reduceIte, transition]
      exact exists_congr fun middle => and_congr_right fun _ => ih _ middle

omit [DecidableEq Value] in
theorem raw_past (body : List (Atom Value)) (pivot depth : Nat) (past : pivot < depth) :
    rawBody body (some pivot) depth = rawBody body none depth := by
  induction body generalizing depth with
  | nil => rfl
  | cons atom rest ih =>
      have different : pivot ≠ depth := by omega
      simp only [rawBody, lane, Option.some.injEq, different, ↓reduceIte, reduceCtorEq]
      rw [ih (depth + 1) (by omega)]

/-- Row-level frontier derivations are exactly the union of position-selected
native pivot traversals, including repeated occurrences of one relation. -/
theorem row_pivots_iff (body : List (Atom Value)) (depth : Nat) (input output : Env Value) :
    rowPivots body input output ↔
      ∃ pivot, depth ≤ pivot ∧ pivot < depth + body.length ∧
        ProviderFrontier.body rawTransition (rawBody body (some pivot) depth) input output := by
  induction body generalizing depth input with
  | nil => simp only [rowPivots, List.length_nil, Nat.add_zero, false_iff, not_exists, not_and]; omega
  | cons atom rest ih =>
      constructor
      · intro fresh
        rcases fresh with ⟨middle, delta, tail⟩ | ⟨middle, all, tail⟩
        · refine ⟨depth, Nat.le_refl _, by simp, ?_⟩
          change ∃ middle, rawTransition ⟨atom.terms, lane atom (some depth) depth⟩ input middle ∧ _
          refine ⟨middle, by simpa [rawTransition, transition, lane] using delta, ?_⟩
          rw [raw_past rest depth (depth + 1) (by omega)]
          exact (raw_all rest (depth + 1) middle output).mpr tail
        · obtain ⟨pivot, lower, upper, traversed⟩ := (ih (depth + 1) middle).mp tail
          refine ⟨pivot, by omega, by simp only [List.length_cons] at *; omega, ?_⟩
          change ∃ middle, rawTransition ⟨atom.terms, lane atom (some pivot) depth⟩ input middle ∧ _
          exact ⟨middle, by simpa [rawTransition, transition, lane, show pivot ≠ depth by omega] using all, traversed⟩
      · rintro ⟨pivot, lower, upper, middle, first, tail⟩
        by_cases atHead : pivot = depth
        · subst pivot
          apply Or.inl
          refine ⟨middle, by simpa [rawTransition, transition, lane] using first, ?_⟩
          rw [raw_past rest depth (depth + 1) (by omega)] at tail
          exact (raw_all rest (depth + 1) middle output).mp tail
        · apply Or.inr
          refine ⟨middle, by simpa [rawTransition, transition, lane, atHead] using first, ?_⟩
          apply (ih (depth + 1) middle).mpr
          exact ⟨pivot, by omega, by simp only [List.length_cons] at *; omega, tail⟩

theorem reference_membership (body : List (PositiveTraversal.Atom Value))
    (emit : Env Value → List Output) (input : Env Value) (item : Output) :
    item ∈ PositiveTraversal.reference body emit input ↔
      ∃ output, ProviderFrontier.body rawTransition body input output ∧ item ∈ emit output := by
  induction body generalizing input with
  | nil => simp [PositiveTraversal.reference, ProviderFrontier.body]
  | cons atom rest ih =>
      simp only [PositiveTraversal.reference, List.mem_flatMap]
      constructor
      · rintro ⟨row, member, emitted⟩
        cases bound : AtomicBinding.bind atom.terms row input with
        | none => simp [bound] at emitted
        | some middle =>
            obtain ⟨output, tail, head⟩ := (ih middle).mp (by simpa [bound] using emitted)
            exact ⟨output, ⟨middle, ⟨row, member, bound⟩, tail⟩, head⟩
      · rintro ⟨output, ⟨middle, ⟨row, member, bound⟩, tail⟩, head⟩
        exact ⟨row, member, by simpa [bound] using (ih middle).mpr ⟨output, tail, head⟩⟩

/-- Finite row-level version of the frontier partition. The growth premise
is scoped to this body's atoms; delta covers every new row and may overlap old rows. -/
theorem row_partition (body : List (Atom Value)) (input output : Env Value)
    (covered : DeltaCovers body) :
    ProviderFrontier.body (transition Atom.allRows) body input output ↔
      ProviderFrontier.body (transition Atom.oldRows) body input output ∨ rowPivots body input output := by
  classical
  induction body generalizing input with
  | nil => simp [ProviderFrontier.body, rowPivots]
  | cons atom rest ih =>
      have tailCoverage : DeltaCovers rest :=
        fun next member => covered next (List.mem_cons_of_mem atom member)
      have atomCoverage := covered atom List.mem_cons_self
      have grow : ∀ seed result, transition Atom.oldRows atom seed result → transition Atom.allRows atom seed result := by
        rintro seed result ⟨row, member, bound⟩
        exact ⟨row, atomCoverage.1 row member, bound⟩
      have deltaGrow : ∀ seed result, transition Atom.deltaRows atom seed result → transition Atom.allRows atom seed result := by
        rintro seed result ⟨row, member, bound⟩
        exact ⟨row, atomCoverage.2.2 row member, bound⟩
      constructor
      · rintro ⟨middle, first, tail⟩
        by_cases prior : transition Atom.oldRows atom input middle
        · rcases (ih middle tailCoverage).mp tail with oldTail | freshTail
          · exact Or.inl ⟨middle, prior, oldTail⟩
          · exact Or.inr (Or.inr ⟨middle, first, freshTail⟩)
        · exact Or.inr (Or.inl ⟨middle, changed_to_delta atom input middle atomCoverage.2.1 ⟨first, prior⟩, tail⟩)
      · intro covered
        rcases covered with ⟨middle, first, tail⟩ | ⟨middle, first, tail⟩ | ⟨middle, first, tail⟩
        · exact ⟨middle, grow _ _ first, (ih middle tailCoverage).mpr (Or.inl tail)⟩
        · exact ⟨middle, deltaGrow _ _ first, tail⟩
        · exact ⟨middle, first, (ih middle tailCoverage).mpr (Or.inr tail)⟩

/-- Any consequence absent from the old snapshot is emitted by at least one
indexed delta pivot. Projection collisions and overlapping pivot emissions
are admitted; authoritative output admission must deduplicate them. -/
theorem new_output_indexed_pivot (body : List (Atom Value))
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (covered : DeltaCovers body) (names : List Nat) (input : Env Value) (frame : Frame Value)
    (rep : Represents names input frame)
    (admitted : ∀ pivot, Admitted body (some pivot) 0 names) (item : Output)
    (current : ∃ output, ProviderFrontier.body (transition Atom.allRows) body input output ∧ item ∈ envEmit output)
    (absent : ¬ ∃ output, ProviderFrontier.body (transition Atom.oldRows) body input output ∧ item ∈ envEmit output) :
    ∃ pivot, pivot < body.length ∧ item ∈
      (runBody (compileBody body names).1 (some pivot) 0 (compileBody body names).2 slotEmit frame).1 := by
  obtain ⟨output, derived, emitted⟩ := current
  have partition := (row_partition body input output covered).mp derived
  rcases partition with old | fresh
  · exact False.elim (absent ⟨output, old, emitted⟩)
  · obtain ⟨pivot, _, upper, traversed⟩ := (row_pivots_iff body 0 input output).mp fresh
    refine ⟨pivot, by simpa using upper, ?_⟩
    rw [precompiled_indexed_pivot_refines body (some pivot) 0 slotEmit envEmit emits names input frame (admitted pivot) rep]
    exact (reference_membership _ envEmit input item).mpr ⟨output, traversed, emitted⟩

/-- Every indexed pivot emission belongs to the full next-snapshot solve.
Together with new_output_indexed_pivot this closes the consequence boundary. -/
theorem indexed_pivot_output_sound (body : List (Atom Value)) (pivot : Nat)
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (covered : DeltaCovers body) (names : List Nat) (input : Env Value) (frame : Frame Value)
    (rep : Represents names input frame) (admitted : Admitted body (some pivot) 0 names)
    (inside : pivot < body.length) (item : Output)
    (emitted : item ∈ (runBody (compileBody body names).1 (some pivot) 0
      (compileBody body names).2 slotEmit frame).1) :
    ∃ output, ProviderFrontier.body (transition Atom.allRows) body input output ∧ item ∈ envEmit output := by
  rw [precompiled_indexed_pivot_refines body (some pivot) 0 slotEmit envEmit emits names input frame admitted rep] at emitted
  obtain ⟨output, traversed, head⟩ := (reference_membership _ envEmit input item).mp emitted
  have fresh := (row_pivots_iff body 0 input output).mpr
    ⟨pivot, Nat.zero_le _, by simpa using inside, traversed⟩
  exact ⟨output, (row_partition body input output covered).mpr (Or.inr fresh), head⟩

/-! Shared curried index views select the same ordered occurrences when a
logical column set covers exactly one physical prefix. Native matching/planning
and trie ordinal collection are separate executable obligations. -/
namespace SharedIndex
variable {V : Type}

/-- The native adapter searches columns and values together. Absence is
separate from every field value, including Scheme's false value. -/
def keyValue (column : Nat) : List Nat → List V → Option V
  | head :: columns, value :: values =>
      if column = head then some value else keyValue column columns values
  | _, _ => none

/-- Mirror the physical-prefix recursion rather than silently truncating an
overlong request with `take`. Native failure is represented by `none`. -/
def adaptKey : List Nat → Nat → List Nat → List V → Option (List V)
  | _, 0, _, _ => some []
  | [], _ + 1, _, _ => none
  | column :: physical, count + 1, logical, values => do
      let value ← keyValue column logical values
      let tail ← adaptKey physical count logical values
      pure (value :: tail)

theorem key_value_mapped (column : Nat) (logical : List Nat) (wanted : Nat → V)
    (member : column ∈ logical) :
    keyValue column logical (logical.map wanted) = some (wanted column) := by
  induction logical with
  | nil => simp at member
  | cons head tail ih =>
    by_cases same : column = head
    · subst column; simp [keyValue]
    · have inside : column ∈ tail := (List.mem_cons.mp member).resolve_left same
      simpa [keyValue, same] using ih inside

theorem key_value_absent (column : Nat) (logical : List Nat) (values : List V)
    (absent : column ∉ logical) : keyValue column logical values = none := by
  induction logical generalizing values with
  | nil => cases values <;> rfl
  | cons head tail ih =>
    cases values with
    | nil => rfl
    | cons value values =>
      have different : column ≠ head := fun same => absent (by simp [same])
      have missing : column ∉ tail := fun member => absent (List.mem_cons_of_mem _ member)
      simpa [keyValue, different] using ih values missing

/-- Distinct logical columns admit arbitrary positional values, without
requiring them to have been manufactured by a field function. -/
theorem key_value_pair (column : Nat) (value : V) (logical : List Nat)
    (values : List V) (unique : logical.Nodup)
    (paired : (column, value) ∈ logical.zip values) :
    keyValue column logical values = some value := by
  induction logical generalizing values with
  | nil => simp at paired
  | cons head tail ih =>
    cases values with
    | nil => simp at paired
    | cons first rest =>
      rcases List.mem_cons.mp paired with same | inside
      · cases same; simp [keyValue]
      · have distinct := List.nodup_cons.mp unique
        have different : column ≠ head := by
          intro same
          exact distinct.1 (same ▸ (List.of_mem_zip inside).1)
        simpa [keyValue, different] using ih rest distinct.2 inside

theorem adapt_key_overlong (physical logical : List Nat) (values : List V)
    (count : Nat) (overlong : physical.length < count) :
    adaptKey physical count logical values = none := by
  induction physical generalizing count with
  | nil => cases count <;> simp_all [adaptKey]
  | cons head tail ih =>
    cases count with
    | zero => simp at overlong
    | succ count =>
      have shorter : tail.length < count := by simpa using overlong
      simp [adaptKey, ih count shorter]

theorem adapt_key_mapped (physical logical : List Nat) (count : Nat)
    (wanted : Nat → V) (bounded : count ≤ physical.length)
    (covered : ∀ column ∈ physical.take count, column ∈ logical) :
    adaptKey physical count logical (logical.map wanted) =
      some ((physical.take count).map wanted) := by
  induction count generalizing physical with
  | zero => simp [adaptKey]
  | succ count ih =>
    cases physical with
    | nil => simp at bounded
    | cons head tail =>
      have headMember : head ∈ logical := covered head (by simp)
      have tailCovered : ∀ column ∈ tail.take count, column ∈ logical := by
        intro column member
        exact covered column (by simp [member])
      have tailBounded : count ≤ tail.length := by simpa using bounded
      simp [adaptKey, key_value_mapped head logical wanted headMember,
        ih tail tailBounded tailCovered]

variable [DecidableEq V]

def Matches (columns : List Nat) (row : List V) (wanted : Nat → Option V) : Prop :=
  ∀ column ∈ columns, row[column]? = wanted column

instance (columns : List Nat) (row : List V) (wanted : Nat → Option V) :
    Decidable (Matches columns row wanted) := by
  unfold Matches
  infer_instance

def lookup (columns : List Nat) (rows : List (List V)) (wanted : Nat → Option V) :
    List (List V) := rows.filter fun row => decide (Matches columns row wanted)

theorem matches_coverage (logical physical : List Nat)
    (coverage : ∀ column, column ∈ logical ↔ column ∈ physical)
    (row : List V) (wanted : Nat → Option V) :
    Matches logical row wanted ↔ Matches physical row wanted := by
  constructor
  · intro selected column member
    exact selected column ((coverage column).mpr member)
  · intro selected column member
    exact selected column ((coverage column).mp member)

/-- Equality of ordered filters preserves multiplicity, including duplicate
rows, and does not depend on the order of logical key columns. -/
theorem prefix_lookup (logical permutation : List Nat) (depth : Nat)
    (coverage : ∀ column, column ∈ logical ↔ column ∈ permutation.take depth)
    (rows : List (List V)) (wanted : Nat → Option V) :
    lookup logical rows wanted = lookup (permutation.take depth) rows wanted := by
  unfold lookup
  congr 1
  funext row
  simp only [matches_coverage logical _ coverage row wanted]

/-- The constructed positional adapter supplies exactly the key whose physical
comparison implements the logical constraints. This does not assume an adapter
oracle, a key permutation, or a precomputed physical key. -/
theorem adapted_prefix_exact (logical physical : List Nat) (depth : Nat)
    (bounded : depth ≤ physical.length)
    (coverage : ∀ column, column ∈ logical ↔ column ∈ physical.take depth)
    (wanted : Nat → V) (row : List V) :
    ∃ values, adaptKey physical depth logical (logical.map wanted) = some values ∧
      ((physical.take depth).map (fun column => row[column]?) = values.map some ↔
        Matches logical row (fun column => some (wanted column))) := by
  refine ⟨(physical.take depth).map wanted, ?_, ?_⟩
  · exact adapt_key_mapped physical logical depth wanted bounded
      (fun column member => (coverage column).mpr member)
  · rw [List.map_map, List.map_eq_map_iff]
    exact (matches_coverage logical _ coverage row _).symm

/-- Incremental native admission prepends the reversed insertion batch. The
same logical view distributes over the two ordered spines without deduplication. -/
theorem extend_lookup (columns : List Nat) (old batch : List (List V))
    (wanted : Nat → Option V) :
    lookup columns (batch.reverse ++ old) wanted =
      lookup columns batch.reverse wanted ++ lookup columns old wanted := by
  simp [lookup, List.filter_append]

theorem lookup_membership (columns : List Nat) (rows : List (List V))
    (wanted : Nat → Option V) (row : List V) :
    row ∈ lookup columns rows wanted ↔ row ∈ rows ∧ Matches columns row wanted := by
  simp [lookup]
/-- The native chain planner appends only newly introduced columns. -/
def extendPermutation (prior next : List Nat) : List Nat :=
  prior ++ next.filter fun column => !prior.contains column

theorem extension_coverage (prior next : List Nat)
    (included : ∀ column ∈ prior, column ∈ next) (column : Nat) :
    column ∈ extendPermutation prior next ↔ column ∈ next := by
  simp only [extendPermutation, List.mem_append, List.mem_filter]
  constructor
  · intro member
    exact member.elim (included column) And.left
  · intro member
    by_cases previous : column ∈ prior
    · exact Or.inl previous
    · exact Or.inr ⟨member, by simp [List.contains_eq_mem, previous]⟩

theorem extension_prefix (prior next : List Nat) (depth : Nat)
    (inside : depth ≤ prior.length) :
    (extendPermutation prior next).take depth = prior.take depth := by
  exact List.take_append_of_le_length inside

theorem extension_nodup (prior next : List Nat)
    (priorUnique : prior.Nodup) (nextUnique : next.Nodup) :
    (extendPermutation prior next).Nodup := by
  apply List.nodup_append.mpr
  refine ⟨priorUnique, nextUnique.filter _, ?_⟩
  intro column oldMember other newMember same
  subst other
  have absent : column ∉ prior := by
    simpa [List.contains_eq_mem] using (List.mem_filter.mp newMember).2
  exact absent oldMember

theorem extension_permutation (prior next : List Nat)
    (priorUnique : prior.Nodup) (nextUnique : next.Nodup)
    (included : ∀ column ∈ prior, column ∈ next) :
    (extendPermutation prior next).Perm next := by
  exact (List.perm_ext_iff_of_nodup (extension_nodup prior next priorUnique nextUnique)
    nextUnique).mpr (extension_coverage prior next included)

theorem new_requirement_covered (prior next : List Nat)
    (priorUnique : prior.Nodup) (nextUnique : next.Nodup)
    (included : ∀ column ∈ prior, column ∈ next) (column : Nat) :
    column ∈ next ↔ column ∈ (extendPermutation prior next).take next.length := by
  have sameLength := (extension_permutation prior next priorUnique nextUnique included).length_eq
  rw [← sameLength, List.take_length]
  exact (extension_coverage prior next included column).symm

/-- Every earlier logical view keeps its physical prefix after introducing a
larger requirement. This is the chain-construction step, independent of the
maximum-matching optimization or trie storage representation. -/
theorem chain_prefix_preserved (logical prior next : List Nat) (depth : Nat)
    (inside : depth ≤ prior.length)
    (coverage : ∀ column, column ∈ logical ↔ column ∈ prior.take depth)
    (rows : List (List V)) (wanted : Nat → Option V) :
    lookup logical rows wanted = lookup ((extendPermutation prior next).take depth) rows wanted := by
  rw [extension_prefix prior next depth inside]
  exact prefix_lookup logical prior depth coverage rows wanted

/- A dual endpoint cover certifies maximum matching independently of the
search algorithm. Left and right occurrences are separate vertex namespaces. -/
namespace MatchingCertificate
abbrev Edge := Nat × Nat

def Matching (edges : List Edge) : Prop :=
  edges.Pairwise (fun first second => first.1 ≠ second.1 ∧ first.2 ≠ second.2)

def Covers (graph : List Edge) (left right : List Nat) : Prop :=
  ∀ edge ∈ graph, edge.1 ∈ left ∨ edge.2 ∈ right

def assigned (left : List Nat) (edge : Edge) : Sum Nat Nat :=
  if edge.1 ∈ left then .inl edge.1 else .inr edge.2

theorem matching_bound (graph edges : List Edge) (left right : List Nat)
    (valid : Matching edges) (present : edges ⊆ graph) (cover : Covers graph left right) :
    edges.length ≤ left.length + right.length := by
  have unique : (edges.map (assigned left)).Nodup := by
    apply List.Pairwise.map (assigned left) _ valid
    intro first second distinct
    by_cases firstLeft : first.1 ∈ left <;> by_cases secondLeft : second.1 ∈ left
    · simpa [assigned, firstLeft, secondLeft] using distinct.1
    · simp [assigned, firstLeft, secondLeft]
    · simp [assigned, firstLeft, secondLeft]
    · simpa [assigned, firstLeft, secondLeft] using distinct.2
  have subset : edges.map (assigned left) ⊆ left.map Sum.inl ++ right.map Sum.inr := by
    intro vertex member
    obtain ⟨edge, known, same⟩ := List.mem_map.mp member
    subst vertex
    have covered := cover edge (present known)
    by_cases selected : edge.1 ∈ left
    · simp [assigned, selected]
    · have rightSelected : edge.2 ∈ right := covered.resolve_left selected
      simp [assigned, selected, rightSelected]
  simpa using unique.length_le_of_subset subset

/-- The verified cover equality supplies maximality for every competing
matching, rather than testing optimality on a bounded requirement corpus. -/
theorem maximum (graph chosen other : List Edge) (left right : List Nat)
    (otherValid : Matching other) (otherPresent : other ⊆ graph)
    (cover : Covers graph left right) (tight : left.length + right.length = chosen.length) :
    other.length ≤ chosen.length := by
  rw [← tight]
  exact matching_bound graph other left right otherValid otherPresent cover

/-- A chain partition has one fewer edge than vertices per nonempty chain.
For partitions with the same requirement count, maximum matching minimizes
physical chain count. Native prefix coverage is a separate obligation. -/
theorem minimum_chains (graph chosen other : List Edge) (left right : List Nat)
    (otherValid : Matching other) (otherPresent : other ⊆ graph)
    (cover : Covers graph left right) (tight : left.length + right.length = chosen.length)
    (requirements chosenChains otherChains : Nat)
    (chosenBalance : chosen.length + chosenChains = requirements)
    (otherBalance : other.length + otherChains = requirements) :
    chosenChains ≤ otherChains := by
  have bound := maximum graph chosen other left right otherValid otherPresent cover tight
  omega
def chainEdges (chain : List Nat) : List Edge := chain.zip chain.tail

def partitionEdges (chains : List (List Nat)) : List Edge := chains.flatMap chainEdges

theorem chain_balance (chain : List Nat) (nonempty : chain ≠ []) :
    (chainEdges chain).length + 1 = chain.length := by
  cases chain with
  | nil => contradiction
  | cons head tail => simp [chainEdges, List.length_zip]

theorem partition_balance (chains : List (List Nat))
    (nonempty : ∀ chain ∈ chains, chain ≠ []) :
    (partitionEdges chains).length + chains.length = chains.flatten.length := by
  induction chains with
  | nil => simp [partitionEdges]
  | cons chain rest ih =>
      have first := chain_balance chain (nonempty chain List.mem_cons_self)
      have remaining := ih (fun c h => nonempty c (List.mem_cons_of_mem chain h))
      simp only [partitionEdges, List.flatMap_cons, List.length_append,
        List.length_cons, List.flatten_cons] at *
      omega

theorem chain_endpoints (chain : List Nat) :
    List.Sublist ((chainEdges chain).map Prod.fst) chain ∧
    List.Sublist ((chainEdges chain).map Prod.snd) chain := by
  induction chain with
  | nil => simp [chainEdges]
  | cons head tail ih =>
      cases tail with
      | nil => simp [chainEdges]
      | cons next rest =>
          constructor
          · exact ih.1.cons_cons head
          · change List.Sublist ((List.zip (head :: next :: rest) (next :: rest)).map Prod.snd) (head :: next :: rest)
            rw [List.map_snd_zip (by simp)]
            exact (List.Sublist.refl _).cons head

theorem partition_endpoints (chains : List (List Nat)) :
    List.Sublist ((partitionEdges chains).map Prod.fst) chains.flatten ∧
    List.Sublist ((partitionEdges chains).map Prod.snd) chains.flatten := by
  induction chains with
  | nil => simp [partitionEdges]
  | cons chain rest ih =>
      simp only [partitionEdges, List.flatMap_cons, List.map_append, List.flatten_cons]
      exact ⟨(chain_endpoints chain).1.append ih.1, (chain_endpoints chain).2.append ih.2⟩

theorem partition_matching (chains : List (List Nat)) (unique : chains.flatten.Nodup) :
    Matching (partitionEdges chains) := by
  have endpoints := partition_endpoints chains
  have left := endpoints.1.nodup unique
  have right := endpoints.2.nodup unique
  have leftPairs := List.pairwise_map.mp left
  have rightPairs := List.pairwise_map.mp right
  exact leftPairs.imp₂ (fun _ _ a b => ⟨a, b⟩) rightPairs

/-- Every legal competing partition supplies its matching and balance by
construction. No assumed edge count or competing matching is needed. -/
theorem minimum_partition (graph : List Edge) (chosen other : List (List Nat))
    (left right : List Nat)
    (chosenNonempty : ∀ chain ∈ chosen, chain ≠ [])
    (otherNonempty : ∀ chain ∈ other, chain ≠ [])
    (otherUnique : other.flatten.Nodup)
    (sameCount : chosen.flatten.length = other.flatten.length)
    (otherPresent : partitionEdges other ⊆ graph)
    (cover : Covers graph left right)
    (tight : left.length + right.length = (partitionEdges chosen).length) :
    chosen.length ≤ other.length := by
  apply minimum_chains graph (partitionEdges chosen) (partitionEdges other) left right
    (partition_matching other otherUnique) otherPresent cover tight chosen.flatten.length
  · exact partition_balance chosen chosenNonempty
  · rw [sameCount]; exact partition_balance other otherNonempty
end MatchingCertificate

end SharedIndex

def actionValueVector {n : Nat} (vector : Vector Value n) : Action Value → Option Value
  | .literal value => some value
  | .fresh index | .bound index => vector[index]?
  | .wildcard => none

omit [DecidableEq Value] in
theorem vector_action_value {n : Nat} (frame : Frame Value) (vector : Vector Value n)
    (rep : VectorRep frame vector) (action : Action Value) (bounded : action.InRange n) :
    actionValueVector vector action = actionValue frame action := by
  cases action <;> simp only [Action.InRange] at bounded
  · simp [actionValueVector, actionValue, bounded, rep _ bounded]
  · simp [actionValueVector, actionValue, bounded, rep _ bounded]
  · rfl
  · rfl

def compiledVectorKey {n : Nat} (terms : List (Term Value)) (columns names : List Nat)
    (vector : Vector Value n) : List (Option Value) :=
  columns.map fun i => (compile terms names).1[i]?.bind (actionValueVector vector)

omit [DecidableEq Value] in
theorem compiled_vector_key_refines {n : Nat} (terms : List (Term Value))
    (columns names : List Nat) (env : Env Value) (frame : Frame Value) (vector : Vector Value n)
    (rep : Represents names env frame) (vectorRep : VectorRep frame vector)
    (extent : (compile terms names).2.length ≤ n) (known : KnownColumns terms columns env) :
    compiledVectorKey terms columns names vector = envKey terms columns env := by
  rw [← compiled_key_refines terms columns names env frame rep known]
  apply List.map_congr_left
  intro index _
  cases found : (compile terms names).1[index]? with
  | none => rfl
  | some action =>
      have member := List.mem_of_getElem? found
      have slotBound := compile_slots_bounded terms names action member
      have bounded : action.InRange n := by
        cases action <;> simp only [Action.InRange] at slotBound ⊢
        · exact Nat.lt_of_lt_of_le slotBound extent
        · exact Nat.lt_of_lt_of_le slotBound extent
      simp only [found, Option.bind_some]
      exact vector_action_value frame vector vectorRep action bounded

end Ascent.IndexedPositiveTraversal
