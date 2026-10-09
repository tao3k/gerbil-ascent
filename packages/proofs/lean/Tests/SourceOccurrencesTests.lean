/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-/
import SourceOccurrences
open Ascent.SourceOccurrences
example : withdraw [10, 10, 20] [1] = [10, 20] := by decide
example : withdraw (withdraw [10, 10, 20] [1]) [1] = [20] := by decide
example : withdraw [10, 10, 20] [1, 2] = [20] := by decide
example : withdraw [10, 20] [2] = [10] := by decide
example : withdraw (withdraw [10, 10, 20] [1]) [1] ≠ [10] := by decide

example (old next later : Cut (List Nat) (List Nat))
    (advance : next.generation = old.generation + 1) :
    publish next later old.generation true = next :=
  competing_request_rejected old next later advance

example : publish (Cut.mk 1 [20] [20]) (Cut.mk 2 [] []) 0 true =
    (Cut.mk 1 [20] [20]) := by decide

-- Edge-only admission fits, but twenty-five inspected premises exhaust it.
example : publishBounded (Cut.mk 0 [1] [1]) (Cut.mk 1 [] []) 0 9 25 1 16 =
    (Cut.mk 0 [1] [1]) := by decide
example : publishBounded (Cut.mk 0 [1] [1]) (Cut.mk 1 [] []) 0 9 25 1 35 =
    (Cut.mk 1 [] []) := by decide
example : publishBounded (Cut.mk 0 [1] [1]) (Cut.mk 1 [] []) 0 9 25 1 34 =
    (Cut.mk 0 [1] [1]) := by decide
