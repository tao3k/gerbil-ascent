/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Operational trace of certificate-for-each-while: each boolean is invocation
liveness after one visited callback, not its return value. Frozen enumeration,
binding and budget admission are separate premises. No heap/time bound claimed.
-/
import Std
namespace Ascent.TerminalTraversal

def trace (live : Bool) : List Bool → List Bool
  | [] => []
  | b :: rest => if live then b :: trace b rest else []

theorem stopped (xs : List Bool) : trace false xs = [] := by
  cases xs <;> rfl

theorem length_bound (live : Bool) (xs : List Bool) :
    (trace live xs).length ≤ xs.length := by
  induction xs generalizing live with
  | nil => simp [trace]
  | cons b rest ih => cases live <;> simp [trace]; exact ih b

theorem trace_append (live : Bool) (xs ys : List Bool) :
    trace live (xs ++ ys) = trace live xs ++ trace (live && xs.all id) ys := by
  induction xs generalizing live with
  | nil => simp [trace]
  | cons b rest ih =>
    cases live <;> cases b <;> simp [trace, stopped, ih]

theorem refused_suffix (xs ys : List Bool) (h : xs.all id = false) :
    trace true (xs ++ ys) = trace true xs := by
  rw [trace_append, h]
  simp [stopped]

theorem complete_trace (xs : List Bool) (h : xs.all id = true) :
    trace true xs = xs := by
  induction xs with
  | nil => rfl
  | cons b rest ih =>
    cases b <;> simp_all [trace]

end Ascent.TerminalTraversal
