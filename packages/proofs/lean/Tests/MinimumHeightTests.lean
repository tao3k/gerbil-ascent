/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-/
import MinimumHeight
open Ascent.MinimumHeight Ascent.ComponentClosure
example (rules : List (Rule Nat)) (source : Database Nat)
    (height : Nat → Option Nat) (closed : Closed rules source height)
    (attained : ∀ fact h, height fact = some h → Within rules source fact h)
    (read : height 3 = some 1) :
    Within rules source 3 1 ∧ ∀ n, Within rules source 3 n → 1 ≤ n :=
  minimum rules source height closed attained read
-- An empty source cannot found a self-loop, even with arbitrary raising.
example (n : Nat) : ¬ Within [Rule.mk [0] 0] (fun _ => False) 0 n := by
  have impossible (fact height : Nat)
      (proof : Within [Rule.mk [0] 0] (fun _ => False) fact height) : False := by
    induction proof with
    | seed present => exact present
    | raise _ ih => exact ih
    | fire member _ ih =>
      have equal := List.mem_singleton.mp member
      cases equal
      exact ih 0 (by simp)
  exact impossible 0 n
