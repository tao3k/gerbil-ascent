-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import NativeBitmapWorklist
import FunctionalDependency

/-!
One source-update contract from the admitted old row log to completed-result
reuse. The old effective rows are its base followed by reverse-chronological
appends in chronological order, matching `program/update-selection.ss`.
Changed relations seed the compiled read graph. The selected bitmap then
frames completed values for a checklist-local evaluator.

This is a typed model. It does not prove that Gerbil `equal?`, lowered plan
IDs, mutable vectors, or the native evaluator refine these definitions.
-/

namespace Ascent.SourceUpdateFrame

open RuleGraphClosure
open NativeBitmapWorklist
open DependencyInvalidation

variable {Row : Type}

structure Cut (count : Nat) (Row : Type) where
  base : Fin count → List Row
  newestFirstAppends : Fin count → List Row
  candidate : Fin count → List Row

def Cut.before (cut : Cut count Row) (key : Fin count) : List Row :=
  cut.base key ++ (cut.newestFirstAppends key).reverse

def Cut.changed (cut : Cut count Row) (key : Fin count) : Prop :=
  cut.before key ≠ cut.candidate key

def Cut.seeds [DecidableEq Row] (cut : Cut count Row) : List (Fin count) :=
  (List.finRange count).filter (fun key => decide (cut.before key ≠ cut.candidate key))

theorem Cut.mem_seeds [DecidableEq Row] (cut : Cut count Row)
    (key : Fin count) : key ∈ cut.seeds ↔ cut.changed key := by
  simp [Cut.seeds, Cut.changed]

theorem Cut.seeds_nodup [DecidableEq Row] (cut : Cut count Row) :
    cut.seeds.Nodup := by
  exact (List.nodup_finRange count).filter _

def affected [DecidableEq Row] (plans : List (Rule (Fin count)))
    (cut : Cut count Row) (key : Fin count) : Prop :=
  marked (runFuel (ruleSuccessors plans) (count + 1)
    (initial cut.seeds)) key

private theorem reachable_seed_iff {Key : Type} (adj : Key → Key → Prop)
    (left right : Key → Prop) (same : ∀ key, left key ↔ right key)
    (key : Key) : Reachable adj left key ↔ Reachable adj right key := by
  constructor
  · intro reached
    induction reached with
    | seed member => exact Reachable.seed ((same _).mp member)
    | follow _ edge ih => exact Reachable.follow ih edge
  · intro reached
    induction reached with
    | seed member => exact Reachable.seed ((same _).mpr member)
    | follow _ edge ih => exact Reachable.follow ih edge

/-- A relation is selected exactly when it is changed or reachable through
one or more positive, negative, or aggregate reads. -/
theorem affected_iff [DecidableEq Row]
    (plans : List (Rule (Fin count))) (cut : Cut count Row)
    (key : Fin count) :
    affected plans cut key ↔ Reachable (ReadsInto plans) cut.changed key := by
  unfold affected
  have closure := runFuel_compiled_exact count plans cut.seeds
    cut.seeds_nodup key
  exact closure.trans (reachable_seed_iff (ReadsInto plans)
    (fun key => key ∈ cut.seeds) cut.changed
    (fun key => cut.mem_seeds key) key)

/-- Source rows outside the computed affected set are identical across cuts. -/
theorem source_frame [DecidableEq Row]
    (plans : List (Rule (Fin count))) (cut : Cut count Row) :
    AgreeOutside (affected plans cut) cut.before cut.candidate := by
  intro key untouched
  by_cases same : cut.before key = cut.candidate key
  · exact same
  · exact False.elim (untouched ((affected_iff plans cut key).mpr
      (Reachable.seed same)))

/-- This is the complete modeled chain: source-log comparison, exact
read-graph closure, checklist-local evaluation, and differently timed
completed fixed points. A rule head may also read its own old value during
deduplication or lattice join. That self-read needs no graph edge: successor
closure is trivially closed under identity. `readsMatch` is the explicit
compiler/evaluator correspondence premise, not an inferred native fact. -/
theorem completed_reuse [DecidableEq Row]
    (plans : List (Rule (Fin count))) (cut : Cut count Row)
    (program : FunctionalDependency.Program (Fin count) (fun _ => List Row))
    (readsMatch : ∀ source target,
      program.edge source target →
        source = target ∨ ReadsInto plans source target)
    (oldRounds newRounds : Nat)
    (oldStable : program.step
      (iterate program.step oldRounds cut.before) =
      iterate program.step oldRounds cut.before)
    (newStable : program.step
      (iterate program.step newRounds cut.candidate) =
      iterate program.step newRounds cut.candidate) :
    AgreeOutside (affected plans cut)
      (iterate program.step oldRounds cut.before)
      (iterate program.step newRounds cut.candidate) := by
  have closed : Closed program.edge (affected plans cut) := by
    intro source target read selected
    rcases readsMatch source target read with self | bodyRead
    · simpa [self] using selected
    · exact runFuel_compiled_closed count plans cut.seeds
        cut.seeds_nodup source target bodyRead selected
  exact program.completed_frame (affected plans cut) closed
    (source_frame plans cut) oldRounds newRounds oldStable newStable

/-! Source-count preflight for detached actor cuts. Unique replacement slots
and correct cached row counts are native correspondence premises. `removed`
is zero for append and the sum of old replaced slot counts for replacement.
These arithmetic laws do not prove allocation or native heap ownership. -/
def sourceCount (before removed added : Nat) : Nat := before - removed + added

def prepareSourceCount (before removed added limit : Nat) : Option Nat :=
  let count := sourceCount before removed added
  if count ≤ limit then some count else none

theorem source_count_balance (before removed added : Nat)
    (validRemoval : removed ≤ before) :
    sourceCount before removed added + removed = before + added := by
  unfold sourceCount
  omega

theorem refused_source_budget (before removed added limit : Nat)
    (over : limit < sourceCount before removed added) :
    prepareSourceCount before removed added limit = none := by
  simp [prepareSourceCount, Nat.not_le_of_gt over]

theorem admitted_source_budget (before removed added limit count : Nat)
    (accepted : prepareSourceCount before removed added limit = some count) :
    count ≤ limit := by
  dsimp only [prepareSourceCount] at accepted
  split at accepted <;> simp_all

end Ascent.SourceUpdateFrame
