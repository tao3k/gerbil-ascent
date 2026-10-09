/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
Completed numeric reductions in candidate/finite-evidence.ss. `none` inputs
represent noninteger matching values. Native still charges remaining probes
after type failure; budget/publication traces belong to Quint.
-/
import Std
namespace Ascent.NumericReduction
inductive Mode where | sum | min | max
  deriving DecidableEq, Repr
def combine (mode : Mode) (acc : Option Int) (value : Int) : Option Int :=
  some (match mode with
    | .sum => acc.getD 0 + value
    | .min => acc.map (fun prior => min prior value) |>.getD value
    | .max => acc.map (fun prior => max prior value) |>.getD value)
def numericFold (mode : Mode) (acc : Option Int) : List (Option Int) → Option Int
  | [] => acc
  | none :: _ => none
  | some value :: rest => numericFold mode (combine mode acc value) rest
def reduce (mode : Mode) (values : List (Option Int)) : Option Int :=
  numericFold mode (if mode = .sum then some 0 else none) values

theorem sum_with_seed (values : List Int) (acc : Int) :
    numericFold .sum (some acc) (values.map some) = some (acc + values.sum) := by
  induction values generalizing acc with
  | nil => simp [numericFold]
  | cons value rest ih =>
    change numericFold .sum (some (acc + value)) (rest.map some) = some (acc + (value + rest.sum))
    rw [ih]; congr 1; omega
theorem sum_correct (values : List Int) :
    reduce .sum (values.map some) = some values.sum := by
  simpa [reduce] using sum_with_seed values 0
theorem min_with_seed (values : List Int) (acc : Int) :
    numericFold .min (some acc) (values.map some) = some (values.foldl min acc) := by
  induction values generalizing acc with
  | nil => rfl
  | cons value rest ih => simpa [numericFold, combine] using ih (min acc value)
theorem min_correct (values : List Int) :
    reduce .min (values.map some) = values.min? := by
  cases values with
  | nil => rfl
  | cons value rest =>
    change numericFold .min (some value) (rest.map some) = some (rest.foldl min value)
    exact min_with_seed rest value
theorem max_with_seed (values : List Int) (acc : Int) :
    numericFold .max (some acc) (values.map some) = some (values.foldl max acc) := by
  induction values generalizing acc with
  | nil => rfl
  | cons value rest ih => simpa [numericFold, combine] using ih (max acc value)
theorem max_correct (values : List Int) :
    reduce .max (values.map some) = values.max? := by
  cases values with
  | nil => rfl
  | cons value rest =>
    change numericFold .max (some value) (rest.map some) = some (rest.foldl max value)
    exact max_with_seed rest value
theorem invalid_suffix (mode : Mode) (initial later : List (Option Int)) (acc : Option Int) :
    numericFold mode acc (initial ++ none :: later) = none := by
  induction initial generalizing acc with
  | nil => rfl
  | cons value rest ih => cases value <;> simp [numericFold, ih]
theorem empty_results : reduce .sum [] = some 0 ∧ reduce .min [] = none ∧ reduce .max [] = none := by
  decide
end Ascent.NumericReduction
