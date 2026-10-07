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
end Ascent.ProviderRouting
