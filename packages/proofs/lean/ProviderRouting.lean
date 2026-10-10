-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
namespace Ascent.ProviderRouting
variable {Row Value : Type} [DecidableEq Value]

def keyMatches (coordinate : Row → Nat → Value) (constraints : List (Nat × Value))
    (row : Row) : Bool := constraints.all fun binding => coordinate row binding.1 == binding.2

def scan (coordinate : Row → Nat → Value) (constraints : List (Nat × Value))
    (rows : List Row) : List Row := rows.filter (keyMatches coordinate constraints)

def routed (coordinate : Row → Nat → Value) (constraints : List (Nat × Value))
    (candidate : Row → Bool) (rows : List Row) : List Row :=
  (rows.filter candidate).filter (keyMatches coordinate constraints)

theorem selected_constraint (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (binding : Nat × Value) (row : Row)
    (selected : binding ∈ constraints) (hit : keyMatches coordinate constraints row = true) :
    coordinate row binding.1 = binding.2 := by
  have h := List.all_eq_true.mp hit binding selected
  exact beq_iff_eq.mp h

-- Candidate buckets may overselect. They may not omit any matching occurrence.
-- List equality preserves traversal order, duplicates and the stored row itself.
theorem routed_exact (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (candidate : Row → Bool) (rows : List Row)
    (coverage : ∀ row ∈ rows, keyMatches coordinate constraints row = true → candidate row = true) :
    routed coordinate constraints candidate rows = scan coordinate constraints rows := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    have tail := ih (fun r hr => coverage r (List.mem_cons_of_mem row hr))
    have head := coverage row (by simp)
    by_cases hit : keyMatches coordinate constraints row = true
    · have admitted := head hit
      simpa [routed,scan,List.filter_cons,hit,admitted] using congrArg (List.cons row) tail
    · by_cases admitted : candidate row = true <;>
        simpa [routed,scan,List.filter_cons,hit,admitted] using tail

theorem coordinate_bucket_exact (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (binding : Nat × Value) (rows : List Row)
    (selected : binding ∈ constraints) :
    routed coordinate constraints (fun row => coordinate row binding.1 == binding.2) rows =
      scan coordinate constraints rows := by
  apply routed_exact
  intro row _ hit
  exact beq_iff_eq.mpr (selected_constraint coordinate constraints binding row selected hit)

theorem stored_occurrence (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (rows : List Row) (row : Row) :
    row ∈ scan coordinate constraints rows ↔ row ∈ rows ∧ keyMatches coordinate constraints row = true := by
  simp [scan]

theorem conflicting_duplicate (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (column : Nat) (left right : Value) (rows : List Row)
    (a : (column,left) ∈ constraints) (b : (column,right) ∈ constraints) (different : left ≠ right) :
    scan coordinate constraints rows = [] := by
  apply List.filter_eq_nil_iff.mpr
  intro row _ hit
  exact different ((selected_constraint coordinate constraints _ row a hit).symm.trans
    (selected_constraint coordinate constraints _ row b hit))
theorem constraints_permuted (coordinate : Row → Nat → Value)
    (left right : List (Nat × Value)) (rows : List Row) (order : left.Perm right) :
    scan coordinate left rows = scan coordinate right rows := by
  have equalPredicates : keyMatches coordinate left = keyMatches coordinate right := by
    funext row
    exact order.all_eq
  simp [scan,equalPredicates]

theorem bucket_choice_independent (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (left right : Nat × Value) (rows : List Row)
    (a : left ∈ constraints) (b : right ∈ constraints) :
    routed coordinate constraints (fun row => coordinate row left.1 == left.2) rows =
      routed coordinate constraints (fun row => coordinate row right.1 == right.2) rows := by
  rw [coordinate_bucket_exact coordinate constraints left rows a,
      coordinate_bucket_exact coordinate constraints right rows b]

/-! Native table/funs.ss and table/access.ss insert each batch row at the head
of its bucket, reverse fresh build buckets once, and never reverse published
buckets. The functional dictionary below models that algorithm, rather than
assuming that its candidate enumeration is complete. Native hash/equality and
mutable dictionary extraction remain a separate representation obligation. -/
section Construction
variable {Key : Type} [DecidableEq Key]

def prependRow (keyOf : Row → Key) (index : Key → List Row) (row : Row) : Key → List Row :=
  fun key => if keyOf row = key then row :: index key else index key

def prependBatch (keyOf : Row → Key) (index : Key → List Row) : List Row → Key → List Row
  | [] => index
  | row :: rest => prependBatch keyOf (prependRow keyOf index row) rest

def keyScan (keyOf : Row → Key) (key : Key) (rows : List Row) : List Row :=
  rows.filter (fun row => keyOf row == key)

def buildBuckets (keyOf : Row → Key) (rows : List Row) : Key → List Row :=
  fun key => (prependBatch keyOf (fun _ => []) rows key).reverse

theorem prepend_batch_exact (keyOf : Row → Key) (index : Key → List Row)
    (rows : List Row) (key : Key) :
    prependBatch keyOf index rows key = keyScan keyOf key rows.reverse ++ index key := by
  induction rows generalizing index with
  | nil => simp [prependBatch, keyScan]
  | cons row rest ih =>
      rw [prependBatch, ih]
      by_cases hit : keyOf row = key <;>
        simp [keyScan, prependRow, List.reverse_cons, List.filter_append, hit,
          List.append_assoc]

theorem build_buckets_exact (keyOf : Row → Key) (rows : List Row) (key : Key) :
    buildBuckets keyOf rows key = keyScan keyOf key rows := by
  simp [buildBuckets, prepend_batch_exact, keyScan, List.filter_reverse]

-- The actual newest-first relation cut is reverse(batch) ++ old, not batch ++ old.
theorem extend_buckets_exact (keyOf : Row → Key) (index : Key → List Row)
    (old batch : List Row) (faithful : ∀ key, index key = keyScan keyOf key old)
    (key : Key) :
    prependBatch keyOf index batch key = keyScan keyOf key (batch.reverse ++ old) := by
  rw [prepend_batch_exact, faithful key]
  simp [keyScan, List.filter_append]

-- Arbitrary finite histories preserve all occurrences, including duplicate rows.
def replayBuckets (keyOf : Row → Key) : List (List Row) → (Key → List Row) → Key → List Row
  | [], index => index
  | batch :: rest, index => replayBuckets keyOf rest (prependBatch keyOf index batch)

def replayRows : List (List Row) → List Row → List Row
  | [], rows => rows
  | batch :: rest, rows => replayRows rest (batch.reverse ++ rows)

theorem replay_buckets_exact (keyOf : Row → Key) (history : List (List Row))
    (index : Key → List Row) (rows : List Row)
    (faithful : ∀ key, index key = keyScan keyOf key rows) (key : Key) :
    replayBuckets keyOf history index key = keyScan keyOf key (replayRows history rows) := by
  induction history generalizing index rows with
  | nil => exact faithful key
  | cons batch rest ih =>
      exact ih (prependBatch keyOf index batch) (batch.reverse ++ rows)
        (extend_buckets_exact keyOf index rows batch faithful)

-- Hash collisions are allowed. Encodings may not merge distinct semantic keys.
theorem encoded_build_exact {Encoded : Type} [DecidableEq Encoded]
    (keyOf : Row → Key) (encode : Key → Encoded) (injective : Function.Injective encode)
    (rows : List Row) (key : Key) :
    buildBuckets (encode ∘ keyOf) rows (encode key) = keyScan keyOf key rows := by
  rw [build_buckets_exact]
  apply List.filter_congr
  intro row _
  simp only [Function.comp_apply]
  exact Bool.eq_iff_iff.mpr (by simpa only [beq_iff_eq] using injective.eq_iff)

-- Every built index concretizes exactly the same rows at its own key projection.
theorem built_candidate_routing_exact (coordinate : Row → Nat → Value)
    (constraints : List (Nat × Value)) (binding : Nat × Value) (rows : List Row)
    (selected : binding ∈ constraints) :
    (buildBuckets (fun row => coordinate row binding.1) rows binding.2).filter
      (keyMatches coordinate constraints) = scan coordinate constraints rows := by
  rw [build_buckets_exact]
  exact coordinate_bucket_exact coordinate constraints binding rows selected

def enumerateBuckets (index : Key → List Row) (keys : List Key) : List Row :=
  keys.flatMap index

theorem key_scan_count [DecidableEq Row] (keyOf : Row → Key) (key : Key)
    (rows : List Row) (row : Row) :
    (keyScan keyOf key rows).count row = if keyOf row = key then rows.count row else 0 := by
  by_cases hit : keyOf row = key
  · simp [hit, keyScan, List.count_filter (a := row) (p := fun r => keyOf r == key) (by simp [hit])]
  · have absent : row ∉ keyScan keyOf key rows := by simp [keyScan, hit]
    simp [hit, List.count_eq_zero.mpr absent]

-- ReadAll must enumerate each semantic key once. Coverage alone would accept
-- repeated keys and duplicate every occurrence in their buckets.
theorem build_read_all_count [DecidableEq Row] (keyOf : Row → Key)
    (rows : List Row) (keys : List Key) (row : Row) :
    (enumerateBuckets (buildBuckets keyOf rows) keys).count row =
      keys.count (keyOf row) * rows.count row := by
  induction keys with
  | nil => simp [enumerateBuckets]
  | cons key keys ih =>
      simp only [enumerateBuckets, List.flatMap_cons, List.count_append] at *
      rw [build_buckets_exact, key_scan_count, ih]
      by_cases hit : keyOf row = key
      · simp [hit, Nat.add_mul, Nat.add_comm]
      · simp [hit, Ne.symm hit]

theorem complete_read_all_count [DecidableEq Row] (keyOf : Row → Key)
    (rows : List Row) (keys : List Key) (unique : keys.Nodup)
    (covered : ∀ row ∈ rows, keyOf row ∈ keys) (row : Row) :
    (enumerateBuckets (buildBuckets keyOf rows) keys).count row = rows.count row := by
  rw [build_read_all_count]
  by_cases present : row ∈ rows
  · have once : keys.count (keyOf row) = 1 :=
      unique.count_of_mem (covered row present)
    simp [once]
  · simp [List.count_eq_zero.mpr present]

theorem replay_read_all_count [DecidableEq Row] (keyOf : Row → Key)
    (rows : List Row) (history : List (List Row)) (keys : List Key)
    (unique : keys.Nodup)
    (covered : ∀ row ∈ replayRows history rows, keyOf row ∈ keys) (row : Row) :
    (enumerateBuckets (replayBuckets keyOf history (buildBuckets keyOf rows)) keys).count row =
      (replayRows history rows).count row := by
  have constructed : replayBuckets keyOf history (buildBuckets keyOf rows) =
      buildBuckets keyOf (replayRows history rows) := by
    funext key
    rw [replay_buckets_exact keyOf history _ rows (build_buckets_exact keyOf rows),
      build_buckets_exact]
  rw [constructed]
  exact complete_read_all_count keyOf _ keys unique covered row
end Construction

/-! Concrete column projection for table/funs.ss. The cursor moves past each
selected value; its next gap is relative to that successor, not to the prior
column. Optional values expose bounds without assuming a successful native read.
Hash equality and extraction of native field values remain separate contracts. -/
section ColumnProjection
variable {Field : Type}

def orderedFrom : Nat → List Nat → Prop
  | _, [] => True
  | position, column :: rest => position ≤ column ∧ orderedFrom (column + 1) rest

def compileSteps : Nat → List Nat → List Nat
  | _, [] => []
  | position, column :: rest => (column - position) :: compileSteps (column + 1) rest

def recoverColumns : Nat → List Nat → List Nat
  | _, [] => []
  | position, gap :: rest => (position + gap) :: recoverColumns (position + gap + 1) rest

def columnKey (row : List Field) (columns : List Nat) : List (Option Field) :=
  columns.map fun column => (row.drop column).head?

def cursorKey : List Field → List Nat → List (Option Field)
  | _, [] => []
  | row, gap :: rest => (row.drop gap).head? :: cursorKey ((row.drop gap).drop 1) rest

theorem compiled_columns_exact (position : Nat) (columns : List Nat)
    (ordered : orderedFrom position columns) :
    recoverColumns position (compileSteps position columns) = columns := by
  induction columns generalizing position with
  | nil => rfl
  | cons column rest ih =>
      have lowerBound := ordered.1
      have atColumn : position + (column - position) = column := by omega
      simp only [compileSteps, recoverColumns, atColumn]
      exact congrArg (List.cons column) (ih (column + 1) ordered.2)

theorem cursor_columns_exact (row : List Field) (position : Nat) (steps : List Nat) :
    cursorKey (row.drop position) steps = columnKey row (recoverColumns position steps) := by
  induction steps generalizing position with
  | nil => rfl
  | cons gap rest ih =>
      simpa only [cursorKey, columnKey, recoverColumns, List.map_cons, List.drop_drop]
        using congrArg (List.cons ((row.drop (position + gap)).head?))
          (ih (position + gap + 1))

theorem stepped_projection_exact (row : List Field) (columns : List Nat)
    (ordered : orderedFrom 0 columns) :
    cursorKey row (compileSteps 0 columns) = columnKey row columns := by
  have cursor := cursor_columns_exact row 0 (compileSteps 0 columns)
  simpa only [List.drop_zero, compiled_columns_exact 0 columns ordered] using cursor

-- Construction derives routing equality from the actual projection compiler;
-- no supplied keyOf equality or candidate coverage is required.
theorem stepped_build_exact [DecidableEq Field] (rows : List (List Field))
    (columns : List Nat) (ordered : orderedFrom 0 columns) (key : List (Option Field)) :
    buildBuckets (fun row => cursorKey row (compileSteps 0 columns)) rows key =
      keyScan (fun row => columnKey row columns) key rows := by
  have projection : (fun row : List Field => cursorKey row (compileSteps 0 columns)) =
      (fun row : List Field => columnKey row columns) := by
    funext row
    exact stepped_projection_exact row columns ordered
  rw [projection, build_buckets_exact]

theorem stepped_history_exact [DecidableEq Field] (rows : List (List Field))
    (history : List (List (List Field))) (columns : List Nat)
    (ordered : orderedFrom 0 columns) (key : List (Option Field)) :
    replayBuckets (fun row => cursorKey row (compileSteps 0 columns)) history
      (buildBuckets (fun row => cursorKey row (compileSteps 0 columns)) rows) key =
      keyScan (fun row => columnKey row columns) key (replayRows history rows) := by
  rw [replay_buckets_exact _ history _ rows (build_buckets_exact _ rows)]
  have projection : (fun row : List Field => cursorKey row (compileSteps 0 columns)) =
      (fun row : List Field => columnKey row columns) := by
    funext row
    exact stepped_projection_exact row columns ordered
  rw [projection]

def orderedCheck : Nat → List Nat → Bool
  | _, [] => true
  | position, column :: rest => decide (position ≤ column) && orderedCheck (column + 1) rest

theorem ordered_check_iff (position : Nat) (columns : List Nat) :
    orderedCheck position columns = true ↔ orderedFrom position columns := by
  induction columns generalizing position with
  | nil => simp [orderedCheck, orderedFrom]
  | cons column rest ih => simp [orderedCheck, orderedFrom, ih]

def dispatchedKey (row : List Field) (columns : List Nat) : List (Option Field) :=
  if orderedCheck 0 columns then cursorKey row (compileSteps 0 columns)
  else columnKey row columns

theorem dispatched_projection_exact (row : List Field) (columns : List Nat) :
    dispatchedKey row columns = columnKey row columns := by
  unfold dispatchedKey
  split
  · rename_i admitted
    exact stepped_projection_exact row columns ((ordered_check_iff 0 columns).mp admitted)
  · rfl

theorem column_key_missing_iff (row : List Field) (columns : List Nat) :
    none ∈ columnKey row columns ↔ ∃ column ∈ columns, row.length ≤ column := by
  simp [columnKey, List.mem_map]

theorem admitted_projection_present (row : List Field) (columns : List Nat)
    (bounds : ∀ column ∈ columns, column < row.length) :
    none ∉ dispatchedKey row columns := by
  rw [dispatched_projection_exact]
  intro missing
  obtain ⟨column, selected, outside⟩ := (column_key_missing_iff row columns).mp missing
  exact Nat.not_le_of_gt (bounds column selected) outside
end ColumnProjection

/-! Shared-index leaf enumeration and ordinal restoration. Branches describe a
finite hash traversal, whose leaf completeness is a native representation
contract. Algebra does not assume any particular hash visitation order. -/
section OrdinalCollection
variable {RecordRow : Type}

inductive RecordTree (R : Type) where
  | leaf (records : List (Nat × R))
  | fork (left right : RecordTree R)

def flattenRecords : RecordTree RecordRow → List (Nat × RecordRow)
  | .leaf records => records
  | .fork left right => flattenRecords right ++ flattenRecords left

def collectRecords : RecordTree RecordRow → List (Nat × RecordRow) → List (Nat × RecordRow)
  | .leaf records, tail => records ++ tail
  | .fork left right, tail => collectRecords right (collectRecords left tail)

theorem collect_tail_exact (tree : RecordTree RecordRow) (tail : List (Nat × RecordRow)) :
    collectRecords tree tail = flattenRecords tree ++ tail := by
  induction tree generalizing tail with
  | leaf records => rfl
  | fork left right ihl ihr => simp [collectRecords, flattenRecords, ihl, ihr, List.append_assoc]

def leafCopies : RecordTree RecordRow → Nat
  | .leaf records => records.length
  | .fork left right => leafCopies left + leafCopies right

def subtreeCopies : RecordTree RecordRow → Nat
  | .leaf records => records.length
  | .fork left right => subtreeCopies left + subtreeCopies right +
      (flattenRecords left).length + (flattenRecords right).length

theorem leaf_copies_exact (tree : RecordTree RecordRow) :
    leafCopies tree = (flattenRecords tree).length := by
  induction tree with
  | leaf records => rfl
  | fork left right ihl ihr => simp [leafCopies, flattenRecords, ihl, ihr, Nat.add_comm]

theorem collection_copies_le (tree : RecordTree RecordRow) :
    leafCopies tree ≤ subtreeCopies tree := by
  induction tree with
  | leaf records => exact Nat.le_refl _
  | fork left right ihl ihr => simp only [leafCopies, subtreeCopies]; omega

def numberRows (next : Nat) : List RecordRow → List (Nat × RecordRow)
  | [] => []
  | row :: rest => (next, row) :: numberRows (next + 1) rest

theorem numbered_values_exact (next : Nat) (rows : List RecordRow) :
    (numberRows next rows).map Prod.snd = rows := by
  induction rows generalizing next with
  | nil => rfl
  | cons row rest ih => simp [numberRows, ih]

theorem numbered_lower_bound (next : Nat) (rows : List RecordRow)
    (record : Nat × RecordRow) (member : record ∈ numberRows next rows) :
    next ≤ record.1 := by
  induction rows generalizing next with
  | nil => simp [numberRows] at member
  | cons row rest ih =>
      simp only [numberRows, List.mem_cons] at member
      rcases member with equal | member
      · subst record; exact Nat.le_refl _
      · have bound := ih (next + 1) member; omega

theorem numbered_strict_order (next : Nat) (rows : List RecordRow) :
    (numberRows next rows).Pairwise (fun a b => a.1 < b.1) := by
  induction rows generalizing next with
  | nil => simp [numberRows]
  | cons row rest ih =>
      simp only [numberRows, List.pairwise_cons]
      exact ⟨fun record member => by
        have bound := numbered_lower_bound (next + 1) rest record member
        exact Nat.lt_of_lt_of_le (Nat.lt_succ_self next) bound, ih (next + 1)⟩

theorem numbered_upper_bound (next : Nat) (rows : List RecordRow)
    (record : Nat × RecordRow) (member : record ∈ numberRows next rows) :
    record.1 < next + rows.length := by
  induction rows generalizing next with
  | nil => simp [numberRows] at member
  | cons row rest ih =>
      simp only [numberRows, List.mem_cons] at member
      rcases member with equal | member
      · subst record; simp only [List.length_cons]; omega
      · have bound := ih (next + 1) member
        simp only [List.length_cons]; omega

def extendNumbered (next : Nat) (prior : List (Nat × RecordRow)) (batch : List RecordRow) :=
  (numberRows next batch).reverse ++ prior

theorem extended_ordinal_order (next : Nat) (prior : List (Nat × RecordRow))
    (batch : List RecordRow) (ordered : prior.Pairwise (fun a b => b.1 < a.1))
    (bounded : ∀ record ∈ prior, record.1 < next) :
    (extendNumbered next prior batch).Pairwise (fun a b => b.1 < a.1) := by
  apply List.pairwise_append.mpr
  refine ⟨List.pairwise_reverse.mpr (numbered_strict_order next batch), ordered, ?_⟩
  intro a am b bm
  have lower := numbered_lower_bound next batch a (List.mem_reverse.mp am)
  have upper := bounded b bm
  omega

theorem extended_ordinal_bound (next : Nat) (prior : List (Nat × RecordRow))
    (batch : List RecordRow) (bounded : ∀ record ∈ prior, record.1 < next) :
    ∀ record ∈ extendNumbered next prior batch, record.1 < next + batch.length := by
  intro record member
  rcases List.mem_append.mp member with fresh | previous
  · exact numbered_upper_bound next batch record (List.mem_reverse.mp fresh)
  · have bound := bounded record previous; omega

def replayNumbered (next : Nat) (prior : List (Nat × RecordRow)) :
    List (List RecordRow) → Nat × List (Nat × RecordRow)
  | [] => (next, prior)
  | batch :: rest => replayNumbered (next + batch.length) (extendNumbered next prior batch) rest

theorem numbered_history_order (history : List (List RecordRow)) (next : Nat)
    (prior : List (Nat × RecordRow)) (ordered : prior.Pairwise (fun a b => b.1 < a.1))
    (bounded : ∀ record ∈ prior, record.1 < next) :
    (replayNumbered next prior history).2.Pairwise (fun a b => b.1 < a.1) ∧
      ∀ record ∈ (replayNumbered next prior history).2,
        record.1 < (replayNumbered next prior history).1 := by
  induction history generalizing next prior with
  | nil => exact ⟨ordered, bounded⟩
  | cons batch rest ih =>
      exact ih _ _ (extended_ordinal_order next prior batch ordered bounded)
        (extended_ordinal_bound next prior batch bounded)

theorem numbered_history_values (history : List (List RecordRow)) (next : Nat)
    (prior : List (Nat × RecordRow)) :
    (replayNumbered next prior history).2.map Prod.snd = replayRows history (prior.map Prod.snd) := by
  induction history generalizing next prior with
  | nil => rfl
  | cons batch rest ih =>
      simpa only [replayNumbered, replayRows, extendNumbered, List.map_append,
        List.map_reverse, numbered_values_exact] using ih (next + batch.length) (extendNumbered next prior batch)

theorem strict_ordinal_unique (records : List (Nat × RecordRow))
    (ordered : records.Pairwise (fun a b => b.1 < a.1))
    (a b : Nat × RecordRow) (am : a ∈ records) (bm : b ∈ records)
    (same : a.1 = b.1) : a = b := by
  induction records with
  | nil => simp at am
  | cons head tail ih =>
      rcases List.mem_cons.mp am with equalA | inA
      · rcases List.mem_cons.mp bm with equalB | inB
        · exact equalA.trans equalB.symm
        · have strict := (List.pairwise_cons.mp ordered).1 b inB
          have ordinal := congrArg Prod.fst equalA
          omega
      · rcases List.mem_cons.mp bm with equalB | inB
        · have strict := (List.pairwise_cons.mp ordered).1 a inA
          have ordinal := congrArg Prod.fst equalB
          omega
        · exact ih (List.pairwise_cons.mp ordered).2 inA inB

def restoreRecords (records : List (Nat × RecordRow)) : List (Nat × RecordRow) :=
  records.mergeSort fun a b => decide (b.1 ≤ a.1)

-- The native sort uses strict >. Its primitive permutation/order contract
-- has the same unique result as the total comparator used by Lean mergeSort.
theorem native_strict_sort_exact (canonical output : List (Nat × RecordRow))
    (ordered : canonical.Pairwise (fun a b => b.1 < a.1))
    (sorted : output.Pairwise (fun a b => b.1 < a.1))
    (permutation : output.Perm canonical) : output = canonical := by
  exact List.Perm.eq_of_pairwise (fun _ _ _ _ ab ba => by omega) sorted ordered permutation

theorem restored_occurrences_exact (canonical gathered : List (Nat × RecordRow))
    (ordered : canonical.Pairwise (fun a b => b.1 < a.1))
    (enumerated : gathered.Perm canonical) : restoreRecords gathered = canonical := by
  have permutation := (List.mergeSort_perm gathered (fun a b => decide (b.1 ≤ a.1))).trans enumerated
  apply List.Perm.eq_of_pairwise (le := fun a b : Nat × RecordRow => b.1 ≤ a.1) ?_ ?_ ?_ permutation
  · intro a b am bm ab ba
    exact strict_ordinal_unique canonical ordered a b (permutation.subset am) bm (by omega)
  · have sorted := List.pairwise_mergeSort
      (le := fun a b : Nat × RecordRow => decide (b.1 ≤ a.1))
      (fun a b c ab bc => by simp only [decide_eq_true_eq] at *; omega)
      (fun a b => by simp only [Bool.or_eq_true, decide_eq_true_eq]; omega) gathered
    exact sorted.imp (fun h => by simpa using h)
  · exact ordered.imp (fun h => Nat.le_of_lt h)

theorem constructed_ordinal_restore (rows : List RecordRow) (next : Nat)
    (gathered : List (Nat × RecordRow))
    (enumerated : gathered.Perm (numberRows next rows.reverse).reverse) :
    (restoreRecords gathered).map Prod.snd = rows := by
  have ordered : (numberRows next rows.reverse).reverse.Pairwise (fun a b => b.1 < a.1) :=
    List.pairwise_reverse.mpr (numbered_strict_order next rows.reverse)
  rw [restored_occurrences_exact _ _ ordered enumerated, List.map_reverse,
    numbered_values_exact, List.reverse_reverse]

theorem constructed_history_restore (source : List RecordRow) (history : List (List RecordRow))
    (gathered : List (Nat × RecordRow))
    (enumerated : gathered.Perm
      (replayNumbered (source.length + 1) (numberRows 1 source.reverse).reverse history).2) :
    (restoreRecords gathered).map Prod.snd = replayRows history source := by
  have ordered := List.pairwise_reverse.mpr (numbered_strict_order 1 source.reverse)
  have bounded : ∀ record ∈ (numberRows 1 source.reverse).reverse, record.1 < source.length + 1 := by
    intro record member
    have bound := numbered_upper_bound 1 source.reverse record (List.mem_reverse.mp member)
    simpa only [List.length_reverse, Nat.add_comm] using bound
  have invariant := numbered_history_order history (source.length + 1) _ ordered bounded
  rw [restored_occurrences_exact _ _ invariant.1 enumerated, numbered_history_values,
    List.map_reverse, numbered_values_exact, List.reverse_reverse]

theorem constructed_prefix_restore (source : List RecordRow) (history : List (List RecordRow))
    (selected : RecordRow → Bool) (gathered : List (Nat × RecordRow))
    (enumerated : gathered.Perm
      ((replayNumbered (source.length + 1) (numberRows 1 source.reverse).reverse history).2.filter
        (fun record => selected record.2))) :
    (restoreRecords gathered).map Prod.snd = (replayRows history source).filter selected := by
  have ordered := List.pairwise_reverse.mpr (numbered_strict_order 1 source.reverse)
  have bounded : ∀ record ∈ (numberRows 1 source.reverse).reverse, record.1 < source.length + 1 := by
    intro record member
    have bound := numbered_upper_bound 1 source.reverse record (List.mem_reverse.mp member)
    simpa only [List.length_reverse, Nat.add_comm] using bound
  have invariant := numbered_history_order history (source.length + 1) _ ordered bounded
  rw [restored_occurrences_exact _ _ (invariant.1.filter _) enumerated]
  have values := numbered_history_values history (source.length + 1) (numberRows 1 source.reverse).reverse
  simp only [List.map_reverse, numbered_values_exact, List.reverse_reverse] at values
  rw [← values, List.filter_map]
  rfl
end OrdinalCollection

/-! A depth-indexed curried dictionary. Functional branches model the map
lookup/update contract; a finite unique key inventory models child enumeration.
The depth is a parameter, not a runtime arity or generation bound. -/
section CurriedConstruction
variable {K R : Type} [DecidableEq K]

def CurriedTrie (K R : Type) : Nat → Type
  | 0 => List R
  | depth + 1 => K → CurriedTrie K R depth

def trieBuild : (depth : Nat) → (R → Nat → K) → List R → CurriedTrie K R depth
  | 0, _, rows => rows
  | depth + 1, coordinate, rows => fun key =>
      trieBuild depth (fun row i => coordinate row (i + 1))
        (keyScan (fun row => coordinate row 0) key rows)

def trieInsert : (depth : Nat) → (R → Nat → K) → R →
    CurriedTrie K R depth → CurriedTrie K R depth
  | 0, _, row, tree => row :: tree
  | depth + 1, coordinate, row, tree => fun key =>
      if key = coordinate row 0 then
        trieInsert depth (fun row i => coordinate row (i + 1)) row (tree key)
      else tree key

def trieCollect (keys : List K) : (depth : Nat) → CurriedTrie K R depth → List R
  | 0, tree => tree
  | depth + 1, tree => keys.flatMap fun key => trieCollect keys depth (tree key)

def trieRead (keys : List K) : (depth : Nat) → List K → CurriedTrie K R depth → List R
  | depth, [], tree => trieCollect keys depth tree
  | 0, _ :: _, _ => []
  | depth + 1, key :: rest, tree => trieRead keys depth rest (tree key)

def prefixSelected : Nat → (R → Nat → K) → List K → R → Bool
  | _, _, [], _ => true
  | 0, _, _ :: _, _ => false
  | depth + 1, coordinate, key :: rest, row =>
      (coordinate row 0 == key) &&
        prefixSelected depth (fun row i => coordinate row (i + 1)) rest row

theorem trie_insert_build (depth : Nat) (coordinate : R → Nat → K)
    (row : R) (rows : List R) :
    trieInsert depth coordinate row (trieBuild depth coordinate rows) =
      trieBuild depth coordinate (row :: rows) := by
  induction depth generalizing coordinate rows with
  | zero => rfl
  | succ depth ih =>
    funext key
    by_cases hit : key = coordinate row 0
    · simp [trieInsert, trieBuild, keyScan, hit, ih]
    · simp [trieInsert, trieBuild, keyScan, hit, Ne.symm hit]

def triePrepend (depth : Nat) (coordinate : R → Nat → K) :
    List R → CurriedTrie K R depth → CurriedTrie K R depth
  | [], tree => tree
  | row :: rest, tree => triePrepend depth coordinate rest (trieInsert depth coordinate row tree)

def trieReplay (depth : Nat) (coordinate : R → Nat → K) :
    List (List R) → CurriedTrie K R depth → CurriedTrie K R depth
  | [], tree => tree
  | batch :: rest, tree => trieReplay depth coordinate rest (triePrepend depth coordinate batch tree)

theorem trie_prepend_build (depth : Nat) (coordinate : R → Nat → K)
    (batch rows : List R) :
    triePrepend depth coordinate batch (trieBuild depth coordinate rows) =
      trieBuild depth coordinate (batch.reverse ++ rows) := by
  induction batch generalizing rows with
  | nil => rfl
  | cons row rest ih =>
    rw [triePrepend, trie_insert_build, ih]
    simp [List.reverse_cons, List.append_assoc]

theorem trie_replay_build (depth : Nat) (coordinate : R → Nat → K)
    (history : List (List R)) (rows : List R) :
    trieReplay depth coordinate history (trieBuild depth coordinate rows) =
      trieBuild depth coordinate (replayRows history rows) := by
  induction history generalizing rows with
  | nil => rfl
  | cons batch rest ih => rw [trieReplay, trie_prepend_build, ih]; rfl

theorem trie_collect_build_count [DecidableEq R] (depth : Nat)
    (coordinate : R → Nat → K) (rows : List R) (keys : List K)
    (unique : keys.Nodup)
    (covered : ∀ row ∈ rows, ∀ i < depth, coordinate row i ∈ keys) (row : R) :
    (trieCollect keys depth (trieBuild depth coordinate rows)).count row = rows.count row := by
  induction depth generalizing coordinate rows with
  | zero => rfl
  | succ depth ih =>
    have children (key : K) :
        (trieCollect keys depth (trieBuild depth (fun row i => coordinate row (i + 1))
          (keyScan (fun row => coordinate row 0) key rows))).count row =
        (keyScan (fun row => coordinate row 0) key rows).count row := by
      apply ih
      intro candidate member i bound
      exact covered candidate (List.mem_filter.mp member).1 (i + 1) (Nat.succ_lt_succ bound)
    simp only [trieCollect, trieBuild, List.count_flatMap]
    simp only [Function.comp_def, children]
    have exactCount := complete_read_all_count (fun row => coordinate row 0) rows keys unique
      (fun candidate member => covered candidate member 0 (Nat.zero_lt_succ depth)) row
    simpa only [enumerateBuckets, List.count_flatMap, Function.comp_def, build_buckets_exact] using exactCount

theorem trie_collect_build_perm [DecidableEq R] (depth : Nat)
    (coordinate : R → Nat → K) (rows : List R) (keys : List K)
    (unique : keys.Nodup)
    (covered : ∀ row ∈ rows, ∀ i < depth, coordinate row i ∈ keys) :
    (trieCollect keys depth (trieBuild depth coordinate rows)).Perm rows := by
  exact List.perm_iff_count.mpr (trie_collect_build_count depth coordinate rows keys unique covered)

theorem trie_read_build_perm [DecidableEq R] (depth : Nat)
    (coordinate : R → Nat → K) (rows : List R) (keys query : List K)
    (unique : keys.Nodup)
    (covered : ∀ row ∈ rows, ∀ i < depth, coordinate row i ∈ keys) :
    (trieRead keys depth query (trieBuild depth coordinate rows)).Perm
      (rows.filter (prefixSelected depth coordinate query)) := by
  have allRows (input : List R) : input.filter (fun _ => true) = input :=
    List.filter_eq_self.mpr (by intro _ _; rfl)
  induction depth generalizing coordinate rows query with
  | zero => cases query <;> simp [trieRead, trieCollect, trieBuild, prefixSelected, allRows]
  | succ depth ih =>
    cases query with
    | nil => simpa [trieRead, prefixSelected, allRows] using
        trie_collect_build_perm (depth + 1) coordinate rows keys unique covered
    | cons key rest =>
      have tailCovered : ∀ candidate ∈ keyScan (fun row => coordinate row 0) key rows,
          ∀ i < depth, coordinate candidate (i + 1) ∈ keys := by
        intro candidate member i bound
        exact covered candidate (List.mem_filter.mp member).1 (i + 1) (Nat.succ_lt_succ bound)
      have recursive := ih (fun row i => coordinate row (i + 1))
        (keyScan (fun row => coordinate row 0) key rows) rest tailCovered
      simpa [trieRead, trieBuild, keyScan, List.filter_filter, prefixSelected, Bool.and_comm] using recursive
theorem prefix_selected_projection {Row : Type} (depth : Nat)
    (coordinate : Row → Nat → K) (query : List K) (project : R → Row) (row : R) :
    prefixSelected depth (fun r => coordinate (project r)) query row =
      prefixSelected depth coordinate query (project row) := by
  induction depth generalizing coordinate query with
  | zero => cases query <;> rfl
  | succ depth ih =>
    cases query with
    | nil => rfl
    | cons key rest =>
      exact congrArg (fun selected => (coordinate (project row) 0 == key) && selected)
        (ih (fun row i => coordinate row (i + 1)) rest)

def trieNumberedReplay {Row : Type} (depth : Nat) (coordinate : (Nat × Row) → Nat → K) :
    Nat → List (List Row) → CurriedTrie K (Nat × Row) depth → CurriedTrie K (Nat × Row) depth
  | _, [], tree => tree
  | next, batch :: rest, tree =>
      trieNumberedReplay depth coordinate (next + batch.length) rest
        (triePrepend depth coordinate (numberRows next batch) tree)

theorem trie_numbered_replay_build {Row : Type} (depth : Nat)
    (coordinate : (Nat × Row) → Nat → K) (next : Nat)
    (history : List (List Row)) (prior : List (Nat × Row)) :
    trieNumberedReplay depth coordinate next history (trieBuild depth coordinate prior) =
      trieBuild depth coordinate (replayNumbered next prior history).2 := by
  induction history generalizing next prior with
  | nil => rfl
  | cons batch rest ih =>
      rw [trieNumberedReplay, trie_prepend_build, ih]
      rfl

theorem trie_numbered_prefix_restore {Row : Type} [DecidableEq Row]
    (depth : Nat) (coordinate : Row → Nat → K) (source : List Row)
    (history : List (List Row)) (keys query : List K) (unique : keys.Nodup)
    (covered : ∀ record ∈
      (replayNumbered (source.length + 1) (numberRows 1 source.reverse).reverse history).2,
      ∀ i < depth, coordinate record.2 i ∈ keys) :
    (restoreRecords (trieRead keys depth query
      (trieNumberedReplay depth (fun record : Nat × Row => coordinate record.2)
        (source.length + 1) history
        (trieBuild depth (fun record : Nat × Row => coordinate record.2)
          (numberRows 1 source.reverse).reverse)))).map
      Prod.snd = (replayRows history source).filter (prefixSelected depth coordinate query) := by
  rw [trie_numbered_replay_build]
  apply constructed_prefix_restore
  have enumerated := trie_read_build_perm depth
    (fun record : Nat × Row => coordinate record.2) _ keys query unique covered
  have lifted : prefixSelected depth (fun record : Nat × Row => coordinate record.2) query =
      (fun record => prefixSelected depth coordinate query record.2) :=
    funext (fun record => prefix_selected_projection depth coordinate query Prod.snd record)
  rw [lifted] at enumerated
  exact enumerated
end CurriedConstruction
end Ascent.ProviderRouting
