-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Measurement policy, not a proof of achieved speed. Native trace generation
and Scheme execution remain separate source-correspondence obligations. -/
namespace Ascent.RuntimeMeasurement

inductive Unit where
  | mailboxMessage | sessionState | relationRun | sourceUpdate | fullExport
  deriving DecidableEq, Repr

structure Trace where
  enqueued : Nat
  entered : Nat
  computed : Nat
  visible : Nat

def Ordered (t : Trace) : Prop :=
  t.enqueued ≤ t.entered ∧ t.entered ≤ t.computed ∧ t.computed ≤ t.visible
def latency (t : Trace) : Nat := t.visible - t.enqueued
def queueTime (t : Trace) : Nat := t.entered - t.enqueued
def executionTime (t : Trace) : Nat := t.computed - t.entered
def publicationTime (t : Trace) : Nat := t.visible - t.computed

/-- The benchmark reads Gambit's monotonic tick counter relative to one module
origin. The SDK supplies the nondecreasing ticks and positive frequency. -/
def tickTimestamp (origin tick frequency : Nat) : Nat :=
  (tick - origin) * 1000000000 / frequency

theorem tick_timestamp_monotone (origin first last frequency : Nat)
    (ordered : first ≤ last) :
    tickTimestamp origin first frequency ≤ tickTimestamp origin last frequency := by
  unfold tickTimestamp
  apply Nat.div_le_div_right
  exact Nat.mul_le_mul_right 1000000000 (Nat.sub_le_sub_right ordered origin)

theorem phase_decomposition (t : Trace) (h : Ordered t) :
    latency t = queueTime t + executionTime t + publicationTime t := by
  unfold Ordered at h
  unfold latency queueTime executionTime publicationTime
  omega

structure Evidence where
  unit : Unit
  planned : Nat
  samples : List Nat
  checked : Bool
  ownerAffine : Bool
  drained : Bool

-- Distribution policy: at least 95 percent of ALL completions meet the bound.
-- Native Suites retain their existing quantile implementations and thresholds.
def Policy (minimum : Nat) (unit : Unit) (p95Bound : Nat) (e : Evidence) : Prop :=
  e.unit = unit ∧ e.planned = e.samples.length ∧ minimum ≤ e.planned ∧
  e.checked = true ∧ e.ownerAffine = true ∧ e.drained = true ∧
  19 * e.samples.length ≤ 20 * (e.samples.filter (fun n => decide (n < p95Bound))).length

theorem bound_itself_is_not_fast (bound : Nat) :
    ([bound].filter (fun n => decide (n < bound))).length = 0 := by simp

def Admitted (unit : Unit) (p95Bound : Nat) (e : Evidence) : Prop :=
  Policy 1000 unit p95Bound e

structure Experiment where
  preparationNs : Nat
  coldLoadNs : Nat
  runtime : Evidence

def RuntimeAdmitted (unit : Unit) (bound : Nat) (e : Experiment) : Prop :=
  Admitted unit bound e.runtime

theorem preparation_is_not_query_latency (unit : Unit) (bound preparation cold : Nat)
    (e : Experiment) :
    RuntimeAdmitted unit bound { e with preparationNs := preparation, coldLoadNs := cold } ↔
      RuntimeAdmitted unit bound e := Iff.rfl

theorem incomplete_rejected (unit : Unit) (bound : Nat) (e : Evidence)
    (missing : e.planned ≠ e.samples.length) : ¬ Admitted unit bound e := by
  intro accepted
  exact missing accepted.2.1

theorem different_units_rejected (expected : Unit) (bound : Nat) (e : Evidence)
    (different : e.unit ≠ expected) : ¬ Admitted expected bound e := by
  intro accepted
  exact different accepted.1

theorem too_few_samples_rejected (unit : Unit) (bound : Nat) (e : Evidence)
    (few : e.planned < 1000) : ¬ Admitted unit bound e := by
  intro accepted
  have enough := accepted.2.2.1
  omega

end Ascent.RuntimeMeasurement

#print axioms Ascent.RuntimeMeasurement.phase_decomposition
#print axioms Ascent.RuntimeMeasurement.tick_timestamp_monotone
#print axioms Ascent.RuntimeMeasurement.preparation_is_not_query_latency
#print axioms Ascent.RuntimeMeasurement.incomplete_rejected
#print axioms Ascent.RuntimeMeasurement.different_units_rejected
#print axioms Ascent.RuntimeMeasurement.too_few_samples_rejected
