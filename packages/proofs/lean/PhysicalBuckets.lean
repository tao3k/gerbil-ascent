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

end Ascent.PhysicalBuckets
