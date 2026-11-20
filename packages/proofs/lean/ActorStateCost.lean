-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
import ActorEnvelope
import ActorReply

/-! Source constructor calls in successful Session state requests. These are
not malloc counts, byte counts, timings, or a verification of the STD scheduler. -/
namespace Ascent.ActorStateCost

structure Constructors where
  completions : Nat
  mutexes : Nat
  conditionVariables : Nat
  envelopePairs : Nat
  statePairs : Nat
  outcomeVectors : Nat
  clockBuffers : Nat
  deriving DecidableEq, Repr

def window (requests : Nat) (timed : Bool) : Constructors :=
  ⟨requests, requests, requests, requests * Ascent.ActorEnvelope.fields.length,
    requests * 2, requests, if timed then requests * 2 else 0⟩

theorem fresh_endpoints (requests : Nat) (timed : Bool) :
    (window requests timed).completions = requests := rfl

theorem five_envelope_pairs (requests : Nat) (timed : Bool) :
    (window requests timed).envelopePairs = requests * 5 := rfl

theorem removing_clock_probes_preserves_protocol (requests : Nat) :
    { window requests true with clockBuffers := 0 } = window requests false := rfl

theorem timed_million_clock_buffers : (window 1000000 true).clockBuffers = 2000000 := by
  decide

structure StateWindow where
  retainedFacts : Nat
  calls : Constructors

def stateWindow (requests retainedFacts : Nat) (timed : Bool) : StateWindow :=
  ⟨retainedFacts, window requests timed⟩

theorem state_constructor_work_does_not_depend_on_relation_size
    (requests oldFacts newFacts : Nat) (timed : Bool) :
    (stateWindow requests oldFacts timed).calls =
      (stateWindow requests newFacts timed).calls := rfl

/-- An explicitly conditional scan-cost expression. Retained roots are an
input from source/liveness evidence, not inferred from a negative counter. -/
def retainedScanWork (collections retainedRoots : Nat) := collections * retainedRoots

theorem fewer_roots_do_not_increase_scan_work (collections oldRoots newRoots : Nat)
    (fewer : newRoots ≤ oldRoots) :
    retainedScanWork collections newRoots ≤ retainedScanWork collections oldRoots :=
  Nat.mul_le_mul_left collections fewer

structure Measured where
  wall : Nat
  cpu : Nat
  gcWall : Nat
  gcCpu : Nat

def Valid (m : Measured) : Prop := m.cpu ≤ m.wall ∧ m.gcCpu ≤ m.cpu ∧ m.gcWall ≤ m.wall

/-- CPU and GC wall are overlapping observations; this is not a partition. -/
theorem cpu_and_gc_cannot_be_added_as_wall_partition :
    ∃ m : Measured, Valid m ∧ m.wall < m.cpu + m.gcWall := by
  exact ⟨⟨10, 9, 8, 7⟩, by simp [Valid], by decide⟩

def wallOnlyDifference (m : Measured) := m.wall - m.cpu

theorem wall_cpu_difference_is_only_an_unattributed_difference (m : Measured)
    (valid : Valid m) : m.wall = m.cpu + wallOnlyDifference m := by
  unfold Valid at valid
  unfold wallOnlyDifference
  omega

end Ascent.ActorStateCost

#print axioms Ascent.ActorStateCost.five_envelope_pairs
#print axioms Ascent.ActorStateCost.removing_clock_probes_preserves_protocol
#print axioms Ascent.ActorStateCost.fewer_roots_do_not_increase_scan_work
#print axioms Ascent.ActorStateCost.cpu_and_gc_cannot_be_added_as_wall_partition
