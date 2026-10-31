/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
Streaming count in candidate/finite-evidence.ss. Binding outcomes are supplied;
this does not prove native binding, frozen enumeration or a heap bound.
-/
import Std
namespace Ascent.CountReduction
def countFold (count : Nat) : List Bool → Nat
  | [] => count
  | matched :: rest => countFold (if matched then count + 1 else count) rest

theorem count_exact (rows : List Bool) (count : Nat) :
    countFold count rows = count + (rows.filter id).length := by
  induction rows generalizing count with
  | nil => simp [countFold]
  | cons matched rest ih =>
    cases matched <;> simp [countFold, ih] <;> omega

theorem count_append (first later : List Bool) (count : Nat) :
    countFold count (first ++ later) = countFold (countFold count first) later := by
  induction first generalizing count with
  | nil => rfl
  | cons matched rest ih => simp [countFold, ih]

theorem unmatched_unchanged (rows : List Bool) (count : Nat) :
    countFold count (false :: rows) = countFold count rows := rfl

theorem suffix_exact (first later : List Bool) (count : Nat) :
    countFold count (first ++ later) = countFold count first + (later.filter id).length := by
  rw [count_append, count_exact]

theorem binding_count_exact (rows : List row) (predicate : row → Bool) :
    countFold 0 (rows.map predicate) = (rows.filter predicate).length := by
  rw [count_exact]
  simp [List.filter_map]
end Ascent.CountReduction
