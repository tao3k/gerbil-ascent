-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Operational bucket construction: Scheme hash-update prepends and reverses
fresh buckets; Rust entry.push appends. No IndexExact premise is assumed here.
get/put coherence and lawful key equality are the hash-map primitive boundary.
Rows and duplicate occurrences are preserved; hash collisions require ordinary
key comparison, rather than treating a digest as an equality certificate. -/
namespace Ascent.PhysicalBuckets
variable {Key Row : Type} [DecidableEq Key]
abbrev Buckets (Key Row : Type) := Key → List Row

def prepend (key : Row → Key) (before : Buckets Key Row) (row : Row) : Buckets Key Row :=
  fun wanted => if wanted = key row then row :: before wanted else before wanted
def append (key : Row → Key) (before : Buckets Key Row) (row : Row) : Buckets Key Row :=
  fun wanted => if wanted = key row then before wanted ++ [row] else before wanted
def extend (update : Buckets Key Row → Row → Buckets Key Row)
    (before : Buckets Key Row) (rows : List Row) : Buckets Key Row := rows.foldl update before

theorem prepend_lookup (key : Row → Key) (rows : List Row)
    (before : Buckets Key Row) (wanted : Key) :
    extend (prepend key) before rows wanted =
      (rows.filter (fun row => decide (wanted = key row))).reverse ++ before wanted := by
  induction rows generalizing before with
  | nil => rfl
  | cons row rest ih =>
      simp only [extend, List.foldl_cons]
      rw [show rest.foldl (prepend key) (prepend key before row) wanted =
        (rest.filter (fun row => decide (wanted = key row))).reverse ++ prepend key before row wanted from ih _]
      by_cases same : wanted = key row <;> simp [same, prepend, List.append_assoc]

theorem append_lookup (key : Row → Key) (rows : List Row)
    (before : Buckets Key Row) (wanted : Key) :
    extend (append key) before rows wanted =
      before wanted ++ rows.filter (fun row => decide (wanted = key row)) := by
  induction rows generalizing before with
  | nil => simp [extend]
  | cons row rest ih =>
      simp only [extend, List.foldl_cons]
      rw [show rest.foldl (append key) (append key before row) wanted =
        append key before row wanted ++ rest.filter (fun row => decide (wanted = key row)) from ih _]
      by_cases same : wanted = key row <;> simp [same, append, List.append_assoc]

theorem scheme_build_exact (key : Row → Key) (rows : List Row) (wanted : Key) :
    (extend (prepend key) (fun _ => []) rows wanted).reverse =
      rows.filter (fun row => decide (wanted = key row)) := by simp [prepend_lookup]

theorem extension_coverage (key : Row → Key) (rows : List Row)
    (before : Buckets Key Row) (wanted : Key) (row : Row) :
    row ∈ extend (prepend key) before rows wanted ↔
      (row ∈ rows ∧ wanted = key row) ∨ row ∈ before wanted := by simp [prepend_lookup]

theorem rust_build_exact (key : Row → Key) (rows : List Row) (wanted : Key) :
    extend (append key) (fun _ => []) rows wanted =
      rows.filter (fun row => decide (wanted = key row)) := by simp [append_lookup]

theorem other_keys_unchanged (key : Row → Key) (rows : List Row)
    (before : Buckets Key Row) (wanted : Key)
    (absent : ∀ row ∈ rows, wanted ≠ key row) :
    extend (prepend key) before rows wanted = before wanted := by
  rw [prepend_lookup]
  have empty : rows.filter (fun row => decide (wanted = key row)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro row member
    simp [absent row member]
  simp [empty]

/-! The actor source index owns one newest-first source lane per retained
slot. It extracts the exact added prefix before extending native buckets.
List elements in the scan can identify owned spine cells. Equality at the
suffix boundary abstracts the native pointer check and implies equality of
that whole suffix; equal counts alone do not imply it. -/
def appendScan [DecidableEq Row] (prior : List Row) :
    Nat → List Row → List Row → Option (List Row)
  | 0, rest, chronological => if rest = prior then some chronological else none
  | _ + 1, [], _ => none
  | count + 1, row :: rest, chronological =>
      appendScan prior count rest (row :: chronological)

theorem append_scan_exact [DecidableEq Row] (prior rows chronological : List Row)
    (count : Nat) (batch : List Row) :
    appendScan prior count rows chronological = some batch ↔
      ∃ prefixRows : List Row, prefixRows.length = count ∧
        rows = prefixRows ++ prior ∧ batch = prefixRows.reverse ++ chronological := by
  induction count generalizing rows chronological with
  | zero =>
      constructor
      · intro step
        simp only [appendScan] at step
        split at step
        · rename_i matched
          exact ⟨[], rfl, matched, (Option.some.inj step).symm⟩
        · contradiction
      · rintro ⟨head, size, matched, result⟩
        cases head with
        | nil => simp [appendScan, matched, result]
        | cons => simp at size
  | succ count ih =>
      cases rows with
      | nil =>
          constructor
          · simp [appendScan]
          · rintro ⟨head, size, matched, _⟩
            cases head with
            | nil => simp at size
            | cons => simp at matched
      | cons row rest =>
          rw [appendScan, ih]
          constructor
          · rintro ⟨head, size, matched, result⟩
            exact ⟨row :: head, by simp [size], by simp [matched],
              by simpa [List.reverse_cons, List.append_assoc] using result⟩
          · rintro ⟨head, size, matched, result⟩
            cases head with
            | nil => simp at size
            | cons first head =>
                simp only [List.cons_append, List.cons.injEq] at matched
                obtain ⟨rfl, tail⟩ := matched
                exact ⟨head, by simpa using size, tail,
                  by simpa [List.reverse_cons, List.append_assoc] using result⟩

theorem extend_newest_first_exact (key : Row → Key) (old newest : List Row) (wanted : Key) :
    extend (prepend key)
      (fun value => old.filter (fun row => decide (value = key row))) newest.reverse wanted =
      (newest ++ old).filter (fun row => decide (wanted = key row)) := by
  rw [prepend_lookup, List.filter_reverse, List.reverse_reverse, List.filter_append]

theorem actor_append_physical_writes [DecidableEq Row] (prior rows added : List Row)
    (count : Nat) (accepted : appendScan prior count rows [] = some added) :
    added.length = count ∧ rows.length = count + prior.length := by
  obtain ⟨head, size, cut, ordered⟩ := (append_scan_exact prior rows [] count added).mp accepted
  simp [ordered, cut, size]

/-! Replacing an owned source keeps the native table storage only after every
table entry is vacant. Bucket spines already held by a completed consumer are
separate list values. Compaction copies only occupied table entries, keeping
their freshly built bucket spines intact. -/
def copyOccupied (keys : List Key) (table : Buckets Key Row) : Buckets Key Row :=
  fun wanted => if wanted ∈ keys then table wanted else []

theorem occupied_copy_exact (keys : List Key) (table : Buckets Key Row)
    (coverage : ∀ wanted, table wanted ≠ [] → wanted ∈ keys) (wanted : Key) :
    copyOccupied keys table wanted = table wanted := by
  by_cases present : wanted ∈ keys
  · simp [copyOccupied, present]
  · cases bucket : table wanted with
    | nil => simp [copyOccupied, present]
    | cons head tail =>
        exact False.elim (present (coverage wanted (by simp [bucket])))

def rebuildCleared (key : Row → Key) (rows : List Row) (keys : List Key)
    (compact : Bool) : Buckets Key Row :=
  let filled : Buckets Key Row := extend (prepend key) (fun _ => []) rows
  let published := if compact then copyOccupied keys filled else filled
  fun wanted => (published wanted).reverse

theorem refill_after_replacement_exact (key : Row → Key) (rows : List Row)
    (keys : List Key) (compact : Bool) (wanted : Key)
    (coverage : ∀ value, (extend (prepend key) (fun _ => []) rows value) ≠ [] →
      value ∈ keys) :
    rebuildCleared key rows keys compact wanted =
      rows.filter (fun row => decide (wanted = key row)) := by
  cases compact
  · simpa [rebuildCleared] using scheme_build_exact key rows wanted
  · change (copyOccupied keys (extend (prepend key) (fun _ => []) rows) wanted).reverse = _
    rw [occupied_copy_exact keys _ coverage]
    exact scheme_build_exact key rows wanted

/-- Clearing the table and refilling its new buckets cannot change the old
immutable list a previous reader held. These two results name different
owners, even when the native backing vector is reused. -/
theorem replacement_preserves_held_rows (old : Buckets Key Row)
    (key : Row → Key) (rows : List Row) (wanted : Key)
    (held : List Row) (observed : held = old wanted) :
    (held, rebuildCleared key rows [] false wanted) =
      (old wanted, rows.filter (fun row => decide (wanted = key row))) := by
  rw [observed]
  exact congrArg (fun fresh => (old wanted, fresh)) (scheme_build_exact key rows wanted)
/-! A direct scalar row occupies the first entry for its key. The native
layout distinguishes the scalar at its head from a row pair at the head
of a multi-row bucket. This sum type states that representation invariant
without relying on the runtime's tagging scheme. -/
inductive SourceBucket (Row : Type) where
  | direct : Row → SourceBucket Row
  | multiple : Row → Row → List Row → SourceBucket Row

def decodeSourceBucket : Option (SourceBucket Row) → List Row
  | none => []
  | some (.direct row) => [row]
  | some (.multiple first second rest) => first :: second :: rest

def pushSourceBucket (row : Row) : Option (SourceBucket Row) → Option (SourceBucket Row)
  | none => some (.direct row)
  | some (.direct prior) => some (.multiple row prior [])
  | some (.multiple first second rest) => some (.multiple row first (second :: rest))

theorem push_source_bucket_exact (row : Row) (prior : Option (SourceBucket Row)) :
    decodeSourceBucket (pushSourceBucket row prior) = row :: decodeSourceBucket prior := by
  cases prior with
  | none => rfl
  | some bucket => cases bucket <;> rfl

def addSourceRow (key : Row → Key) (before : Key → Option (SourceBucket Row))
    (row : Row) (wanted : Key) : Option (SourceBucket Row) :=
  if wanted = key row then pushSourceBucket row (before wanted) else before wanted

theorem source_bucket_fold_exact (key : Row → Key) (rows : List Row)
    (before : Key → Option (SourceBucket Row)) (wanted : Key) :
    decodeSourceBucket (rows.foldl (addSourceRow key) before wanted) =
      extend (prepend key) (fun k => decodeSourceBucket (before k)) rows wanted := by
  induction rows generalizing before with
  | nil => rfl
  | cons row rest ih =>
      change decodeSourceBucket (rest.foldl (addSourceRow key) (addSourceRow key before row) wanted) =
        extend (prepend key) (prepend key (fun k => decodeSourceBucket (before k)) row) rest wanted
      rw [ih]
      congr 2
      funext k
      by_cases same : k = key row <;> simp [addSourceRow, prepend, same, push_source_bucket_exact]

theorem direct_source_build_preserves_order (key : Row → Key) (rows : List Row) (wanted : Key) :
    (decodeSourceBucket (rows.foldl (addSourceRow key) (fun _ => none) wanted)).reverse =
      rows.filter (fun row => decide (wanted = key row)) := by
  rw [source_bucket_fold_exact]
  exact scheme_build_exact key rows wanted

def storedSourcePairs : Option (SourceBucket Row) → Nat
  | some (.multiple _ _ rest) => rest.length + 2
  | _ => 0

def allocatedSourcePairs : Option (SourceBucket Row) → Nat
  | none => 0
  | some (.direct _) => 2
  | some (.multiple _ _ _) => 1

theorem source_pair_allocation_exact (row : Row) (before : Option (SourceBucket Row)) :
    storedSourcePairs (pushSourceBucket row before) =
      storedSourcePairs before + allocatedSourcePairs before := by
  cases before with
  | none => rfl
  | some bucket => cases bucket <;> simp [storedSourcePairs, allocatedSourcePairs, pushSourceBucket] <;> omega

end Ascent.PhysicalBuckets
