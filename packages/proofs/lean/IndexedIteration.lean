-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import IndexedPositiveTraversal
import PositiveConsequence

/-! Concrete compiled indexed pivot batches and synchronous positive Set history.
Initialization is full. Old-head coverage is derived from the preceding round,
not assumed as completion. Frames represent each rule's seed prefix; pivot
batches reuse their actual dirty returns. Actor scheduling/cache publication
and native extraction are not duplicated in this semantic proof. -/
namespace Ascent.IndexedIteration
open AtomicBinding PositiveSlots
open IndexedPositiveTraversal
variable {Key Value Output : Type} [DecidableEq Value]
abbrev Spec (Key Value : Type) := PositiveConsequence.Atom Key Value × List Nat
abbrev Rows (Key Value Output : Type) := SemiNaive.Database Output → Key → List (List Value)

structure Rule (Key Value Output : Type) where
  atoms : List (Spec Key Value)
  names : List Nat
  seed : Env Value
  frame : Frame Value
  emit : Env Value → List Output
  slotEmit : List Nat → Frame Value → List Output

def instantiate (specs : List (Spec Key Value)) (old next : Key → List (List Value)) : List (Atom Value) :=
  specs.map fun spec => ⟨spec.1.terms, spec.2, next spec.1.source,
    (next spec.1.source).filter (fun row => !decide (row ∈ old spec.1.source)), old spec.1.source⟩

def Schema (domain : Key → List Value → Prop) : List (Spec Key Value) → List Nat → Prop
  | [], _ => True
  | spec :: rest, names =>
      (∀ row, domain spec.1.source row → spec.1.terms.length = row.length) ∧
      (∀ env frame, Represents names env frame → KnownColumns spec.1.terms spec.2 env) ∧
      Schema domain rest (compile spec.1.terms names).2

def Valid (domain : Key → List Value → Prop) (rule : Rule Key Value Output) : Prop :=
  Schema domain rule.atoms rule.names ∧ Represents rule.names rule.seed rule.frame ∧
  ∀ names env frame, Represents names env frame → rule.slotEmit names frame = rule.emit env

def RowsAdmitted (domain : Key → List Value → Prop) (rows : Rows Key Value Output) : Prop :=
  ∀ database key row, row ∈ rows database key → domain key row

def RowsMonotone (rows : Rows Key Value Output) : Prop :=
  ∀ before after, (∀ item, before item → after item) →
    ∀ key row, row ∈ rows before key → row ∈ rows after key

theorem instantiated_admitted (specs : List (Spec Key Value)) (domain : Key → List Value → Prop)
    (old next : Key → List (List Value)) (names : List Nat)
    (schema : Schema domain specs names) (covered : ∀ key row, row ∈ next key → domain key row)
    (pivot : Option Nat) (depth : Nat) : Admitted (instantiate specs old next) pivot depth names := by
  induction specs generalizing names depth with
  | nil => trivial
  | cons spec rest ih =>
      refine ⟨?_, schema.2.1, ih _ schema.2.2 _⟩
      intro row member
      apply schema.1 row
      apply covered spec.1.source row
      dsimp [instantiate, lane] at member
      split at member
      · exact (List.mem_filter.mp member).1
      · exact member

theorem instantiated_delta (specs : List (Spec Key Value)) (old next : Key → List (List Value))
    (grows : ∀ key row, row ∈ old key → row ∈ next key) : DeltaExact (instantiate specs old next) := by
  intro atom member
  obtain ⟨spec, _, same⟩ := List.mem_map.mp member
  subst atom
  exact ⟨grows spec.1.source, fun row => by simp⟩

theorem instantiated_body (specs : List (Spec Key Value)) (old next : Key → List (List Value))
    (input output : Env Value) :
    ProviderFrontier.body (transition Atom.allRows) (instantiate specs old next) input output ↔
      ProviderFrontier.body (PositiveConsequence.transition next) (specs.map Prod.fst) input output := by
  induction specs generalizing input with
  | nil => rfl
  | cons spec rest ih =>
      simp only [instantiate, List.map_cons, ProviderFrontier.body]
      exact exists_congr fun middle => and_congr_right fun _ => ih middle

theorem instantiated_old (specs : List (Spec Key Value)) (old next : Key → List (List Value))
    (input output : Env Value) :
    ProviderFrontier.body (transition Atom.oldRows) (instantiate specs old next) input output ↔
      ProviderFrontier.body (PositiveConsequence.transition old) (specs.map Prod.fst) input output := by
  induction specs generalizing input with
  | nil => rfl
  | cons spec rest ih =>
      simp only [instantiate, List.map_cons, ProviderFrontier.body]
      exact exists_congr fun middle => and_congr_right fun _ => ih middle

def batch (body : List (Atom Value)) (names : List Nat)
    (emit : List Nat → Frame Value → List Output) : List Nat → Frame Value → PositiveTraversal.Result Value Output
  | [], frame => ([], frame)
  | pivot :: rest, frame =>
      let compiled := compileBody body names
      let first := runBody compiled.1 (some pivot) 0 compiled.2 emit frame
      let tail := batch body names emit rest first.2
      (first.1 ++ tail.1, tail.2)

theorem batch_reuse (body : List (Atom Value)) (names : List Nat) (env : Env Value)
    (emit : List Nat → Frame Value → List Output) (pivots : List Nat)
    (frame : Frame Value) (rep : Represents names env frame) :
    Represents names env (batch body names emit pivots frame).2 := by
  induction pivots generalizing frame with
  | nil => exact rep
  | cons pivot rest ih =>
      apply ih
      rw [precompiled_walk]
      exact indexed_reuse body (some pivot) 0 names env emit frame rep

theorem batch_refines (body : List (Atom Value)) (names : List Nat) (env : Env Value)
    (slotEmit : List Nat → Frame Value → List Output) (envEmit : Env Value → List Output)
    (emits : ∀ names env frame, Represents names env frame → slotEmit names frame = envEmit env)
    (pivots : List Nat) (admitted : ∀ pivot ∈ pivots, Admitted body (some pivot) 0 names)
    (frame : Frame Value) (rep : Represents names env frame) :
    (batch body names slotEmit pivots frame).1 = pivots.flatMap
      (fun pivot => PositiveTraversal.reference (rawBody body (some pivot) 0) envEmit env) := by
  induction pivots generalizing frame with
  | nil => rfl
  | cons pivot rest ih =>
      have kept : Represents names env
          (runBody (compileBody body names).1 (some pivot) 0 (compileBody body names).2 slotEmit frame).2 := by
        rw [precompiled_walk]
        exact indexed_reuse body (some pivot) 0 names env slotEmit frame rep
      have tail := ih (fun p member => admitted p (List.mem_cons_of_mem pivot member)) _ kept
      simp only [batch, List.flatMap_cons]
      rw [precompiled_indexed_pivot_refines body (some pivot) 0 slotEmit envEmit emits names env frame
        (admitted pivot List.mem_cons_self) rep, tail]

def consequence (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (database : SemiNaive.Database Output) (item : Output) : Prop :=
  ∃ output, ProviderFrontier.body (PositiveConsequence.transition (rows database))
    (rule.atoms.map Prod.fst) rule.seed output ∧ item ∈ rule.emit output

def fullRun (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (database : SemiNaive.Database Output) : List Output :=
  let body := instantiate rule.atoms (rows database) (rows database)
  runBody (compileBody body rule.names).1 none 0 (compileBody body rule.names).2 rule.slotEmit rule.frame |>.1

def pivotRun (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (old next : SemiNaive.Database Output) : List Output :=
  let body := instantiate rule.atoms (rows old) (rows next)
  (batch body rule.names rule.slotEmit (List.range body.length) rule.frame).1

/-- A rule's original seed prefix survives every actual dirty pivot return,
so the next round can reuse that frame without clearing it. -/
theorem returned_frame_valid (rule : Rule Key Value Output) (domain : Key → List Value → Prop)
    (valid : Valid domain rule) (old next : Key → List (List Value)) :
    Valid domain {rule with frame :=
      (batch (instantiate rule.atoms old next) rule.names rule.slotEmit
        (List.range rule.atoms.length) rule.frame).2} :=
  ⟨valid.1, batch_reuse _ _ _ _ _ _ valid.2.1, valid.2.2⟩

theorem pivot_frame_independent (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : Valid domain rule) (covered : RowsAdmitted domain rows)
    (old next : SemiNaive.Database Output) (frame : Frame Value)
    (rep : Represents rule.names rule.seed frame) :
    pivotRun {rule with frame := frame} rows old next = pivotRun rule rows old next := by
  unfold pivotRun
  rw [batch_refines _ rule.names rule.seed rule.slotEmit rule.emit valid.2.2 _
    (fun p _ => instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered next) (some p) 0)
    frame rep,
    batch_refines _ rule.names rule.seed rule.slotEmit rule.emit valid.2.2 _
    (fun p _ => instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered next) (some p) 0)
    rule.frame valid.2.1]

theorem full_run_exact (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : Valid domain rule) (covered : RowsAdmitted domain rows)
    (database : SemiNaive.Database Output) (item : Output) :
    item ∈ fullRun rule rows database ↔ consequence rule rows database item := by
  unfold fullRun
  rw [precompiled_indexed_pivot_refines _ none 0 rule.slotEmit rule.emit valid.2.2 rule.names rule.seed rule.frame
    (instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered database) none 0) valid.2.1]
  rw [reference_membership]
  exact exists_congr fun output => and_congr_left fun _ =>
    (raw_all _ 0 rule.seed output).trans (instantiated_body rule.atoms _ _ rule.seed output)

theorem pivot_run_sound (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : Valid domain rule) (covered : RowsAdmitted domain rows)
    (old next : SemiNaive.Database Output) (grows : ∀ item, old item → next item)
    (monotone : RowsMonotone rows) (item : Output) (emitted : item ∈ pivotRun rule rows old next) :
    consequence rule rows next item := by
  unfold pivotRun at emitted
  rw [batch_refines _ rule.names rule.seed rule.slotEmit rule.emit valid.2.2 _
    (fun pivot _ => instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered next) (some pivot) 0)
    rule.frame valid.2.1] at emitted
  obtain ⟨pivot, member, head⟩ := List.mem_flatMap.mp emitted
  obtain ⟨output, traversed, emitted⟩ := (reference_membership _ rule.emit rule.seed item).mp head
  have fresh := (row_pivots_iff _ 0 rule.seed output).mpr
    ⟨pivot, Nat.zero_le _, by simpa using List.mem_range.mp member, traversed⟩
  have all := (row_partition _ rule.seed output
    (exact_covers _ (instantiated_delta rule.atoms _ _ (monotone old next grows)))).mpr (Or.inr fresh)
  exact ⟨output, (instantiated_body rule.atoms _ _ rule.seed output).mp all, emitted⟩

theorem pivot_run_complete (rule : Rule Key Value Output) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : Valid domain rule) (covered : RowsAdmitted domain rows)
    (old next : SemiNaive.Database Output) (grows : ∀ item, old item → next item)
    (monotone : RowsMonotone rows) (item : Output)
    (current : consequence rule rows next item) (absent : ¬ consequence rule rows old item) :
    item ∈ pivotRun rule rows old next := by
  have now : ∃ output, ProviderFrontier.body (transition Atom.allRows)
      (instantiate rule.atoms (rows old) (rows next)) rule.seed output ∧ item ∈ rule.emit output := by
    obtain ⟨output, traversed, head⟩ := current
    exact ⟨output, (instantiated_body rule.atoms _ _ rule.seed output).mpr traversed, head⟩
  have prior : ¬ ∃ output, ProviderFrontier.body (transition Atom.oldRows)
      (instantiate rule.atoms (rows old) (rows next)) rule.seed output ∧ item ∈ rule.emit output := by
    rintro ⟨output, traversed, head⟩
    exact absent ⟨output, (instantiated_old rule.atoms _ _ rule.seed output).mp traversed, head⟩
  obtain ⟨pivot, inside, emitted⟩ := new_output_indexed_pivot _ rule.slotEmit rule.emit valid.2.2
    (exact_covers _ (instantiated_delta rule.atoms _ _ (monotone old next grows))) rule.names rule.seed rule.frame valid.2.1
    (fun p => instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered next) (some p) 0) item now prior
  unfold pivotRun
  rw [batch_refines _ rule.names rule.seed rule.slotEmit rule.emit valid.2.2 _
    (fun p _ => instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered next) (some p) 0)
    rule.frame valid.2.1]
  apply List.mem_flatMap.mpr
  refine ⟨pivot, List.mem_range.mpr inside, ?_⟩
  rwa [precompiled_indexed_pivot_refines _ (some pivot) 0 rule.slotEmit rule.emit valid.2.2 rule.names rule.seed rule.frame
    (instantiated_admitted rule.atoms domain _ _ rule.names valid.1 (covered next) (some pivot) 0) valid.2.1] at emitted

def fullStep (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (known : SemiNaive.Database Output) : SemiNaive.Database Output :=
  fun item => known item ∨ ∃ rule ∈ rules, consequence rule rows known item

def compiledFullStep (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (known : SemiNaive.Database Output) : SemiNaive.Database Output :=
  fun item => known item ∨ ∃ rule ∈ rules, item ∈ fullRun rule rows known

def compiledPivotStep (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (old known : SemiNaive.Database Output) : SemiNaive.Database Output :=
  fun item => known item ∨ ∃ rule ∈ rules, item ∈ pivotRun rule rows old known

theorem full_step_exact (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : ∀ rule ∈ rules, Valid domain rule)
    (covered : RowsAdmitted domain rows) (known : SemiNaive.Database Output) :
    compiledFullStep rules rows known = fullStep rules rows known := by
  funext item; apply propext
  simp only [compiledFullStep, fullStep]
  exact or_congr_right (exists_congr fun rule => and_congr_right fun member =>
    full_run_exact rule rows domain (valid rule member) covered known item)

/-- History supplies all-old heads through the preceding full consequence
step. No completed/fixed-point premise enters the pivot round. -/
theorem pivot_after_full (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : ∀ rule ∈ rules, Valid domain rule)
    (covered : RowsAdmitted domain rows) (monotone : RowsMonotone rows)
    (old : SemiNaive.Database Output) :
    compiledPivotStep rules rows old (fullStep rules rows old) =
      fullStep rules rows (fullStep rules rows old) := by
  classical
  funext item; apply propext
  have grows : ∀ item, old item → fullStep rules rows old item := fun _ h => Or.inl h
  constructor
  · rintro (known | ⟨rule, member, emitted⟩)
    · exact Or.inl known
    · exact Or.inr ⟨rule, member, pivot_run_sound rule rows domain (valid rule member) covered old _ grows monotone item emitted⟩
  · rintro (known | ⟨rule, member, current⟩)
    · exact Or.inl known
    · by_cases prior : consequence rule rows old item
      · exact Or.inl (Or.inr ⟨rule, member, prior⟩)
      · exact Or.inr ⟨rule, member, pivot_run_complete rule rows domain (valid rule member) covered old _ grows monotone item current prior⟩

def naive (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (initial : SemiNaive.Database Output) : Nat → SemiNaive.Database Output
  | 0 => initial
  | n + 1 => fullStep rules rows (naive rules rows initial n)

def indexed (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (initial : SemiNaive.Database Output) : Nat → SemiNaive.Database Output × SemiNaive.Database Output
  | 0 => (initial, compiledFullStep rules rows initial)
  | n + 1 =>
      let prior := indexed rules rows initial n
      (prior.2, compiledPivotStep rules rows prior.1 prior.2)

theorem indexed_iterations_equal (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : ∀ rule ∈ rules, Valid domain rule)
    (covered : RowsAdmitted domain rows) (monotone : RowsMonotone rows)
    (initial : SemiNaive.Database Output) (n : Nat) :
    indexed rules rows initial n = (naive rules rows initial n, naive rules rows initial (n + 1)) := by
  induction n with
  | zero => simp only [indexed, naive, full_step_exact rules rows domain valid covered]
  | succ n ih =>
      simp only [indexed, ih, naive]
      rw [pivot_after_full rules rows domain valid covered monotone]

/-- Once the concrete full step stabilizes, every later indexed snapshot has
the same facts. This transports observed stability; it asserts no cutoff. -/
theorem stable_indexed (rules : List (Rule Key Value Output)) (rows : Rows Key Value Output)
    (domain : Key → List Value → Prop) (valid : ∀ rule ∈ rules, Valid domain rule)
    (covered : RowsAdmitted domain rows) (monotone : RowsMonotone rows)
    (initial : SemiNaive.Database Output) (n : Nat)
    (stable : naive rules rows initial (n + 1) = naive rules rows initial n) (extra : Nat) :
    (indexed rules rows initial (n + extra)).2 = naive rules rows initial n := by
  rw [indexed_iterations_equal rules rows domain valid covered monotone]
  have stays : ∀ extra, naive rules rows initial (n + extra) = naive rules rows initial n := by
    intro extra
    induction extra with
    | zero => simp
    | succ extra ih =>
        change fullStep rules rows (naive rules rows initial (n + extra)) = naive rules rows initial n
        rw [ih]
        exact stable
  simpa [Nat.add_assoc] using stays (extra + 1)
omit [DecidableEq Value] in
/-- A fixed declared tuple domain discharges both row assumptions. This is
faithful finite snapshot enumeration, not callback monotonicity. -/
theorem faithful_rows_admitted (tupleDomain : List (Key × List Value))
    (rows : Rows Key Value (Key × List Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      (key, row) ∈ tupleDomain ∧ database (key, row)) :
    RowsAdmitted (fun key row => (key, row) ∈ tupleDomain) rows :=
  fun database key row member => ((faithful database key row).mp member).1

omit [DecidableEq Value] in
theorem faithful_rows_monotone (tupleDomain : List (Key × List Value))
    (rows : Rows Key Value (Key × List Value))
    (faithful : ∀ database key row, row ∈ rows database key ↔
      (key, row) ∈ tupleDomain ∧ database (key, row)) : RowsMonotone rows := by
  intro before after included key row member
  obtain ⟨admitted, present⟩ := (faithful before key row).mp member
  exact (faithful after key row).mpr ⟨admitted, included _ present⟩

end Ascent.IndexedIteration
