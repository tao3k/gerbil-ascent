/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
Ordered buckets preserve direct scan order including duplicate outputs.
Native hash equality, descriptor admission and ownership remain premises.
-/
import Std
namespace Ascent.OrderedMapping
variable {Key Value : Type} [DecidableEq Key]
def scan (key : Key) (rows : List (Key × Value)) : List Value :=
  (rows.filter (fun row => decide (row.1 = key))).map Prod.snd
def prependBucket (key : Key) : List (Key × Value) → List Value → List Value
  | [], seed => seed
  | row :: rest, seed =>
      prependBucket key rest (if row.1 = key then row.2 :: seed else seed)
theorem prepend_eq_reverse_scan (key : Key) (rows : List (Key × Value))
    (seed : List Value) :
    prependBucket key rows seed = (scan key rows).reverse ++ seed := by
  induction rows generalizing seed with
  | nil => simp [prependBucket, scan]
  | cons row rest ih =>
    by_cases hit : row.1 = key
    · simp [prependBucket, scan, hit, ih, List.reverse_cons, List.append_assoc]
    · simp [prependBucket, scan, hit, ih]
def lookup (key : Key) (rows : List (Key × Value)) : List Value :=
  (prependBucket key rows []).reverse
theorem lookup_eq_scan (key : Key) (rows : List (Key × Value)) :
    lookup key rows = scan key rows := by
  simp [lookup, prepend_eq_reverse_scan]
theorem batch_eq_scan (keys : List Key) (rows : List (Key × Value)) :
    keys.flatMap (fun key => lookup key rows) =
      keys.flatMap (fun key => scan key rows) := by
  simp only [lookup_eq_scan]
theorem lookup_membership (key : Key) (rows : List (Key × Value)) (value : Value) :
    value ∈ lookup key rows ↔ ∃ row ∈ rows, row.1 = key ∧ row.2 = value := by
  rw [lookup_eq_scan]
  simp only [scan, List.mem_map, List.mem_filter, decide_eq_true_eq]
  constructor
  · rintro ⟨row, ⟨member, hit⟩, output⟩
    exact ⟨row, member, hit, output⟩
  · rintro ⟨row, member, hit, output⟩
    exact ⟨row, ⟨member, hit⟩, output⟩
end Ascent.OrderedMapping
