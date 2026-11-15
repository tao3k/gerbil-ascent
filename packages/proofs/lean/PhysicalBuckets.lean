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

end Ascent.PhysicalBuckets
