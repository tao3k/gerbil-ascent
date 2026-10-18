-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Work observations, not a hardware latency model. GSC invocations consume
concrete hashed inputs. Import allocator snapshots are process-wide/inclusive:
they cannot be added as if nested imports owned disjoint allocation intervals.
The SDK compiler/allocator and the observer/decoder remain outside this proof. -/
namespace Ascent.PreparationWork

-- Importing build.ss evaluates its PackageSpec declaration even when the
-- consumer only requests its module list. The separate data module has no
-- such declaration. Source controls read that module with Gerbil's reader
-- and require exactly an export and a quoted string-list binding.
inductive InventorySource where
  | moduleData
  | buildEntry
  deriving DecidableEq

def inventoryPackageDeclarations : InventorySource → Nat
  | .moduleData => 0
  | .buildEntry => 1

def inventoryImportSchemeSource : String :=
  "        (only-in \"../../build-modules.ss\" gerbil-ascent-library-modules)\n"

theorem module_data_avoids_package_declaration :
    inventoryPackageDeclarations .moduleData = 0 ∧
    inventoryPackageDeclarations .buildEntry = 1 := by decide

abbrev Dependency := List String × List String
def requested (tests : List String) (entry : Dependency) : Bool :=
  entry.1.any tests.contains
def selected (tests : List String) (entries : List Dependency) : List String :=
  (entries.filter (requested tests)).flatMap Prod.snd

-- A declared dependency has no cost effect in a lane that does not request it.
-- In particular scheme-artifact-test is absent from prepare-test-library's
-- performance consumers. Deleting its bridge entry cannot explain that lane.
theorem inactive_dependency_no_work (tests : List String)
    (before after : List Dependency) (entry : Dependency)
    (inactive : requested tests entry = false) :
    selected tests (before ++ entry :: after) = selected tests (before ++ after) := by
  simp [selected, List.filter_append, inactive]

def selectionSchemeSource : String :=
  ";; Generated from PreparationWork.lean; formal CI compares this region.\n" ++
  "(def (preparation-selected-dependencies tests entries)\n" ++
  "  (apply append\n" ++
  "    (map cdr\n" ++
  "      (filter (lambda (entry) (ormap (cut member <> tests) (car entry))) entries))))\n"

structure Work where
  jobs : Nat := 0
  inputBytes : Nat := 0
  deriving DecidableEq, Repr

def Work.plus (a b : Work) : Work :=
  ⟨a.jobs + b.jobs, a.inputBytes + b.inputBytes⟩

def total : List Work → Work
  | [] => ⟨0, 0⟩
  | x :: xs => x.plus (total xs)

theorem total_append (xs ys : List Work) :
    total (xs ++ ys) = (total xs).plus (total ys) := by
  induction xs with
  | nil => simp [total, Work.plus]
  | cons x xs ih => simp [total, ih, Work.plus, Nat.add_assoc]

-- Removing two observed GSC records retains every other record. A module
-- or logical compile-file job must not be assumed to correspond to two GSC
-- invocations; the actual SDK pipeline can use several processes per job.
theorem removed_two_observations (before after : List Work) (phase0 phase1 : Nat) :
    (total (before ++ [⟨1, phase0⟩, ⟨1, phase1⟩] ++ after)).jobs =
      (total (before ++ after)).jobs + 2 ∧
    (total (before ++ [⟨1, phase0⟩, ⟨1, phase1⟩] ++ after)).inputBytes =
      (total (before ++ after)).inputBytes + phase0 + phase1 := by
  simp [total_append, total, Work.plus]
  omega

-- Snapshot subtraction is valid for ordered observations. Nested inclusive
-- measurements are not inputs to this telescoping total.
theorem ordered_allocation_snapshots (start middle finish : Nat)
    (first : start ≤ middle) (second : middle ≤ finish) :
    (middle - start) + (finish - middle) = finish - start := by omega

theorem nested_inclusive_double_counts (outer inner : Nat) (positive : 0 < inner) :
    outer < outer + inner := by omega

-- Nat subtraction would silently turn this invalid interval into zero.
-- The observed counter must pass ordering before it can enter an allocation sum.
theorem decreasing_counter_rejected (start finish : Nat) (decreased : finish < start) :
    decide (start ≤ finish) = false := by simp; omega

-- CPU/work bounds do not establish wall bounds: queue/IO/descheduling time
-- is an independent nonnegative component and is not silently set to zero.
theorem work_reduction_does_not_bound_wait (work saved wait : Nat)
    (enough : saved ≤ work) (delay : saved < wait) :
    work < work - saved + wait := by omega

#print axioms total_append
#print axioms module_data_avoids_package_declaration
#print axioms inactive_dependency_no_work
#print axioms removed_two_observations
#print axioms ordered_allocation_snapshots
#print axioms nested_inclusive_double_counts
#print axioms decreasing_counter_rejected
#print axioms work_reduction_does_not_bound_wait
end Ascent.PreparationWork
