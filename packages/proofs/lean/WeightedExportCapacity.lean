-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Init.Omega
import ProviderRectangles
import RuleGraphClosure

/-! Source-directed units and conditional allocation capacity.
The frozen mem.c words_movable_objs macro doubles the heap/stack cursor
span for semispace accounting. No equation here identifies RSS or exact
cumulative payload bytes with the runtime counter. Integer arithmetic
assumes the actual floating-point receipt counters are exactly represented. -/
namespace Ascent.WeightedCapacity

def movableBudget (heap stack : Int) : Int := 2 * (heap + stack)
def counter (adjusted heap stack processorStill vmStill : Int) : Int :=
  adjusted + movableBudget heap stack + processorStill + vmStill

/-- The collection watermark (statistics field 16) is the rebased
processor charge, while the current counter (field 7) also includes
VM-wide still occupancy. Adding the just-collected still occupancy
(field 19) restores a common accounting domain. Equating the two
observations at the collection boundary requires stable still occupancy. -/
theorem collector_watermark_still_correction
    (adjusted heap stack processorStill stillBefore stillAfter : Int) :
    counter adjusted heap stack processorStill 0 + stillAfter -
      counter adjusted heap stack processorStill stillBefore =
      stillAfter - stillBefore := by
  unfold counter
  omega

theorem mixed_watermark_can_report_negative_offset
    (start watermark still : Int)
    (positive : start ≤ watermark + still)
    (below : watermark < start) :
    watermark - start < 0 ∧ 0 ≤ watermark + still - start := by
  omega

/-- The selected-activation byte gate keeps every observation. A negative
observation invalidates the byte lane before the existing thresholds. -/
def validAllocationSamples (samples : List Int) : Bool :=
  samples.all fun bytes => decide (0 ≤ bytes)

theorem negative_sample_invalidates_allocation (samples : List Int) (bytes : Int)
    (observed : bytes ∈ samples) (negative : bytes < 0) :
    validAllocationSamples samples = false := by
  cases h : validAllocationSamples samples with
  | false => rfl
  | true =>
    have nonnegative : 0 ≤ bytes := by
      simpa using (List.all_eq_true.mp h bytes observed)
    omega

theorem valid_samples_preserve_threshold (reference candidate : List Int)
    (threshold : Bool) (r : validAllocationSamples reference = true)
    (c : validAllocationSamples candidate = true) :
    (validAllocationSamples reference && validAllocationSamples candidate && threshold) = threshold := by
  simp [r, c]

/-- Frozen `mem.c` adds pre-collection processor occupancy to the adjusted
counter and subtracts post-collection occupancy. This rebase alone does not
explain a loss in the reported counter: its processor terms cancel exactly.
The VM-wide still term, subsequent stack retirement and cursor observations
must be distinguished from this collector-boundary equation. -/
theorem collector_rebase_preserves_processor_counter
    (adjusted heapBefore stackBefore stillBefore vmStillBefore
      heapAfter stackAfter stillAfter vmStillAfter : Int) :
    let rebased := adjusted + movableBudget heapBefore stackBefore + stillBefore -
      (movableBudget heapAfter stackAfter + stillAfter)
    counter rebased heapAfter stackAfter stillAfter vmStillAfter -
      counter adjusted heapBefore stackBefore stillBefore vmStillBefore =
      vmStillAfter - vmStillBefore := by
  unfold counter movableBudget
  omega

/-- Use the adjusted ledger for successful still allocations and
rebase only the movable charge during collection. The still object's
reservation and later release then never change its reported charge. -/
theorem successful_still_charge_survives_collection
    (adjusted heapBefore stackBefore heapAfter stackAfter stillBytes : Int) :
    let afterAllocation := adjusted + stillBytes
    let rebased := afterAllocation + movableBudget heapBefore stackBefore -
      movableBudget heapAfter stackAfter
    counter rebased heapAfter stackAfter 0 0 -
      counter adjusted heapBefore stackBefore 0 0 = stillBytes := by
  unfold counter
  omega

/-- Exact inputs read from the fenced Actor child's allocation function.
The prior movable sections join the heap term. The processor still term
includes the deferred statistics vector charge at the start endpoint. -/
theorem actor_admission_counter_replay :
    counter (-3683216) (8 * (13633 + 131029)) (8 * 2364) (8 * 10231) (8 * 10231) -
      counter 6830696 (8 * (2507 + 131059)) (8 * 60) (8 * (7402 + 26)) (8 * 7402) =
    -10254456 := by decide

/-- The Actor child's GC prelude added the observed negative prior-section
words to two positive current spans before rebasing. -/
theorem actor_negative_prior_sections_replay :
    movableBudget (427648 - 8 * 579581) 66336 + 8 * 7402 = -8226112 := by
  decide

/-- A separate instruction trace captured a stack-limit write after the
new section had been installed. The selected cursor belonged to that
new section, while the adjustment used the prior section start. -/
theorem actor_stack_limit_cross_section_write :
    (188411 : Int) + (-10387392 / 8) = -1110013 ∧
      ¬ (0 ≤ (-10387392 : Int) ∧ (-10387392 : Int) ≤ 524288) ∧
      0 ≤ (64 : Int) ∧ (64 : Int) ≤ 524288 := by
  decide

/-- Frozen arm64 `gerbil` startup. LLDB observed the subtract operands
and read the retired-section word ledger immediately after the store. -/
theorem frozen_gerbil_stack_limit_write :
    (14541502 : Int) + (-350257088 / 8) = -29240634 ∧
      ¬ (0 ≤ (-350257088 : Int) ∧ (-350257088 : Int) ≤ 524288) := by
  decide

/-- Native wide-mapping reference, sample 68. There was no collection
and the adjusted and still terms were stable. These are observed state
differences, not a replacement allocation measurement. -/
theorem wide_mapping_reference_counter_replay :
    counter 0 0 (8 * (-37189311 - 21868)) 0 0 - counter 0 0 0 0 0 =
      -595378864 := by decide

/-- Empty-bucket diagnostic, ordinal zero, reuse disabled. No collection
occurs and the rebased processor counter does not change. The observer
and the public counter use adjacent call boundaries. Their separate
observations are both negative, with an explicit endpoint residual. -/
theorem empty_bucket_counter_replay :
    let reconstructed := counter 0 0 (8 * (-28684182 + 36844)) 0 (8 * 15940)
    reconstructed = -458229888 ∧
      reconstructed + 396224 = -457833664 ∧
      0 < counter 0 0 (8 * 36844) 0 (8 * 15940) := by
  decide

/-- The native instruction trace brackets the first `empty-workflow` sample.
Each subtraction is followed by a read of the actual retired-word store. The
remaining ledger change is reconciled separately; the public counter and
component probes have adjacent endpoints. This is an observed counter defect,
with no inference about exact allocated payload or elapsed cost. -/
theorem empty_bucket_observed_stack_writes :
    let first : Int := -222248896 / 8
    let second : Int := -23101376 / 8
    let retired : Int := -19458731 - 8973530
    let reconstructed := counter 0 0 (8 * (retired + (36904 - 48))) 0 (8 * 15940)
    9776388 + first = -18004724 ∧
      -17144524 + second = -20032196 ∧
      first < 0 ∧ second < 0 ∧
      retired - first - second = 2236523 ∧
      reconstructed = -454198960 ∧
      reconstructed + 396400 = -453802560 := by
  decide

/-- `stack_msection_stop_using` charges the old section's remaining words;
resuming that same section removes the same charge. Word addresses are
integers here; the native C subtraction also requires pointers in one section. -/
theorem matched_stack_section_charge (previous start cursor : Int) :
    previous + (start - cursor) - (start - cursor) = previous := by
  omega

/-- Using a cursor from the new section when stopping the old one breaks
that balance. This states the accounting discrepancy only; native branch and
pointer ownership correspondence requires a trace of the actual write. -/
theorem foreign_stack_cursor_charge
    (previous oldStart oldCursor newCursor : Int) :
    previous + (oldStart - newCursor) - (oldStart - oldCursor) =
      previous + oldCursor - newCursor := by
  omega

/-- The native stop-using charge is bounded only when its cursor belongs to
the same old section. These address bounds are a source/trace obligation,
not a consequence of counter conservation or integer pointer arithmetic. -/
theorem same_section_charge_bound (start cursor capacity : Int)
    (insideLow : start - capacity ≤ cursor) (insideHigh : cursor ≤ start) :
    0 ≤ start - cursor ∧ start - cursor ≤ capacity := by
  omega

/-- At the old break, no frame moves. The new link keeps the original top
of the old stack, so retirement charges all the words between that top and
the old start. The new section's active charge is independent. -/
theorem retirement_preserves_unmoved_stack
    (retired oldStart oldTop newStart newTop : Int) :
    movableBudget 0 (retired + (oldStart - oldTop) + (newStart - newTop)) -
      movableBudget 0 (retired + (oldStart - oldTop)) =
        movableBudget 0 (newStart - newTop) := by
  unfold movableBudget
  omega

/-- When a stack retirement transfers frames, the old cursor advances
by exactly their word count. In the no-transfer branch it is unchanged.
The retirement charge and the newly occupied copies together count each
of the old frame words once, in addition to the new break-frame overhead. -/
theorem stack_transfer_conserves_charge
    (oldStart oldTop oldEnd moved overhead : Int)
    (copied : oldEnd - oldTop = moved) :
    (oldStart - oldEnd) + (moved + overhead) = oldStart - oldTop + overhead := by
  omega

/-- Saved cursor control at the same native workflow boundary. Both stores
use the saved old top, and the break-frame cursor would omit live words.
The endpoint residual is retained as in the unmodified trace. -/
theorem empty_bucket_old_cursor_control :
    let first : Int := 458848 / 8
    let second : Int := 458880 / 8
    let retired : Int := 11324777 - 8973531
    let reconstructed := counter 0 0 (8 * (retired + (36880 - 48))) 0 (8 * 15940)
    9776389 + first = 9833745 ∧
      10693951 + second = 10751311 ∧
      first - 458560 / 8 = 36 ∧ second - 458240 / 8 = 80 ∧
      retired - first - second = 2236530 ∧
      reconstructed = 38336768 ∧ reconstructed + 397376 = 38734144 := by
  decide

/-- The collection setup discards the retired-section ledger and recounts
the reachable state. With the same post-copy state, the old ledger error
persists in the rebased allocation counter and cancels out of post-copy
occupancy. The heap sizing input comes from the latter. This statement
holds the reachable state and section allocation path fixed. -/
theorem retired_charge_changes_rebase_not_postcopy_occupancy
    (adjusted beforeHeap beforeStack retired correction afterHeap afterStack
      afterRetired stillBefore stillAfter vmStill : Int) :
    let post := movableBudget afterHeap (afterStack + afterRetired) + stillAfter
    let corrected := adjusted + movableBudget beforeHeap (beforeStack + retired + correction) + stillBefore - post
    let original := adjusted + movableBudget beforeHeap (beforeStack + retired) + stillBefore - post
    counter corrected afterHeap (afterStack + afterRetired) stillAfter vmStill -
      counter original afterHeap (afterStack + afterRetired) stillAfter vmStill =
        movableBudget 0 correction := by
  unfold counter movableBudget
  omega

/-- The captured native write exceeds a whole frozen msection. Its observed
old-section cursor charge is within that bound. This rejects the observed
charge; it does not prove all executions of the C candidate are in bounds. -/
theorem captured_section_charge_violation :
    ¬ (0 ≤ (258056 : Int) ∧ (258056 : Int) ≤ 131072) ∧
    (0 ≤ (57364 : Int) ∧ (57364 : Int) ≤ 131072) ∧
    (258056 : Int) - 57364 = 200692 := by
  decide

/-- An increase in the heap cursor can be masked by a stack unwind even
without collection. This is an identifiability obstruction for a scalar
allocation-counter delta, independent of the observed still-object drop. -/
theorem same_counter_different_heap
    (adjusted heap stack processorStill vmStill allocated : Int) :
    counter adjusted (heap + allocated) (stack - allocated) processorStill vmStill =
    counter adjusted heap stack processorStill vmStill := by
  unfold counter movableBudget
  omega

/-- `___bytes_allocated` includes VM still occupancy as well as the processor
terms. A fall in those terms can make a positive heap allocation appear
negative. This implication does not identify the terms of an observed sample. -/
theorem processor_counter_can_drop_after_allocation
    (adjusted heap stack processorStill vmStill allocated unwound retired : Int)
    (allocation : 0 < allocated) (unwind : 0 ≤ unwound) (retirement : 0 ≤ retired)
    (loss : 2 * allocated < 2 * unwound + retired) :
    0 < allocated ∧ 0 ≤ unwound ∧ 0 ≤ retired ∧
      counter adjusted (heap + allocated) (stack - unwound)
        processorStill (vmStill - retired) <
      counter adjusted heap stack processorStill vmStill := by
  unfold counter movableBudget
  omega

def freshRowBytes (rows : Nat) : Nat := rows * 3 * 24
def payload (vertices : Nat) : Nat := 32 * freshRowBytes (vertices * vertices)
def budgetedPayload (vertices : Nat) : Nat := 2 * payload vertices

/-- Semispace charge for a single still-reachable complete result, before
accounting for interpreter roots, collector reserve or unrelated objects.
A held-result differential can test this unit without timing an export. -/
def heldExportCharge (vertices : Nat) : Nat :=
  2 * freshRowBytes (vertices * vertices)

theorem batch_charge_is_32_held_exports (vertices : Nat) :
    budgetedPayload vertices = 32 * heldExportCharge vertices := by
  simp [budgetedPayload, payload, heldExportCharge, Nat.mul_left_comm]

theorem held_export_charge_scales :
    heldExportCharge 384 = 21233664 ∧ heldExportCharge 512 = 37748736 := by
  decide

/-- Contiguous triples put each outer cell three pair widths from its
neighbor. Copying the entire outer cdr chain first puts the neighbors
one pair width apart. These offsets omit allocator boundaries. -/
theorem dense_outer_spine_strides (row pairBytes : Nat) (positive : 0 < pairBytes) :
    row * (3 * pairBytes) + pairBytes < (row + 1) * (3 * pairBytes) ∧
      (row + 1) * pairBytes = row * pairBytes + pairBytes := by
  constructor
  · rw [Nat.add_mul, Nat.one_mul]
    exact Nat.add_lt_add_left (by omega : pairBytes < 3 * pairBytes) _
  · rw [Nat.add_mul, Nat.one_mul]

/-- In the frozen 64-bit allocator a will has three body words and
one header word, charged in two semispaces. Independently watching
all public pair cells therefore allocates more than the cells.
The equality excludes finalizer closures and work during collection. -/
theorem observing_every_public_pair_cost (rows : Nat) :
    (3 * rows) * (2 * 4 * 8) = 2 * freshRowBytes rows + 48 * rows := by
  unfold freshRowBytes
  omega

/-- One 512 admission would require over 2 GiB of total accounting
charge with one fresh will per pair, even if the whole pair and will
payload were the only work. Collections may renew the available charge. -/
theorem watched_large_admission_charge :
    32 * (3 * (512 * 512)) * (2 * 4 * 8) = 1610612736 ∧
      2 * 1024 ^ 3 < budgetedPayload 512 + 1610612736 := by decide

/-- Snapshotting a stable roster into a second directory and then
reading the selected owner IDs gives the same ordered axis as reading
those IDs directly. The projection may contain weighted member spines
as well as counts. The native caller must establish that no mutation
interleaves and that every selected ID names a live root. -/
theorem frozen_axis_from_live_roster {Member : Type}
    (read snapshot : Nat → List Member × Nat) (selected : List Nat)
    (same : ∀ id ∈ selected, snapshot id = read id) :
    selected.map snapshot = selected.map read := by
  exact List.map_congr_left same

/-- For a sparse capture the replaced work consists of a record and hash
insertion per root, and a hash lookup per selected source or target.
Both paths still read membership and publish the same rectangles. -/
theorem sparse_roster_directory_work (roots selections shared : Nat) :
    (shared + 2 * roots + selections) - shared = 2 * roots + selections := by
  omega

/-- Nearest-rank P95 of an already sorted, nonempty timing sequence.
The single-export diagnostic uses rank 950 of 1000 observations. This
definition does not model clock accuracy, scheduling or collector pauses. -/
def sortedP95 (samples : List Nat) : Nat :=
  (samples[(95 * samples.length + 99) / 100 - 1]?).getD 0

theorem thousand_observation_rank : (95 * 1000 + 99) / 100 - 1 = 949 := by decide

theorem hundred_observation_rank : (95 * 100 + 99) / 100 - 1 = 94 := by decide

/-- If six of the one hundred observations reach the limit, their five
later entries cannot hide the first failing observation from rank 95.
Use an actual admission sample sequence for this criterion. -/
theorem sixth_exceedance_blocks_admission (sorted : List Nat) (limit : Nat)
    (count : sorted.length = 100) (exceeds : limit ≤ sorted[94]?.getD 0) :
    ¬ sortedP95 sorted < limit := by
  simpa [sortedP95, count] using Nat.not_lt.mpr exceeds

/-- For ascending samples, the values strictly below a limit form a prefix.
Unlike a test of the mean or median, this includes equality as a miss. -/
private theorem sorted_get_below_iff_count (samples : List Nat)
    (ordered : samples.Pairwise (· ≤ ·)) (limit index : Nat)
    (inside : index < samples.length) :
    samples[index] < limit ↔ index < samples.countP (fun wall => decide (wall < limit)) := by
  induction samples generalizing index with
  | nil => simp at inside
  | cons first rest ih =>
    obtain ⟨firstLe, restOrdered⟩ := List.pairwise_cons.mp ordered
    by_cases firstBelow : first < limit
    · cases index with
      | zero => simp [firstBelow]
      | succ index =>
        have indexInside : index < rest.length := by simpa using inside
        simp only [List.getElem_cons_succ, List.countP_cons, decide_eq_true firstBelow, ite_true]
        rw [ih restOrdered index indexInside]
        omega
    · have noneBelow : rest.countP (fun wall => decide (wall < limit)) = 0 := by
        apply List.countP_eq_zero.mpr
        intro wall member
        have h := firstLe wall member
        simp [show ¬ wall < limit by omega]
      have notBelow : ¬ (first :: rest)[index] < limit := by
        cases index with
        | zero => exact firstBelow
        | succ index =>
          have indexInside : index < rest.length := by simpa using inside
          have h := firstLe rest[index] (List.getElem_mem indexInside)
          simp only [List.getElem_cons_succ]
          omega
      simp [notBelow, firstBelow, noneBelow]

/-- ASP's nearest-rank gate for exactly 100 actual admission durations.
The sort is a permutation of the input; chronology is preserved separately
for joining a duration to its own phase receipt. -/
theorem strict_p95_iff_ninety_five_pass (samples : List Nat) (limit : Nat)
    (count : samples.length = 100) :
    sortedP95 (samples.mergeSort) < limit ↔
      95 ≤ samples.countP (fun wall => decide (wall < limit)) := by
  have sortedCount : samples.mergeSort.length = 100 := by simpa using count
  have inside : 94 < samples.mergeSort.length := by omega
  have ordered : samples.mergeSort.Pairwise (· ≤ ·) := by
    simpa using List.pairwise_mergeSort (le := fun a b : Nat => decide (a ≤ b))
      (by intro a b c; simp; omega) (by intro a b; simp; omega) samples
  have same := (List.mergeSort_perm samples (fun a b => decide (a ≤ b))).countP_eq
    (fun wall => decide (wall < limit))
  have selected := sorted_get_below_iff_count samples.mergeSort ordered limit 94 inside
  simp only [sortedP95, sortedCount, hundred_observation_rank, List.getElem?_eq_getElem inside,
    Option.getD_some]
  rw [selected, same]
  omega

/-- A candidate that preserves the given per-sample cost floors can pass
only if at least 95 of those floors are strictly under the limit. A floor
must come from the same observation or be established for the candidate.
This avoids subtracting one phase's P95 from another phase's P95. -/
theorem strict_p95_requires_phase_budget (samples : List (Nat × Nat)) (limit : Nat)
    (aligned : ∀ sample ∈ samples, sample.1 ≤ sample.2) (count : samples.length = 100)
    (pass : sortedP95 ((samples.map Prod.snd).mergeSort) < limit) :
    95 ≤ samples.countP (fun sample => decide (sample.1 < limit)) := by
  have budget := (strict_p95_iff_ninety_five_pass _ limit (by simpa using count)).mp pass
  rw [List.countP_map] at budget
  change 95 ≤ samples.countP (fun sample => decide (sample.2 < limit)) at budget
  have monotone : samples.countP (fun sample => decide (sample.2 < limit)) ≤
      samples.countP (fun sample => decide (sample.1 < limit)) := by
    clear pass budget count
    induction samples with
    | nil => simp
    | cons sample rest ih =>
      have below := aligned sample (by simp)
      have later := ih (fun item member => aligned item (by simp [member]))
      by_cases wallBelow : sample.2 < limit
      · have floorBelow : sample.1 < limit := by omega
        simpa [wallBelow, floorBelow] using later
      · by_cases floorBelow : sample.1 < limit <;>
          simp [wallBelow, floorBelow] <;> omega
  exact Nat.le_trans budget monotone

/-- Disjoint elapsed intervals from the same admission callback. Closure
and index construction happen before this callback. An unchanged phase is
usable as a lower bound only after accounting for observer endpoint skew. -/
theorem admission_phase_lower_bound
    (wall exportWall report gcWall skew : Nat)
    (gcWithin : gcWall ≤ exportWall) (align : exportWall + report ≤ wall + skew) :
    gcWall - skew ≤ wall ∧ (exportWall - gcWall) - skew ≤ wall := by omega

/-- If fewer than 95 measured floors fit, every candidate that leaves
those same floors in place fails the strict gate, even if it removes
all other costs. Changing the floors requires fresh measurements. -/
theorem preserved_phase_rejects_strict_p95 (samples : List (Nat × Nat)) (limit : Nat)
    (aligned : ∀ sample ∈ samples, sample.1 ≤ sample.2) (count : samples.length = 100)
    (tooFew : samples.countP (fun sample => decide (sample.1 < limit)) < 95) :
    ¬ sortedP95 ((samples.map Prod.snd).mergeSort) < limit := by
  intro pass
  have fits := strict_p95_requires_phase_budget samples limit aligned count pass
  omega

/-- If all samples keep a floor, the attainable saving on that phase
must bring at least 95 original floors below the enlarged limit. The
same saving allowance applies to each observation, in the same units. -/
theorem bounded_phase_saving_requires_95 (samples : List (Nat × Nat))
    (limit saving : Nat) (count : samples.length = 100)
    (aligned : ∀ sample ∈ samples, sample.1 ≤ sample.2 + saving)
    (pass : sortedP95 ((samples.map Prod.snd).mergeSort) < limit) :
    95 ≤ samples.countP (fun sample => decide (sample.1 < limit + saving)) := by
  have floors : ∀ pair ∈ samples.map (fun sample => (sample.1 - saving, sample.2)),
      pair.1 ≤ pair.2 := by
    intro pair member
    obtain ⟨sample, present, rfl⟩ := List.mem_map.mp member
    have bound := aligned sample present
    omega
  have projection : ((samples.map fun sample => (sample.1 - saving, sample.2)).map Prod.snd) =
      samples.map Prod.snd := by rw [List.map_map]; rfl
  have fit := strict_p95_requires_phase_budget _ limit floors
    (by simp [count]) (by rw [projection]; exact pass)
  rw [List.countP_map] at fit
  have positive : 0 < limit := Nat.zero_lt_of_lt pass
  have same : (fun sample : Nat × Nat => decide (sample.1 - saving < limit)) =
      (fun sample => decide (sample.1 < limit + saving)) := by
    funext sample
    by_cases below : sample.1 - saving < limit
    · have other : sample.1 < limit + saving := by omega
      simp [below, other]
    · have other : ¬ sample.1 < limit + saving := by omega
      simp [below, other]
  simpa only [Function.comp_def, same] using fit

/-- Lower bound for evaluating a proposed change against a matched batch.
Each saving is an independently justified upper bound, in the same wall
units. Saturating subtraction discards any unused saving in that phase;
the observer skew allowance is spent once on the sum of disjoint phases. -/
def candidateWallFloor (gc outside maxGcSaving maxOutsideSaving skew : Nat) : Nat :=
  ((gc - maxGcSaving) + (outside - maxOutsideSaving)) - skew

theorem candidate_wall_floor_sound
    (oldGc oldOutside newGc newOutside maxGcSaving maxOutsideSaving skew wall : Nat)
    (gcBound : oldGc ≤ newGc + maxGcSaving)
    (outsideBound : oldOutside ≤ newOutside + maxOutsideSaving)
    (disjoint : newGc + newOutside ≤ wall + skew) :
    candidateWallFloor oldGc oldOutside maxGcSaving maxOutsideSaving skew ≤ wall := by
  unfold candidateWallFloor
  omega

/-- An application proposal must leave room in at least 95 matched batches.
Here each first pair contains the old GC and outside-GC durations. Its
second element is the candidate's full wall duration. The correspondence
must be justified per batch by `candidate_wall_floor_sound`. -/
theorem candidate_needs_95_joint_budgets
    (samples : List ((Nat × Nat) × Nat)) (maxGcSaving maxOutsideSaving skew limit : Nat)
    (count : samples.length = 100)
    (matched : ∀ sample ∈ samples,
      candidateWallFloor sample.1.1 sample.1.2 maxGcSaving maxOutsideSaving skew ≤ sample.2)
    (pass : sortedP95 ((samples.map Prod.snd).mergeSort) < limit) :
    95 ≤ samples.countP (fun sample => decide
      (candidateWallFloor sample.1.1 sample.1.2 maxGcSaving maxOutsideSaving skew < limit)) := by
  let projected := samples.map fun sample =>
    (candidateWallFloor sample.1.1 sample.1.2 maxGcSaving maxOutsideSaving skew, sample.2)
  have aligned : ∀ sample ∈ projected, sample.1 ≤ sample.2 := by
    intro sample member
    obtain ⟨original, present, rfl⟩ := List.mem_map.mp member
    exact matched original present
  have projectedPass : sortedP95 ((projected.map Prod.snd).mergeSort) < limit := by
    simpa [projected, List.map_map, Function.comp_def] using pass
  have fits := strict_p95_requires_phase_budget projected limit aligned
    (by simpa [projected] using count) projectedPass
  simpa [projected, List.countP_map, Function.comp_def] using fits

/-- If the remaining non-collector floor fits by itself, this is the
least collector saving that makes the two floors fit the strict limit.
Otherwise even a collector with zero cost cannot fit. -/
def jointBudgetFits (limit gc outside maxGcSaving outsideSaving : Nat) : Bool :=
  let rest := outside - outsideSaving
  decide (rest < limit ∧ gc + rest + 1 - limit ≤ maxGcSaving)

theorem joint_budget_fits_iff
    (limit gc outside maxGcSaving outsideSaving : Nat) :
    jointBudgetFits limit gc outside maxGcSaving outsideSaving = true ↔
      candidateWallFloor gc outside maxGcSaving outsideSaving 0 < limit := by
  simp only [jointBudgetFits, decide_eq_true_eq, candidateWallFloor, Nat.sub_zero]
  omega

/-- Bounds for one prepared `ui-consume` admission in elapsed nanoseconds.
Capture, materialization, and consumer traversal are exclusive of collector
time. The remainder includes validation, harness work, and endpoint error.
State construction and index preparation occur before this callback. -/
structure PreparedAdmissionBounds where
  capture : Nat
  materialization : Nat
  consumer : Nat
  collection : Nat
  remainder : Nat

def PreparedAdmissionBounds.total (bounds : PreparedAdmissionBounds) : Nat :=
  bounds.capture + bounds.materialization + bounds.consumer + bounds.collection + bounds.remainder

/-- An endpoint contains wall time and cumulative collector wall time,
both in the same units. Keep signed differences so a skew-induced
negative interval remains observable. -/
def outsideCollector (start finish : Int × Int) : Int :=
  finish.1 - start.1 - (finish.2 - start.2)

def observedOutside (start : Int × Int) (interior : List (Int × Int))
    (finish : Int × Int) : Int :=
  match interior with
  | [] => outsideCollector start finish
  | point :: rest => outsideCollector start point + observedOutside point rest finish

/-- Subtract GC in each adjacent interval across all exports and the
gaps between them. Add its enclosing difference once for the full
callback. The same native collector counter supplies every endpoint. -/
theorem prepared_observed_partition (start finish : Int × Int)
    (interior : List (Int × Int)) :
    observedOutside start interior finish + (finish.2 - start.2) = finish.1 - start.1 := by
  induction interior generalizing start with
  | nil => simp [observedOutside, outsideCollector]
  | cons point rest ih =>
    have remaining := ih point
    simp only [observedOutside, outsideCollector]
    omega

/-- The sufficient counterpart to `candidate_needs_95_joint_budgets`.
An elapsed upper bound must cover its own complete admission. Supply one
bound per chronological sample, including the remainder; an independently
sorted phase or a CPU duration cannot establish this premise. -/
theorem prepared_admissions_pass_with_95_aligned_upper_bounds
    (samples : List (PreparedAdmissionBounds × Nat)) (limit : Nat)
    (count : samples.length = 100)
    (aligned : ∀ sample ∈ samples, sample.2 ≤ sample.1.total)
    (enough : 95 ≤ samples.countP (fun sample => decide (sample.1.total < limit))) :
    sortedP95 ((samples.map Prod.snd).mergeSort) < limit := by
  apply (strict_p95_iff_ninety_five_pass _ limit (by simp [count])).mpr
  rw [List.countP_map]
  refine Nat.le_trans enough (List.countP_mono_left ?_)
  intro sample member below
  exact decide_eq_true (Nat.lt_of_le_of_lt (aligned sample member) (of_decide_eq_true below))

/-- Both phase marginals can pass while the corresponding complete
admissions fail. The two phases miss on disjoint sets of three samples. -/
theorem passing_phase_percentiles_do_not_imply_passing_total :
    let samples := List.replicate 3 (100, 1) ++ List.replicate 3 (1, 100) ++
      List.replicate 94 (1, 1)
    sortedP95 ((samples.map Prod.fst).mergeSort) < 100 ∧
    sortedP95 ((samples.map Prod.snd).mergeSort) < 100 ∧
    ¬ sortedP95 ((samples.map fun (first, second) => first + second).mergeSort) < 100 := by
  dsimp only
  rw [strict_p95_iff_ninety_five_pass, strict_p95_iff_ninety_five_pass,
    strict_p95_iff_ninety_five_pass] <;> simp

/-- A per-sample budget for a collector intervention. If the candidate's
other elapsed work is bounded by the supplied allowance, a strict budget
on the sum of its pauses is sufficient for this sample. -/
theorem collection_budget_suffices
    (pauses : List Nat) (other allowance wall limit : Nat)
    (accounted : wall ≤ other + pauses.sum) (otherBound : other ≤ allowance)
    (fits : pauses.sum < limit - allowance) : wall < limit := by omega

/-- Even a hypothetical reduction to zero construction time cannot pass an
individual 100 ms budget when its measured GC CPU is retained. The strict
gate uses separate wall observations, so this applies to the modeled CPU
leg only. The example uses the default-policy 384-vertex GC median. -/
theorem default_heavy_gc_cpu_alone_exceeds_100ms (remaining : Nat) :
    100000 ≤ 104624 + remaining := by omega

/-- A collection count is useful only with a bound on the cost of each
collection. This is a per-batch statement: a median pause cannot establish
the premise, and a GC count from the CPU arm is not an admission sample. -/
theorem collection_cost_floor (pauses : List Nat) (floor : Nat)
    (each : ∀ pause ∈ pauses, floor ≤ pause) :
    pauses.length * floor ≤ pauses.sum := by
  induction pauses with
  | nil => simp
  | cons pause rest ih =>
    have first := each pause (by simp)
    have later := ih (fun p hp => each p (by simp [hp]))
    simp only [List.length_cons, List.sum_cons, Nat.add_mul, Nat.one_mul]
    omega

/-- For one batch, retaining its non-collector wall floor and a lower
bound for each of at least `count` pauses implies this candidate floor.
The caller must justify both measurements for the proposed schedule. -/
def pauseScheduleFloor (outside pause count : Nat) : Nat := outside + count * pause

theorem pause_schedule_floor_sound
    (pauses : List Nat) (outside pause count wall : Nat)
    (atLeast : count ≤ pauses.length)
    (pauseBound : ∀ duration ∈ pauses, pause ≤ duration)
    (accounted : outside + pauses.sum ≤ wall) :
    pauseScheduleFloor outside pause count ≤ wall := by
  have measured := collection_cost_floor pauses pause pauseBound
  have minimum := Nat.mul_le_mul_right pause atLeast
  unfold pauseScheduleFloor
  omega

/-- A mixed collection schedule charges each pause according to the
kind of tracing it performs. `whole` counts full-heap collections and
`young` counts collections confined to a young allocation region. -/
def mixedPauseFloor (outside wholePrice youngPrice whole young : Nat) : Nat :=
  outside + whole * wholePrice + young * youngPrice

theorem mixed_pause_floor_sound (whole young : List Nat)
    (outside wholePrice youngPrice wall : Nat)
    (wholeFloor : ∀ duration ∈ whole, wholePrice ≤ duration)
    (youngFloor : ∀ duration ∈ young, youngPrice ≤ duration)
    (accounted : outside + whole.sum + young.sum ≤ wall) :
    mixedPauseFloor outside wholePrice youngPrice whole.length young.length ≤ wall := by
  have fullCharge := collection_cost_floor whole wholePrice wholeFloor
  have youngCharge := collection_cost_floor young youngPrice youngFloor
  unfold mixedPauseFloor
  omega

/-- A pause-price limit includes every full collection in that same
sample. The remaining budget cannot also be credited to promotion or
to maintaining remembered references. -/
theorem mixed_schedule_required_budget (outside wholePrice youngPrice whole young extra wall limit : Nat)
    (accounted : mixedPauseFloor outside wholePrice youngPrice whole young + extra ≤ wall)
    (passes : wall < limit) :
    young * youngPrice + extra < limit - (outside + whole * wholePrice) := by
  unfold mixedPauseFloor at accounted
  omega

/-- With the same count of collections, the remaining wall budget gives
an integer ceiling on their average time. This does not constrain any
single pause to that ceiling. -/
theorem average_pause_budget (limit outside count elapsed : Nat)
    (fits : outside + elapsed < limit) :
    elapsed / count ≤ (limit - outside - 1) / count := by
  have available : elapsed ≤ limit - outside - 1 := by omega
  exact Nat.div_le_div_right available

/-- The greatest number of full pauses of the given price that fit
alongside the retained outside-GC work. The subtraction reserves one
tick for the strict inequality. -/
def admissiblePauseCount (limit outside pause : Nat) : Nat :=
  (limit - outside - 1) / pause

/-- Necessary renewal headroom when the outside-work floor and pause
price hold on the same admission. The first interval counts once;
every collection can contribute at most one further interval. -/
theorem admission_requires_interval_headroom
    (pauses : List Nat) (payload capacity outside pause wall limit : Nat)
    (coverage : payload ≤ (pauses.length + 1) * capacity)
    (pausePositive : 0 < pause)
    (pauseFloor : ∀ duration ∈ pauses, pause ≤ duration)
    (accounted : outside + pauses.sum ≤ wall) (passes : wall < limit) :
    payload ≤ (admissiblePauseCount limit outside pause + 1) * capacity := by
  have charged := collection_cost_floor pauses pause pauseFloor
  have sumBound : pauses.length * pause ≤ limit - outside - 1 := by omega
  have count : pauses.length ≤ admissiblePauseCount limit outside pause := by
    unfold admissiblePauseCount
    exact (Nat.le_div_iff_mul_le pausePositive).mpr sumBound
  exact Nat.le_trans coverage (Nat.mul_le_mul_right capacity (Nat.add_le_add_right count 1))

/-- Optimistic uniform-capacity sensitivity for a single admission.
Round its fixed payload up to the number of required intervals. A zero
capacity or pause price is outside this positive-price model. -/
def capacityFloorFits (payload limit outside pause capacity : Nat) : Bool :=
  decide (outside < limit ∧ 0 < pause ∧
    payload ≤ (admissiblePauseCount limit outside pause + 1) * capacity)

theorem passing_admission_satisfies_capacity_floor
    (pauses : List Nat) (payload capacity outside pause wall limit : Nat)
    (coverage : payload ≤ (pauses.length + 1) * capacity)
    (pausePositive : 0 < pause)
    (pauseFloor : ∀ duration ∈ pauses, pause ≤ duration)
    (accounted : outside + pauses.sum ≤ wall) (passes : wall < limit) :
    capacityFloorFits payload limit outside pause capacity = true := by
  have outsideFits : outside < limit := by omega
  have fits := admission_requires_interval_headroom pauses payload capacity outside pause wall limit
    coverage pausePositive pauseFloor accounted passes
  exact decide_eq_true ⟨outsideFits, pausePositive, fits⟩

/-- When a candidate changes capacity only at entry, charge the first
interval separately from the unchanged per-collection renewal ceiling.
This is the least initial capacity consistent with the measured floors,
assuming every allowed renewal reaches its ceiling. -/
def requiredInitialCapacity (payload limit outside pause renewal : Nat) : Nat :=
  payload - admissiblePauseCount limit outside pause * renewal

theorem passing_admission_requires_initial_capacity
    (pauses : List Nat) (payload limit outside pause initial renewal wall : Nat)
    (coverage : payload ≤ initial + pauses.length * renewal)
    (pausePositive : 0 < pause)
    (pauseFloor : ∀ duration ∈ pauses, pause ≤ duration)
    (accounted : outside + pauses.sum ≤ wall) (passes : wall < limit) :
    requiredInitialCapacity payload limit outside pause renewal ≤ initial := by
  have charged := collection_cost_floor pauses pause pauseFloor
  have sumBound : pauses.length * pause ≤ limit - outside - 1 := by omega
  have count : pauses.length ≤ admissiblePauseCount limit outside pause := by
    unfold admissiblePauseCount
    exact (Nat.le_div_iff_mul_le pausePositive).mpr sumBound
  have room := Nat.mul_le_mul_right renewal count
  unfold requiredInitialCapacity
  omega

theorem initial_capacity_coverage_iff
    (payload limit outside pause renewal initial : Nat) :
    requiredInitialCapacity payload limit outside pause renewal ≤ initial ↔
      payload ≤ initial + admissiblePauseCount limit outside pause * renewal := by
  unfold requiredInitialCapacity
  omega

/-- The native strict benchmark runs the two CPU arms serially.
Each original trial keeps its measured reference charge, a candidate
charge, and any remaining disjoint process time. The latter includes
startup, collect-before calls, validation, admission and allocation. -/
theorem watchdog_remaining_after_cpu_pairs
    (reference candidate other elapsed deadline : Nat)
    (serial : reference + candidate + other ≤ elapsed)
    (finished : elapsed < deadline) :
    candidate + other < deadline - reference := by
  omega

/-- With a candidate-only change, a frozen reference's collected
prefix must fit before any other work. A remaining-work lower bound
can reject the proposed command even if the candidate arm is free. -/
theorem watchdog_cannot_be_recovered_by_candidate
    (reference other elapsed deadline : Nat)
    (charged : reference + other ≤ elapsed)
    (overBudget : deadline ≤ reference + other) :
    ¬ elapsed < deadline := by
  omega

/-- Inside one arm, the two measured GC windows are disjoint. The
precondition is outside the arm's CPU clock but still inside the
outer watchdog. Use one time unit for wall, GC, and the remainder. -/
theorem watchdog_arm_partition
    (start afterCollect afterBody preGc bodyGc : Nat)
    (ordered : start ≤ afterCollect ∧ afterCollect ≤ afterBody)
    (preWithin : preGc ≤ afterCollect - start)
    (bodyWithin : bodyGc ≤ afterBody - afterCollect) :
    preGc + bodyGc + ((afterCollect - start) - preGc) +
      ((afterBody - afterCollect) - bodyGc) = afterBody - start := by
  omega

/-- The strict gate can miss five admissions. If only `eligible` baseline
floors can fit with the old pause schedule, at least `95 - eligible`
additional samples must change their floors to make a pass possible. -/
theorem passing_schedule_needs_changed_samples (eligible changed : Nat)
    (fits : 95 ≤ eligible + changed) : 95 - eligible ≤ changed := by
  omega

/-- With at most two renewals, a uniformly bounded capacity must cover
the fixed 512 payload in three intervals. The bound includes the initial
interval and excludes non-pair allocations. -/
theorem large_512_two_renewals_require_capacity (capacity : Nat)
    (coverage : budgetedPayload 512 ≤ 3 * capacity) : 402653184 ≤ capacity := by
  have payload : budgetedPayload 512 = 1207959552 := by decide
  rw [payload] at coverage
  omega

/-- Necessary budget for a batch with nonoverlapping measured wall phases.
Use this with wall durations, or supply an independent CPU-to-wall bound.
Neither the adaptive heap rule nor a CPU receipt proves that bound. -/
theorem passing_batch_requires_collection_budget
    (pauses : List Nat) (floor other wall threshold : Nat)
    (each : ∀ pause ∈ pauses, floor ≤ pause)
    (accounted : pauses.sum + other ≤ wall)
    (pass : wall < threshold) :
    pauses.length * floor + other < threshold := by
  have gc := collection_cost_floor pauses floor each
  omega

/-- If at most `collections` pauses fit the elapsed budget, the initial
interval and those renewals must together cover the full pair payload.
The maximum renewal charge must include the active-section remainder;
the nominal new-section charge alone is insufficient as an upper bound. -/
theorem passing_batch_requires_renewal_capacity
    (pauses : List Nat) (payload initial renewal other floor limit collections : Nat)
    (coverage : payload ≤ initial + pauses.length * renewal)
    (each : ∀ pause ∈ pauses, floor ≤ pause)
    (tooMany : limit ≤ (collections + 1) * floor + other)
    (accounted : pauses.sum + other ≤ limit - 1) (positive : 0 < limit) :
    payload ≤ initial + collections * renewal := by
  have gc := collection_cost_floor pauses floor each
  have count : pauses.length ≤ collections := by
    by_cases fits : pauses.length ≤ collections
    · exact fits
    · have minimum := Nat.mul_le_mul_right floor (show collections + 1 ≤ pauses.length by omega)
      omega
  have capacity := Nat.mul_le_mul_right renewal count
  omega

/-- Concrete sensitivity for the 512 admission. With a 34 ms non-GC
floor and an 18 ms floor on each pause, a 100 ms batch fits at most
three collections. This bounds the required capacity only when the
observed floors apply to the candidate being evaluated. -/
theorem large_512_three_renewal_capacity
    (pauses : List Nat) (initial renewal wall : Nat)
    (coverage : budgetedPayload 512 ≤ initial + pauses.length * renewal)
    (pauseFloor : ∀ pause ∈ pauses, 18000000 ≤ pause)
    (outsideFloor : pauses.sum + 34000000 ≤ wall)
    (fits : wall < 100000000) :
    budgetedPayload 512 ≤ initial + 3 * renewal := by
  exact passing_batch_requires_renewal_capacity pauses _ initial renewal
    34000000 18000000 100000000 3 coverage pauseFloor (by decide)
    (by omega) (by decide)

/-- A candidate retaining the measured scale of the default renewal
intervals and pause costs cannot pass at 512 even with free construction
and traversal. The bound on the initial interval is separate from the
bound on renewals. Both must be established for the candidate. -/
theorem large_512_default_scale_excludes_strict_gate
    (pauses : List Nat) (initial renewal wall : Nat)
    (coverage : budgetedPayload 512 ≤ initial + pauses.length * renewal)
    (initialBound : initial ≤ 152000000) (renewalBound : renewal ≤ 152000000)
    (pauseFloor : ∀ pause ∈ pauses, 16000000 ≤ pause)
    (accounted : pauses.sum ≤ wall) :
    112000000 ≤ wall := by
  have payload : budgetedPayload 512 = 1207959552 := by decide
  rw [payload] at coverage
  have capacity := Nat.mul_le_mul_left pauses.length renewalBound
  have count : 7 ≤ pauses.length := by omega
  have floor := Nat.mul_le_mul_right 16000000 count
  have pausesLower := collection_cost_floor pauses 16000000 pauseFloor
  omega

/-- The strict weighted trajectory receives an already closed provider
and requests an unindexed view. Provider construction and route building
belong in separate measurements. GC pauses are accounted independently
of the remaining capture and materialization durations. -/
def exportWork (closure routing capture materialization collection : Nat) : Nat :=
  closure + routing + capture + materialization + collection

theorem prepared_unindexed_export_work (capture materialization collection : Nat) :
    exportWork 0 0 capture materialization collection =
      capture + materialization + collection := by
  simp [exportWork]

theorem prepared_unindexed_capture_saving_bound
    (capture materialization collection : Nat) :
    exportWork 0 0 capture materialization collection -
      exportWork 0 0 0 materialization collection = capture := by
  simp only [prepared_unindexed_export_work, Nat.zero_add]
  omega

/-- A paired diagnostic can bound the non-collector difference only by
subtracting the collector wall delta from each observation. The bound
requires disjoint wall phases measured over the same respective intervals. -/
theorem paired_outside_wall_difference
    (reference candidate referenceGC candidateGC : Nat)
    (referenceBound : referenceGC ≤ reference)
    (candidateBound : candidateGC ≤ candidate) :
    ((reference - referenceGC : Nat) : Int) - ((candidate - candidateGC : Nat) : Int) =
      ((reference : Int) - candidate) - ((referenceGC : Int) - candidateGC) := by
  omega

/-- Subtract the collection counter within each CPU sample before
comparing arms. A faster total CPU result can coexist with slower GC;
this bound is on the remainder and uses the same original pair. -/
theorem paired_cpu_saving_from_outside
    (reference candidate referenceGC candidateGC saving regression : Nat)
    (referenceBound : referenceGC ≤ reference)
    (candidateBound : candidateGC ≤ candidate)
    (outsideSaving : candidate - candidateGC + saving ≤ reference - referenceGC)
    (gcRegression : candidateGC ≤ referenceGC + regression) :
    candidate + saving ≤ reference + regression := by
  omega

/-- A synchronized one-processor sample splits its GC wall interval
into GC CPU and the remaining wall interval. This is elapsed time not
charged as CPU. The sample cannot identify the OS reason for it. -/
theorem paired_cpu_wall_split (wall cpu gcWall gcCPU : Nat)
    (gcInsideWall : gcWall ≤ wall) (gcInsideCPU : gcCPU ≤ cpu)
    (gcCPUWithinWall : gcCPU ≤ gcWall)
    (otherCPUWithinWall : cpu - gcCPU ≤ wall - gcWall) :
    wall = gcCPU + (gcWall - gcCPU) + (cpu - gcCPU) +
      ((wall - gcWall) - (cpu - gcCPU)) := by omega

/-- Wall outside the measured collection window that is uncharged by
the owner thread clock. The collector's process CPU is comparable only
with a single collecting processor and aligned observations. -/
def outsideCollectorUncharged (wall ownerCPU gcWall gcCPU : Nat) : Nat :=
  (wall - gcWall) - (ownerCPU - gcCPU)

/-- If a change retains the elapsed interval outside collection up to
`outsideSaving`, a new collection charge must fit in the remaining
wall budget. The measured export window omits reporting. The skew
allowance only compensates the old observation boundary. -/
theorem collector_replacement_needs_outside_budget
    (exportWall gcWall outsideSaving skew nextGC limit : Nat) :
    exportWall - gcWall - outsideSaving - skew + nextGC < limit ↔
      nextGC < limit ∧
      exportWall - gcWall - outsideSaving - skew < limit - nextGC := by
  omega

/-- If the non-collector uncharged interval persists, removing all
recorded CPU and even the entire collector elapsed interval may still
leave the batch over budget. This floor is conditional on the next
execution retaining the interval, not a conclusion about scheduling. -/
theorem preserved_outside_uncharged_floor
    (exportWall ownerCPU gcWall gcCPU skew replacementWall : Nat)
    (retained : outsideCollectorUncharged exportWall ownerCPU gcWall gcCPU ≤
      replacementWall + skew) :
    outsideCollectorUncharged exportWall ownerCPU gcWall gcCPU - skew ≤ replacementWall :=
  Nat.sub_le_iff_le_add.mpr retained

/-- Charge the entire owner CPU interval to work outside collection.
The resulting floor needs no alignment between the collector's process
CPU clock and the owner thread clock. A lower bound on export wall and
upper bounds on collector wall and owner CPU suffice. -/
theorem outside_owner_gap_lower_bound
    (observedWall observedGC observedCPU skew wall gc ownerOutside : Nat)
    (wallBound : observedWall ≤ wall + skew)
    (gcBound : gc ≤ observedGC)
    (ownerBound : ownerOutside ≤ observedCPU) :
    observedWall - observedGC - observedCPU - skew ≤ wall - gc - ownerOutside := by
  omega

/-- Even removing all wall time uncharged as CPU leaves the CPU budget.
Apply only to the same synchronized sample, not to separate percentiles. -/
theorem paired_cpu_over_limit (wall cpu threshold : Nat)
    (within : cpu ≤ wall) (over : threshold ≤ cpu) :
    threshold ≤ wall - (wall - cpu) := by omega

/-- The runnable clock is a process counter. Its use here requires a
separately justified bound on other threads and counter endpoint skew.
Runnable time includes execution and time spent ready to execute. -/
theorem ready_wait_le_export_gap
    (exportWall runnable ownerCPU tolerance : Nat)
    (runnableBound : runnable ≤ exportWall + tolerance) :
    runnable - ownerCPU ≤ exportWall - ownerCPU + tolerance := by
  omega

/-- A timed reporting change cannot save a batch if its complete export
interval alone already reaches the budget after subtracting probe skew. -/
theorem export_phase_independently_exceeds_limit
    (exportWall reportWall admittedWall tolerance limit : Nat)
    (phaseBound : exportWall + reportWall ≤ admittedWall + tolerance)
    (exportMiss : limit + tolerance ≤ exportWall) :
    limit ≤ admittedWall := by
  omega

/-- For a strict wall budget, even eliminating every non-collector cost
requires reducing collector CPU by more than its excess over the budget.
Compare the same workload, with collector CPU bounded by elapsed time. -/
theorem collector_reduction_needed (oldCPU newCPU newWall threshold : Nat)
    (oldOver : threshold ≤ oldCPU) (cpuWithinWall : newCPU ≤ newWall)
    (newUnder : newWall < threshold) :
    oldCPU - threshold < oldCPU - newCPU := by omega

/-- Equal 32-export batch totals cannot identify single-export P95, even
when all latencies are positive and both input lists are already sorted.
Dividing a batch percentile by 32 is therefore not a percentile conversion. -/
theorem equal_batch_totals_do_not_identify_export_p95 :
    let concentrated := List.replicate 31 1 ++ [33]
    let uniform := List.replicate 32 2
    concentrated.Pairwise (· ≤ ·) ∧ uniform.Pairwise (· ≤ ·) ∧
      concentrated.length = 32 ∧ uniform.length = 32 ∧
      concentrated.sum = uniform.sum ∧ sortedP95 concentrated ≠ sortedP95 uniform := by
  decide

/-- A single-export threshold and a 32-export batch threshold express
different workloads. This witness assumes additive timings only. -/
theorem single_export_bound_does_not_imply_batch_bound :
    (List.replicate 32 4).all (· < 100) = true ∧
      100 < (List.replicate 32 4).sum := by decide

/-- Pair identities in the public binary export. The collector produces an
outer spine cell and the two cells created by `(list left right)` for each
row. The payload counts no private builder sentinel or captured axis cell. -/
structure BinaryRowCells where
  outer : Nat
  first : Nat
  second : Nat

def exportCells (rows : List BinaryRowCells) : List Nat :=
  rows.flatMap fun row => [row.outer, row.first, row.second]

theorem exportCells_length (rows : List BinaryRowCells) :
    (exportCells rows).length = rows.length * 3 := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    unfold exportCells
    rw [List.flatMap_cons, List.length_append]
    change 3 + (exportCells rest).length = (rest.length + 1) * 3
    rw [ih]
    omega

/-- If distinct positions are detached and each visible pair is fresh,
the allocation event sequence must include at least three pairs per row.
Apply this per export: reclaiming earlier results does not undo events. -/
theorem fresh_export_allocation_floor (rows : List BinaryRowCells) (allocated : List Nat)
    (detached : (exportCells rows).Nodup)
    (fresh : exportCells rows ⊆ allocated) :
    freshRowBytes rows.length ≤ allocated.length * 24 := by
  have count := detached.length_le_of_subset fresh
  rw [exportCells_length] at count
  exact Nat.mul_le_mul_right 24 count

/-- The native dense-cycle check marks the car of each of the three visible
pairs after reading the row. On this fixture every unmarked car is either
an integer or a row pair, so a fresh nonnumeric symbol makes a second visit
observable. This model accounts for visits, independently of GC movement. -/
def freshPairVisits (marked : List Nat) : List Nat → Prop
  | [] => True
  | id :: rest => id ∉ marked ∧ freshPairVisits (id :: marked) rest

theorem fresh_pair_visits_exact (marked trace : List Nat) :
    freshPairVisits marked trace ↔ trace.Nodup ∧
      ∀ id ∈ trace, id ∉ marked := by
  induction trace generalizing marked with
  | nil => simp [freshPairVisits]
  | cons id tail ih =>
    rw [freshPairVisits, ih, List.nodup_cons]
    constructor
    · rintro ⟨idFresh, distinct, fresh⟩
      refine ⟨⟨?_, distinct⟩, ?_⟩
      · intro repeated
        exact fresh id repeated (by simp)
      · intro cell member previous
        rcases List.mem_cons.mp member with same | later
        · subst cell
          exact idFresh previous
        · exact fresh cell later (List.mem_cons_of_mem id previous)
    · rintro ⟨⟨notRepeated, distinct⟩, fresh⟩
      refine ⟨fresh id (by simp), distinct, ?_⟩
      intro cell later previous
      rcases List.mem_cons.mp previous with same | earlier
      · subst cell
        exact notRepeated later
      · exact fresh cell (List.mem_cons_of_mem id later) earlier

/-- Count-only closure visits a singleton winner first and prepends each
retired singleton's member. The first source edge introduces 0 and 1 as
one roster block, whereas later insertions prepend one vertex at a time. -/
private theorem prepend_singletons (retired retained : List Nat) :
    retired.foldl (fun members vertex => vertex :: members) retained =
      retired.reverse ++ retained := by
  induction retired generalizing retained with
  | nil => rfl
  | cons vertex rest ih =>
    simp [List.foldl, ih, List.reverse_cons, List.append_assoc]

theorem count_only_dense_cycle_axis (laterBirths : List Nat) :
    (laterBirths.reverse ++ [0, 1]).foldl
      (fun members vertex => vertex :: members) [] = [1, 0] ++ laterBirths := by
  rw [prepend_singletons]
  simp

theorem heavy_payload : payload 384 = 339738624 := by decide
theorem large_payload : payload 512 = 603979776 := by decide
theorem large_budget : budgetedPayload 512 = 1207959552 := by decide

/-- Sensitivity calculation for a 512-vertex batch. With a 40 ms other
cost floor and 18 ms for each collection, at most three collections
fit. Even with an initial interval as large as each renewal, four
intervals of this size cannot cover the detached pair payload. These
time floors are explicit inputs, not claims about every observed pause. -/
theorem large_capacity_sensitivity (pauses : List Nat) (initial renewal other : Nat)
    (coverage : budgetedPayload 512 ≤ initial + pauses.length * renewal)
    (initialCap : initial ≤ 301989887) (renewalCap : renewal ≤ 301989887)
    (outside : 40000000 ≤ other) (each : ∀ pause ∈ pauses, 18000000 ≤ pause) :
    100000000 ≤ pauses.sum + other := by
  by_cases over : 100000000 ≤ pauses.sum + other
  · exact over
  · have capacity := passing_batch_requires_renewal_capacity pauses (budgetedPayload 512)
      initial renewal other 18000000 100000000 3 coverage each (by omega) (by omega) (by decide)
    rw [large_budget] at capacity
    omega

/-- Keep the public three-pair row and allocate its terminal cell as a
nonmoving Gambit object. The constructor counts the two movable pair
headers in both semispaces and the terminal body in one still object.
Still accounting can be deferred, so this charge is not a prediction of
the instantaneous allocation counter. -/
def terminalStillCharge (rows stillHeaderWords : Nat) : Nat :=
  rows * (2 * (2 * 3) + (stillHeaderWords + 2)) * 8

theorem terminalStillCharge_exceeds_movable (rows : Nat) :
    terminalStillCharge rows 6 = 2 * freshRowBytes rows + 16 * rows := by
  simp [terminalStillCharge, freshRowBytes, Nat.mul_comm, Nat.mul_left_comm]
  omega

/-- Model the native list control: an inner map makes a fresh list of
fresh two-cell tuples, the outer map holds one private descriptor per
left coordinate, and destructive concatenation links only those fresh
row spines. This models list values and payload, not the collector's
live charge, stack, or native compiler allocation events. -/
def mappedChunks (lefts rights : List α) : List (List (α × α)) :=
  lefts.map fun left => rights.map fun right => (left, right)

theorem mapped_chunks_exact (rectangle : ProviderRectangles.Rectangle α) :
    (mappedChunks rectangle.left rectangle.right).flatten =
      ProviderRectangles.rows rectangle := by
  simp [mappedChunks, ProviderRectangles.rows, List.flatten_eq_flatMap,
    List.flatMap_map]

/-- Delay inter-chunk links until every chunk has been allocated. The
backward stitch of the privately owned outer spines changes only their
terminal cdrs, and is represented by append. -/
def stitchChunks : List (List α) → List α
  | [] => []
  | chunk :: rest => chunk ++ stitchChunks rest

theorem stitched_chunks_exact (chunks : List (List α)) :
    stitchChunks chunks = chunks.flatten := by
  induction chunks with
  | nil => rfl
  | cons chunk rest ih => simp [stitchChunks, ih]

theorem stitched_product_exact (rectangle : ProviderRectangles.Rectangle α) :
    stitchChunks (mappedChunks rectangle.left rectangle.right) =
      ProviderRectangles.rows rectangle := by
  rw [stitched_chunks_exact, mapped_chunks_exact]

/-- Each nonempty private chunk retains a `(head . tail)` and one link in
the directory. The forward builder instead uses a 24-byte sentinel and a
16-byte box. The two-semispaces accounting doubles these private charges.
This equation excludes other VM allocations and stack changes. -/
theorem stitched_batch_private_charge (width : Nat) :
    2 * 32 * (2 * 24 * width) = 3072 * width ∧
      2 * 32 * (24 + 16) = 2560 := by omega

theorem stitched_fixed_width_counter_deltas :
    3072 * 384 - 2560 = 1177088 ∧
      3072 * 512 - 2560 = 1570304 := by decide

theorem mapped_chunks_payload (rectangle : ProviderRectangles.Rectangle α) :
    freshRowBytes (mappedChunks rectangle.left rectangle.right).flatten.length +
      (mappedChunks rectangle.left rectangle.right).length * 24 =
    freshRowBytes (rectangle.left.length * rectangle.right.length) +
      rectangle.left.length * 24 := by
  rw [mapped_chunks_exact, ProviderRectangles.rectangle_length]
  simp [mappedChunks]

/-- Fixed-width forward splice: publish four newly constructed row cells
in order, then continue from the unvisited axis suffix. The short suffix
uses the ordinary row path. This models visible order and pair payload;
it makes no claim about compiler heap-check placement or GC timing. -/
def fourRows (left : α) : List α → List (α × α)
  | a :: b :: c :: d :: rest =>
    (left, a) :: (left, b) :: (left, c) :: (left, d) :: fourRows left rest
  | rest => rest.map fun right => (left, right)

theorem fourRows_exact (left : α) (rights : List α) :
    fourRows left rights = rights.map (fun right => (left, right)) := by
  match rights with
  | [] => rfl
  | [_] => rfl
  | [_, _] => rfl
  | [_, _, _] => rfl
  | _ :: _ :: _ :: _ :: rest =>
    simp only [fourRows, List.map_cons, fourRows_exact left rest]

theorem fourRows_product_exact (rectangle : ProviderRectangles.Rectangle α) :
    rectangle.left.flatMap (fun left => fourRows left rectangle.right) =
      ProviderRectangles.rows rectangle := by
  simp [fourRows_exact, ProviderRectangles.rows]

theorem thousand_vertex_payload : payload 1000 = 2304000000 := by decide

/-- Conditional charge model for complete collection intervals. Units are
collector budget charges, not CPU time or physical bytes scanned. Frozen
`mem.c:adjust_heap` sizes the target from live occupancy when no custom
hook/minimum dominates; rounding, stacks, still objects and initial free
capacity must be accounted for before applying a concrete multiplier. -/
structure CollectorInterval where
  allocated : Nat
  available : Nat
  live : Nat

def intervalAllocations (intervals : List CollectorInterval) : Nat :=
  (intervals.map (·.allocated)).sum

def intervalLiveCharges (intervals : List CollectorInterval) : Nat :=
  (intervals.map (·.live)).sum

/-- If each interval's allocation capacity is bounded by a fixed multiple
of its live charge, total allocation requires proportional cumulative live
charges even when live occupancy changes between collections. A smaller
root set alone therefore does not establish a smaller amortized collector
cost. This is not a refinement or wall-time bound for the native collector. -/
theorem allocation_requires_cumulative_live_charge
    (intervals : List CollectorInterval) (freeMultiple : Nat)
    (bounded : ∀ interval ∈ intervals,
      interval.allocated ≤ interval.available ∧
        interval.available ≤ freeMultiple * interval.live) :
    intervalAllocations intervals ≤ freeMultiple * intervalLiveCharges intervals := by
  revert bounded
  induction intervals with
  | nil => simp [intervalAllocations, intervalLiveCharges]
  | cons interval rest ih =>
    intro bounded
    have first := bounded interval (by simp)
    have tail := ih (fun current member => bounded current (by simp [member]))
    simpa [intervalAllocations, intervalLiveCharges, Nat.mul_add] using
      Nat.add_le_add (Nat.le_trans first.1 first.2) tail

/-- A fixed initial reserve is separate from the capacities replenished by
collection. It cannot be silently charged as if a collection produced it. -/
theorem initial_reserve_accounted_separately
    (intervals : List CollectorInterval) (freeMultiple initial total : Nat)
    (bounded : ∀ interval ∈ intervals,
      interval.allocated ≤ interval.available ∧
        interval.available ≤ freeMultiple * interval.live)
    (coverage : total ≤ initial + intervalAllocations intervals) :
    total ≤ initial + freeMultiple * intervalLiveCharges intervals := by
  exact Nat.le_trans coverage
    (Nat.add_le_add_left (allocation_requires_cumulative_live_charge
      intervals freeMultiple bounded) initial)

/-- Even an empty allocation interval with the entire two-GiB budget cannot
hold the movable charge for this workload. This requires interval renewal,
not necessarily any particular number or duration of collector pauses. -/
theorem thousand_vertex_exceeds_empty_interval :
    2 * 1024 ^ 3 < budgetedPayload 1000 := by decide

/-- A batch can spend its initial free capacity once, then at most one
new interval per collection. The cap is an input bound, not a claim that
the last observed heap size is a hard limit on future intervals. -/
theorem renewed_capacity_bound (charges : List Nat) (cap : Nat)
    (bounded : ∀ charge ∈ charges, charge ≤ cap) :
    charges.sum ≤ charges.length * cap := by
  induction charges with
  | nil => simp
  | cons charge rest ih =>
    have first := bounded charge (by simp)
    have later := ih (fun x hx => bounded x (by simp [hx]))
    simp only [List.length_cons, List.sum_cons, Nat.add_mul, Nat.one_mul]
    omega

/-- Conditional exclusion of the 512-vertex target. The units are integer
milliseconds and movable accounting bytes. This applies only if an
independent trace/source bound supplies both the per-interval capacity
ceiling and the per-collection wall floor for the same execution. -/
theorem large_target_needs_capacity_or_pause_change
    (pauses charges : List Nat) (initial wall : Nat)
    (oneIntervalPerCollection : charges.length ≤ pauses.length)
    (initialCap : initial ≤ 180000000)
    (intervalCap : ∀ charge ∈ charges, charge ≤ 180000000)
    (pauseFloor : ∀ pause ∈ pauses, 27 ≤ pause)
    (coverage : budgetedPayload 512 ≤ initial + charges.sum)
    (wallBound : pauses.sum ≤ wall) :
    100 ≤ wall := by
  have capacity := renewed_capacity_bound charges 180000000 intervalCap
  have gc := collection_cost_floor pauses 27 pauseFloor
  rw [large_budget] at coverage
  omega

/-- Sensitivity analysis for the measured no-output collection cost.
If the same run has at least 18 ms of wall cost per collection, a passing
batch has at most five collections. Its six intervals cannot each have
at most 201,326,591 charged bytes, even with all non-GC work removed.
The empirical median does not establish the per-collection premise. -/
theorem large_target_needs_more_than_201mb_at_18ms
    (pauses charges : List Nat) (initial wall : Nat)
    (oneIntervalPerCollection : charges.length ≤ pauses.length)
    (initialCap : initial ≤ 201326591)
    (intervalCap : ∀ charge ∈ charges, charge ≤ 201326591)
    (pauseFloor : ∀ pause ∈ pauses, 18 ≤ pause)
    (coverage : budgetedPayload 512 ≤ initial + charges.sum)
    (wallBound : pauses.sum ≤ wall) : 100 ≤ wall := by
  have capacity := renewed_capacity_bound charges 201326591 intervalCap
  have gc := collection_cost_floor pauses 18 pauseFloor
  rw [large_budget] at coverage
  omega

/-- Reverse the factorized axes, not the quadratic output. The implementation
uses invocation-local tail-call accumulators; the theorem states its ordered
value semantics, not native cell ownership or compiler correctness. -/
theorem fold_prepend (values : List α) (f : α → β) (suffix : List β) :
    values.foldl (fun rows value => f value :: rows) suffix =
      (values.map f).reverse ++ suffix := by
  induction values generalizing suffix with
  | nil => simp
  | cons value rest ih => simp [List.foldl_cons, ih, List.append_assoc]

theorem reverse_prepend (values : List α) (f : α → β) (suffix : List β) :
    values.reverse.foldl (fun rows value => f value :: rows) suffix =
      values.map f ++ suffix := by
  rw [fold_prepend]
  simp

theorem reverse_prepend_blocks (values : List α) (f : α → List β)
    (suffix : List β) :
    values.reverse.foldl (fun rows value => f value ++ rows) suffix =
      values.flatMap f ++ suffix := by
  induction values with
  | nil => simp
  | cons value rest ih =>
      simp [List.reverse_cons, List.foldl_append, ih, List.append_assoc]

def collectReversedAxes (lefts rights : List α) : List (α × α) :=
  lefts.reverse.foldl
    (fun rows left => rights.reverse.foldl (fun rows right => (left, right) :: rows) rows) []

theorem reversed_axes_order_exact (rectangle : ProviderRectangles.Rectangle α) :
    collectReversedAxes rectangle.left rectangle.right = ProviderRectangles.rows rectangle := by
  simp only [collectReversedAxes, reverse_prepend]
  rw [reverse_prepend_blocks]
  simp [ProviderRectangles.rows]

/-- A backwards cursor over the packed axis gives the same row order.
The encoding premise is checked before any coordinate is narrowed. -/
theorem packed_axis_order_exact (rectangle : ProviderRectangles.Rectangle α)
    (packed : Array α) (left : packed.toList = rectangle.left)
    (right : packed.toList = rectangle.right) :
    collectReversedAxes packed.toList packed.toList = ProviderRectangles.rows rectangle := by
  exact (congr (congrArg collectReversedAxes left) right).trans
    (reversed_axes_order_exact rectangle)

/-- A packed unsigned 16-bit coordinate occupies two bytes. The payload
comparison counts the same detached output pairs on both paths. -/
theorem packed_axis_payload_smaller (width header : Nat)
    (amortized : header < 22 * width) :
    freshRowBytes (width * width) + header + 2 * width <
      freshRowBytes (width * width) + 24 * width := by omega

/-- Each inner Scheme step prepends `(cons (list left right) rows)`:
two fresh tuple cells and one fresh outer cell. This ledger describes that
constructor sequence, not collector copying or the runtime allocation counter. -/
def collectRightCost (left : α) (rights : List α)
    (initial : List (α × α) × Nat) : List (α × α) × Nat :=
  rights.foldl (fun state right => ((left, right) :: state.1, state.2 + 3)) initial

theorem collectRightCost_exact (left : α) (rights : List α)
    (rows : List (α × α)) (cells : Nat) :
    collectRightCost left rights (rows, cells) =
      (rights.foldl (fun rows right => (left, right) :: rows) rows,
       cells + 3 * rights.length) := by
  induction rights generalizing rows cells with
  | nil => simp [collectRightCost]
  | cons right rest ih =>
      simp only [collectRightCost, List.foldl_cons, List.length_cons]
      change collectRightCost left rest ((left, right) :: rows, cells + 3) = _
      rw [ih]
      congr 1
      omega

def collectProductCost (lefts rights : List α)
    (initial : List (α × α) × Nat) : List (α × α) × Nat :=
  lefts.foldl (fun state left => collectRightCost left rights state) initial

theorem collectProductCost_exact (lefts rights : List α)
    (rows : List (α × α)) (cells : Nat) :
    collectProductCost lefts rights (rows, cells) =
      (lefts.foldl
        (fun rows left => rights.foldl (fun rows right => (left, right) :: rows) rows) rows,
       cells + 3 * (lefts.length * rights.length)) := by
  induction lefts generalizing rows cells with
  | nil => simp [collectProductCost]
  | cons left rest ih =>
      simp only [collectProductCost, List.foldl_cons, List.length_cons]
      rw [collectRightCost_exact]
      change collectProductCost rest rights _ = _
      rw [ih]
      congr 1
      simp [Nat.add_mul, Nat.mul_add]
      omega

/-- A Scheme spine cursor is either a pair, the proper terminator, or
an improper tail. The emitted row and the fallback action depend on
that shape, independently of the order of the pair and null tests. -/
inductive ExportCursor where
  | pair | nil | improper
  deriving DecidableEq

def ExportCursor.action (cursor : ExportCursor) : Nat :=
  if cursor = .nil then 0 else if cursor = .pair then 1 else 2

theorem pair_first_preserves_cursor_action (cursor : ExportCursor) :
    (if cursor = .pair then 1 else if cursor = .nil then 0 else 2) =
      cursor.action := by
  cases cursor <;> decide

/-- On proper axes, moving the pair test first saves one tag test for
every input pair and adds one for every terminating null. The inner
cursor is restarted once per left member. Row allocation is identical. -/
theorem pair_first_product_tag_tests (left right : Nat) :
    let nullFirst := 2 * (left + left * right) + (left + 1)
    let pairFirst := (left + left * right) + 2 * (left + 1)
    pairFirst + left * right = nullFirst + 1 := by
  omega

/-- On a proper shared axis the private Scheme specialization reverses the
axis once and executes the two nested loops. The first projection proves
ordered answers; the second counts exactly the constructor pair events.
The guard, capture, VM stack, GC and wall time remain separate obligations. -/
theorem shared_axis_cost_and_answers (axis : List α) :
    collectProductCost axis.reverse axis.reverse ([], axis.length) =
      (collectReversedAxes axis axis,
       axis.length + 3 * (axis.length * axis.length)) := by
  rw [collectProductCost_exact]
  simp [collectReversedAxes]

/-- A row-local constructor removes two tail-maintenance writes per row,
but copying the axes is additional work. Counts alone establish a benefit
only under a cost inequality; they imply no wall-clock or P95 guarantee. -/
theorem axis_copy_cost_criterion (rows axisCells pairCost tailWriteCost : Nat)
    (worthwhile : axisCells * pairCost < 2 * rows * tailWriteCost) :
    3 * rows * pairCost + axisCells * pairCost <
      3 * rows * pairCost + 2 * rows * tailWriteCost := by
  omega

/-- Public specialization validates its borrowed axis before copying it.
The private-loop criterion above does not pay this preflight charge. -/
theorem public_axis_cost_criterion
    (rows axisCells pairCost preflightCharge tailWriteCost : Nat)
    (worthwhile : preflightCharge + axisCells * pairCost < 2 * rows * tailWriteCost) :
    3 * rows * pairCost + preflightCharge + axisCells * pairCost <
      3 * rows * pairCost + 2 * rows * tailWriteCost := by
  omega

def builderConstructorPayload (width : Nat) : Nat :=
  3 * (width * width) * 24 + 40

def selfProductConstructorPayload (width : Nat) : Nat :=
  3 * (width * width) * 24 + width * 24

theorem self_product_quadratic_margin (width : Nat) :
    480 * width ≤ 72 * (width * width) + 840 := by
  by_cases large : 7 ≤ width
  · have scale : 20 ≤ 3 * width := by omega
    have lower : 20 * width ≤ 3 * (width * width) := by
      simpa [Nat.mul_assoc] using Nat.mul_le_mul_right width scale
    omega
  · have cases : width = 0 ∨ width = 1 ∨ width = 2 ∨ width = 3 ∨
        width = 4 ∨ width = 5 ∨ width = 6 := by omega
    rcases cases with h | h | h | h | h | h | h <;> subst width <;> decide

/-- A physical shared axis needs one reverse copy. Its constructor payload
adds at most five percent over the old three-pair rows plus sentinel/box,
at every width. This uses the frozen 64-bit pair=24/box=16 representation;
it excludes GC copying, stack occupancy and other library allocations. -/
theorem self_product_constructor_amplification (width : Nat) :
    20 * selfProductConstructorPayload width ≤
      21 * builderConstructorPayload width := by
  have margin := self_product_quadratic_margin width
  unfold selfProductConstructorPayload builderConstructorPayload
  omega

/-- Arbitrary thin products lack the square's amortization guarantee. -/
theorem thin_product_copy_exceeds_five_percent :
    21 * (3 * 100 * 24 + 40) < 20 * (3 * 100 * 24 + 101 * 24) := by decide

/-- The native diagnostic repeats one complete export 32 times. Under the
frozen two-semispaces accounting, removing the builder sentinel and box
saves 80 counter bytes per export, while copying the axis costs 48 per
member. This ledger does not predict whether the added charge crosses
the next allocation limit. -/
theorem reverse_axis_batch_counter_difference (width : Nat) :
    2 * 32 * selfProductConstructorPayload width + 80 * 32 =
      2 * 32 * builderConstructorPayload width + 48 * width * 32 := by
  unfold selfProductConstructorPayload builderConstructorPayload
  omega

theorem reverse_axis_fixed_width_counter_deltas :
    2 * 32 * selfProductConstructorPayload 384 -
        2 * 32 * builderConstructorPayload 384 = 587264 ∧
    2 * 32 * selfProductConstructorPayload 512 -
        2 * 32 * builderConstructorPayload 512 = 783872 := by decide

/-- A suspended inner call holds one coordinate and a suffix. Rows are
allocated on return, so no reversed copy of either input axis is needed. -/
def unwindRight (left : α) (rights : List α) (suffix : List (α × α)) :
    List (α × α) :=
  rights.foldr (fun right rows => (left, right) :: rows) suffix

theorem unwindRight_exact (left : α) (rights : List α) (suffix : List (α × α)) :
    unwindRight left rights suffix = rights.map (fun right => (left, right)) ++ suffix := by
  induction rights with
  | nil => rfl
  | cons right rest ih =>
    change (left, right) :: unwindRight left rest suffix =
      (left, right) :: (rest.map (fun value => (left, value)) ++ suffix)
    rw [ih]

def unwindProduct (lefts rights : List α) : List (α × α) :=
  lefts.foldr (fun left rows => unwindRight left rights rows) []

theorem unwindProduct_exact (rectangle : ProviderRectangles.Rectangle α) :
    unwindProduct rectangle.left rectangle.right = ProviderRectangles.rows rectangle := by
  rcases rectangle with ⟨lefts, rights⟩
  induction lefts with
  | nil => rfl
  | cons left rest ih =>
    simp only [unwindProduct, List.foldr_cons] at ih ⊢
    rw [unwindRight_exact, ih]
    rfl

/-- When building a right-axis suffix, only the unreturned outer frames
and the current inner suffix can coexist. This is a bound on model
frames, not VM stack bytes or collector traffic. -/
theorem unwind_frames_bound (leftDepth rightDepth width : Nat)
    (leftBound : leftDepth ≤ width) (rightBound : rightDepth ≤ width) :
    leftDepth + rightDepth ≤ 2 * width := by omega

/-- Eliminating the axis copy leaves only the three row pairs. This term
excludes stack allocation and any allocation done by the collector. -/
theorem unwind_constructor_saves_builder_charge (width : Nat) :
    2 * 32 * builderConstructorPayload width =
      2 * 32 * (3 * (width * width) * 24) + 2560 := by
  unfold builderConstructorPayload
  omega

/-- Scoped to the observed binary export loop: one complete private row may
be allocated before its interrupt poll. A second row cannot bypass that poll.
The compiler-to-event correspondence is an explicit external obligation. -/
inductive PollEvent where
  | row
  | poll
  deriving DecidableEq

def RowPollTrace (pending : Nat) : List PollEvent → Prop
  | [] => pending = 0
  | .row :: rest => pending = 0 ∧ RowPollTrace 1 rest
  | .poll :: rest => RowPollTrace 0 rest

def binaryLoopTrace : Nat → List PollEvent
  | 0 => []
  | n + 1 => .row :: .poll :: binaryLoopTrace n

theorem binary_loop_preserves_row_poll (rows : Nat) :
    RowPollTrace 0 (binaryLoopTrace rows) := by
  induction rows with
  | zero => simp [binaryLoopTrace, RowPollTrace]
  | succ rows ih => simpa [binaryLoopTrace, RowPollTrace] using ih

/-- The unrestricted emitted loop peeled three row constructors before its
loop-back poll. Value equivalence alone would not reject that schedule. -/
theorem three_rows_one_poll_rejected :
    ¬ RowPollTrace 0 [.row, .row, .row, .poll] := by
  simp [RowPollTrace]

/-- Two consecutive 512-vertex admissions each create 32 detached exports.
If their movable payload uses one allocation interval, even an empty
two-GiB budget cannot supply both. This bound does not assign a collection
to either admission or predict a pause duration. -/
theorem two_large_admissions_exceed_one_interval (available : Nat)
    (capped : available ≤ 2 * 1024 ^ 3) :
    available < budgetedPayload 512 + budgetedPayload 512 := by
  apply Nat.lt_of_le_of_lt capped
  decide

/-- An uninterrupted stream can spend its initial capacity once. Each
collection renews at most one interval. The premise bounds spendable
charge in the same units as the pair allocation, including any active
section remainder. The charge is not process RSS. -/
theorem stream_capacity (batches vertices initial cap : Nat) (renewals : List Nat)
    (coverage : batches * budgetedPayload vertices ≤ initial + renewals.sum)
    (initialBound : initial ≤ cap)
    (renewalBound : ∀ charge ∈ renewals, charge ≤ cap) :
    batches * budgetedPayload vertices ≤ (renewals.length + 1) * cap := by
  have later := renewed_capacity_bound renewals cap renewalBound
  rw [Nat.add_mul, Nat.one_mul]
  omega

/-- Even granting the entire two-GiB cap to pair allocation after every
collection, a hundred 512-vertex batches require at least 56 renewals.
Collections at batch boundaries count too. This bound concerns a stream,
and gives neither a per-batch count nor a pause bound. -/
theorem hundred_large_batches_need_56_renewals (initial : Nat) (renewals : List Nat)
    (coverage : 100 * budgetedPayload 512 ≤ initial + renewals.sum)
    (initialBound : initial ≤ 2 * 1024 ^ 3)
    (renewalBound : ∀ charge ∈ renewals, charge ≤ 2 * 1024 ^ 3) :
    56 ≤ renewals.length := by
  have charge := stream_capacity 100 512 initial (2 * 1024 ^ 3) renewals
    coverage initialBound renewalBound
  rw [large_budget] at charge
  omega

/-- Keep the large-scale workload and its output cardinality distinct.
A single complete 10k clique exceeds the 2 GiB limit from pair cells alone;
100 disjoint size-100 components have 1M rows and a smaller live result.
Neither calculation bounds the overhead of the current implementation. -/
theorem dense_ten_thousand_exceeds_limit :
    2 * 1024 ^ 3 < freshRowBytes (10000 ^ 2) := by decide
theorem grouped_million_result :
    freshRowBytes (100 * 100 ^ 2) = 72000000 := by decide

/-- Byte-quantum capacity projection. Free and refill exclude stacks,
fragmentation and reserve. The real collector's refill is not a constant;
the following lemma requires a lower bound for every post-GC refill. -/
def collections (work free refill : Nat) : Nat :=
  if work ≤ free then 0 else 1 + (work - free - 1) / refill

theorem at_most_one_collection (work free refill : Nat) (fits : work ≤ refill) :
    collections work free refill ≤ 1 := by
  unfold collections
  split
  · decide
  · have less : work - free - 1 < refill := by omega
    simp [Nat.div_eq_of_lt less]

/-- An explicit boundary collection can replace a collection during list
construction only if the entire charged batch fits in the new interval.
It still incurs one pause even for a batch that would not have collected. -/
theorem boundary_collection_count (work free refill : Nat) (fits : work ≤ free) :
    1 + collections work free refill = 1 := by
  simp [collections, fits]

/-- Same-batch comparison including the entire explicit pause. An empty
prefix cannot establish a gain by itself. The full boundary pause and all
remaining elapsed work must beat the natural construction and its pauses. -/
theorem charged_boundary_improvement_iff
    (naturalOther boundaryOther boundaryPause : Nat) (naturalPauses : List Nat) :
    boundaryOther + boundaryPause < naturalOther + naturalPauses.sum ↔
      (boundaryOther : Int) - naturalOther < (naturalPauses.sum : Int) - boundaryPause := by
  omega

/-- A boundary intervention belongs to the owner of the allocation window.
If applied to each of 32 individual exports, even a 3.125 ms floor per
pause exhausts the batch's strict wall budget before construction. The
floor must hold for every pause in the same observed batch. -/
theorem per_export_collection_rejects_batch (pauses : List Nat) (wall : Nat)
    (count : 32 ≤ pauses.length)
    (pauseFloor : ∀ pause ∈ pauses, 3125000 ≤ pause)
    (within : pauses.sum ≤ wall) :
    100000000 ≤ wall := by
  have gc := collection_cost_floor pauses 3125000 pauseFloor
  omega

/-- Sizing target, not a measured free-space guarantee. The maximum live
budget is from the retained 100-attempt diagnostic; future heaps must be
checked. The remainder must cover all capture/stack/section overhead. -/
theorem proposed_budget_margin :
    1344 * 1048576 - 142159880 - budgetedPayload 512 = 59166712 := by decide

/-- Gambit mem.c `adjust_heap`, when no adjust hook is installed and the
percentage is less than 100. The minimum and live inputs are in words.
This is the target before section rounding, reserve and maximum handling. -/
def proportionalTargetWords (live minimum percent : Nat) : Nat :=
  max minimum ((live / percent) * 100)

/-- On a successful resize, Gambit `resize_heap` charges the requested
still words before `adjust_heap` and before deriving the section cap.
The charge is for the imminent still object, including its header. It
raises reported live occupancy and consumes part of the same heap cap. -/
theorem still_request_charges_live_and_cap (movable still requested cap : Nat) :
    (movable + (still + requested)) - (movable + still) = requested ∧
    cap - (still + requested) ≤ cap - still := by omega

/-- A minimum-heap control can vary raw allocation headroom without
changing the live ratio. This is the adjust-heap target before section
rounding, reserve, resize history, and maximum handling. -/
theorem heap_minimum_dominates_proportional_target (live minimum percent : Nat)
    (dominates : (live / percent) * 100 ≤ minimum) :
    proportionalTargetWords live minimum percent = minimum := by
  exact Nat.max_eq_left dominates

/-- Native `setup_mem_vmstate` limits the requested minimum to the same
maximum before converting it to sections. The zero maximum is Gambit's
unlimited case. The later processor minimum and rounding are separate. -/
def initialHeapRequest (minimum maximum : Nat) : Nat :=
  if maximum = 0 then minimum else min minimum maximum

theorem initial_heap_request_respects_cap (minimum maximum : Nat)
    (limited : maximum ≠ 0) : initialHeapRequest minimum maximum ≤ maximum := by
  simpa [initialHeapRequest, limited] using Nat.min_le_right minimum maximum

theorem prelinked_observed_heap_targets :
    proportionalTargetWords (916272 / 8) (64 * 1048576 / 8) 50 * 8 = 67108864 ∧
    proportionalTargetWords (1056048 / 8) (64 * 1048576 / 8) 50 * 8 = 67108864 ∧
    initialHeapRequest (256 * 1048576) (2 * 1024 ^ 3) = 268435456 := by decide

/-- The observed high live budget of the 512-vertex control leaves room
in the raw target at 1344 MiB, even with the live ratio kept at 50.
This does not establish how much memory is resident or how long it takes
to fault in that memory. -/
theorem fixed_minimum_default_ratio_control :
    proportionalTargetWords (142159880 / 8) (1344 * 1048576 / 8) 50 * 8 =
      142159880 + budgetedPayload 512 + 59166712 := by
  decide

/-- The default branch's raw target minus live words, before the runtime's
minimum, reserve, history and section-size adjustments. -/
def rawHeadroom50 (liveWords : Nat) : Int :=
  (proportionalTargetWords liveWords 0 50 : Int) - liveWords

/-- At an aligned change of live words, the target changes by twice that
change. Raw free capacity changes in the same direction as liveness,
even though the copy volume can fall when liveness falls. -/
theorem rawHeadroom50_aligned (liveWords blocks : Nat) :
    rawHeadroom50 (liveWords + 50 * blocks) =
      rawHeadroom50 liveWords + 50 * (blocks : Int) := by
  unfold rawHeadroom50 proportionalTargetWords
  simp only [Nat.zero_max]
  omega

/-- Divide-first rounding loses at most 98 words at the default ratio.
This does not bound the actual number of collections. -/
theorem rawHeadroom50_rounding (liveWords : Nat) :
    (liveWords : Int) - 98 ≤ rawHeadroom50 liveWords ∧
      rawHeadroom50 liveWords ≤ (liveWords : Int) := by
  unfold rawHeadroom50 proportionalTargetWords
  simp only [Nat.zero_max]
  omega

/-- `compute_free_heap_space_approximately` in the pinned 64-bit Gambit
build. Whole-section admission is evaluated after subtracting still bytes,
assigned sections and the overflow reserve. -/
def unassignedSections (heap still assigned reserve : Nat) : Nat :=
  (heap - still - reserve) / 1048576 - assigned

theorem native_section_admission (heap still assigned reserve : Nat) :
    0 < unassignedSections heap still assigned reserve ↔
      1048576 * (assigned + 1) + still + reserve ≤ heap := by
  unfold unassignedSections
  omega

/-- A collection at an export boundary can eliminate an in-flight
collection only if the renewed interval covers that export. Counting
only rows and ignoring the actual renewal capacity would not justify
the intervention. The `extra` term covers all non-row charges through
the last allocation of this call. -/
theorem boundary_export_capacity (rows extra active freshSections sectionCharge : Nat)
    (fit : 144 * rows + extra ≤ active + freshSections * sectionCharge)
    (before : Nat) (prefixCharge : before ≤ 144 * rows + extra) :
    before ≤ active + freshSections * sectionCharge :=
  Nat.le_trans prefixCharge fit

/-- If both allocations individually fit but their sum does not, placing
a renewal between them removes pressure inside either output. This is
an interval arithmetic law, not a rule that the VM must collect only
when the modeled pair charge is exhausted. -/
theorem boundary_moves_pressure (previous next available renewed : Nat)
    (previousFits : previous ≤ available) (crosses : available < previous + next)
    (nextFits : next ≤ renewed) :
    available - previous < next ∧ next ≤ renewed := by
  omega

/-- A batch whose collections have all moved to its internal export
boundaries still pays every pause in its elapsed interval. The example
is a necessary per-pause floor, supplied independently for the batch. -/
theorem sixteen_boundary_pauses_budget (pauses : List Nat) (wall : Nat)
    (count : 16 ≤ pauses.length)
    (floor : ∀ pause ∈ pauses, 6250000 ≤ pause)
    (within : pauses.sum ≤ wall) :
    100000000 ≤ wall := by
  have gc := collection_cost_floor pauses 6250000 floor
  omega

/-- Partition the sum of post-copy movable occupancy into a repeated
background floor and per-collection excess. Both terms use the runtime's
charge units. The excess may include frames, chunk links and other roots
besides partially built output. Neither term is a wall-clock estimate. -/
theorem repeated_copy_charge (charges : List Nat) (background : Nat)
    (bounded : ∀ charge ∈ charges, background ≤ charge) :
    charges.sum = charges.length * background + (charges.map (· - background)).sum := by
  induction charges with
  | nil => simp
  | cons head tail ih =>
    have first := bounded head (by simp)
    have rest := ih (fun charge member => bounded charge (by simp [member]))
    simp only [List.sum_cons, List.length_cons, Nat.add_mul, Nat.one_mul, List.map_cons]
    omega

/-- The background charge from additional pauses can exceed the entire
old excess even when every new pause copies no output. Supply the floor
for the same comparison and the complete collection counts. -/
theorem additional_collections_outweigh_all_excess (old next : List Nat) (background : Nat)
    (oldBound : ∀ charge ∈ old, background ≤ charge)
    (nextBound : ∀ charge ∈ next, background ≤ charge)
    (exceeds : old.length * background + (old.map (· - background)).sum <
      next.length * background) :
    old.sum < next.sum := by
  rw [repeated_copy_charge old background oldBound, repeated_copy_charge next background nextBound]
  omega

/-- The nominal movable accounting charge of a newly admitted section.
The active semispace starts at 65536 words and reserves 8194 words for
the largest frame/object. The allocator may cross the soft limit, and
already active sections, stack changes and GC chunk markers are separate. -/
def sectionPayloadBytes : Nat := 16 * (65536 - 8194)

/-- Within a successful allocation interval, mapped semispaces bound
the pair allocation even if every word is granted to the materializer.
This generous ceiling ignores occupied space, stack sections and the
allocator reserve. No still-object payload is credited to these pairs. -/
theorem movable_pair_interval_fits_mapped_sections
    (pairs allocatedWords usableWords sections : Nat)
    (pairWords : 3 * pairs ≤ allocatedWords)
    (fits : allocatedWords ≤ usableWords)
    (mapped : usableWords ≤ 65536 * sections) :
    48 * pairs ≤ 1048576 * sections := by
  omega

/-- The frozen heap limit can take a released stack section or assign an
unassigned section. Either transition trades one existing section for
one new heap segment. The collector can replenish the stock separately. -/
inductive SectionAdvance : Nat → Nat → Nat → Nat → Prop where
  | reuse (available unused : Nat) :
      SectionAdvance (available + 1) unused available unused
  | assign (available unused : Nat) :
      SectionAdvance available (unused + 1) available unused

theorem section_advance_spends_one
    {released unassigned nextReleased nextUnassigned : Nat}
    (advance : SectionAdvance released unassigned nextReleased nextUnassigned) :
    nextReleased + nextUnassigned + 1 = released + unassigned := by
  cases advance <;> omega

/-- The mutator can install a recycled stack section as its next heap
section. Both heap transitions reset the active heap cursor. Transfer
the old span to the retired ledger before that reset. The equation
holds between collections while the other counter terms stay fixed. -/
theorem recycled_heap_section_preserves_charge
    (adjusted retired active nextActive stack processorStill vmStill : Int) :
    counter adjusted (retired + active + nextActive) stack processorStill vmStill -
      counter adjusted (retired + active) stack processorStill vmStill =
    2 * nextActive := by
  unfold counter movableBudget
  omega

/-- Resetting the active cursor without transferring its span loses
exactly twice that span in the movable accounting domain. -/
theorem uncharged_recycled_heap_section_loses_retired_span
    (adjusted retired active nextActive stack processorStill vmStill : Int) :
    counter adjusted (retired + active + nextActive) stack processorStill vmStill -
      counter adjusted (retired + nextActive) stack processorStill vmStill =
    2 * active := by
  unfold counter movableBudget
  omega

/-- Released stack sections are already mapped and assigned. Even
crediting them all before the next collection cannot increase the
whole-mapped-span ceiling used by the complete export model. -/
theorem free_stack_sections_stay_inside_mapped_span
    (assigned mapped released : Nat)
    (within : assigned ≤ mapped) (subset : released ≤ assigned) :
    released + (mapped - assigned) ≤ mapped := by
  omega

/-- Growing the stock without moving any live object is admissible in the
same accounting domain as `resize_heap`. The actual mapped count can be
smaller than requested after a partial allocation. -/
theorem section_growth_respects_heap_cap
    (sectionWords still cap requested mapped : Nat)
    (stillFits : still ≤ cap)
    (targetFits : requested ≤ (cap - still) / sectionWords)
    (actualFits : mapped ≤ requested) :
    mapped * sectionWords + still ≤ cap := by
  by_cases positive : 0 < sectionWords
  · have charge : (cap - still) / sectionWords * sectionWords ≤ cap - still := Nat.div_mul_le_self _ _
    have claim := Nat.mul_le_mul_right sectionWords (Nat.le_trans actualFits targetFits)
    omega
  · obtain rfl : sectionWords = 0 := by omega
    simpa using stillFits

/-- A successful no-copy assignment consumes one already mapped section
and leaves the same overflow reserve. On a failed guard the original
collector path is still required. -/
theorem grown_section_preserves_reserve (sectionWords assigned mapped reserve : Nat)
    (fits : assigned * sectionWords + reserve + sectionWords ≤ mapped * sectionWords) :
    (assigned + 1) * sectionWords + reserve ≤ mapped * sectionWords := by
  simpa [Nat.add_mul, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using fits

/-- A pressure collection can reuse the previously mapped sections.
Clamp the retention floor to the current ceiling, which may have fallen
as still occupancy grew. The ordinary target remains a lower bound. -/
theorem pressure_resize_retention_bounds (ordinary previous ceiling : Nat)
    (ordinaryFits : ordinary ≤ ceiling) :
    let retained := max ordinary (min previous ceiling)
    ordinary ≤ retained ∧ retained ≤ ceiling ∧ retained ≤ max ordinary previous := by
  exact ⟨Nat.le_max_left _ _, Nat.max_le.mpr ⟨ordinaryFits, Nat.min_le_right _ _⟩,
    Nat.max_le.mpr ⟨Nat.le_max_left _ _, Nat.le_trans (Nat.min_le_left _ _) (Nat.le_max_right _ _)⟩⟩

/-- A soft ceiling limits opportunistic growth. The original heap cap and
still occupancy also bound each attempted section map. -/
theorem soft_growth_target_bounds (requested cap softCap still sectionWords : Nat) :
    let target := min requested ((min cap softCap - still) / sectionWords)
    target ≤ (cap - still) / sectionWords ∧ target ≤ (softCap - still) / sectionWords := by
  simp only
  exact ⟨Nat.le_trans (Nat.min_le_right _ _)
    (Nat.div_le_div_right (Nat.sub_le_sub_right (Nat.min_le_left _ _) _)),
    Nat.le_trans (Nat.min_le_right _ _)
      (Nat.div_le_div_right (Nat.sub_le_sub_right (Nat.min_le_right _ _) _))⟩

/-- One GiB of sections cannot cover the 512 pair charge in one interval
at the nominal section payload. Two nominal intervals have room before
subtracting live objects, the stack, the reserve and other allocations. -/
theorem one_gib_growth_envelope :
    1024 * sectionPayloadBytes < budgetedPayload 512 ∧
      budgetedPayload 512 ≤ 2 * (1024 * sectionPayloadBytes) := by decide

/-- A section budget that can pay for the export with at most `renewals`
collections must cover all pair charges in that many intervals plus
the initial interval. This grants the whole semispace to each interval. -/
theorem minimum_mapped_sections_for_renewals
    (payload renewals sections : Nat)
    (coverage : payload ≤ (renewals + 1) * (1048576 * sections)) :
    (payload + (1048576 * (renewals + 1)) - 1) /
      (1048576 * (renewals + 1)) ≤ sections := by
  have positive : 0 < 1048576 * (renewals + 1) :=
    Nat.mul_pos (by decide) (Nat.zero_lt_succ renewals)
  apply Nat.le_of_lt_succ
  apply (Nat.div_lt_iff_lt_mul positive).mpr
  rw [Nat.succ_eq_add_one, Nat.add_mul, Nat.one_mul]
  have reordered : (renewals + 1) * (1048576 * sections) =
      sections * (1048576 * (renewals + 1)) := by ac_rfl
  rw [reordered] at coverage
  omega

/-- Arithmetic ceilings before subtracting occupied and reserved words.
The 512 natural trace measured at most 276 mapped sections. -/
theorem weighted_minimum_mapped_section_counts :
    (budgetedPayload 384 + 1048576 * 3 - 1) / (1048576 * 3) = 216 ∧
    (budgetedPayload 512 + 1048576 * 3 - 1) / (1048576 * 3) = 384 ∧
    (budgetedPayload 512 + 1048576 * 4 - 1) / (1048576 * 4) = 288 ∧
    (budgetedPayload 512 + sectionPayloadBytes * 3 - 1) /
      (sectionPayloadBytes * 3) = 439 := by decide

/-- Price the necessary number of collections when every interval is
allowed the entire mapped section span. The measured pause and outside
floors are independent premises for the proposed change. -/
def mappedSectionsFloor (payload sections outside pause : Nat) : Nat :=
  let capacity := 1048576 * sections
  pauseScheduleFloor outside pause ((payload + capacity - 1) / capacity - 1)

theorem mapped_sections_floor_sound
    (payload sections outside pause wall : Nat) (pauses : List Nat)
    (nonempty : 0 < sections)
    (coverage : payload ≤ (pauses.length + 1) * (1048576 * sections))
    (pauseFloor : ∀ duration ∈ pauses, pause ≤ duration)
    (accounted : outside + pauses.sum ≤ wall) :
    mappedSectionsFloor payload sections outside pause ≤ wall := by
  have positive : 0 < 1048576 * sections := by omega
  have intervals : (payload + 1048576 * sections - 1) / (1048576 * sections) ≤
      pauses.length + 1 := by
    apply Nat.le_of_lt_succ
    apply (Nat.div_lt_iff_lt_mul positive).mpr
    rw [Nat.succ_eq_add_one, Nat.add_mul, Nat.one_mul]
    omega
  exact pause_schedule_floor_sound pauses outside pause _ wall
    (by omega) pauseFloor accounted

/-- Convert the measured 512 charge thresholds to whole section counts
in the nominal allocator equation. This example grants no credit for
an already active remainder and excludes overflow and stack reserves. -/
theorem large_interval_nominal_section_targets :
    329 * sectionPayloadBytes < 301989888 ∧
      301989888 ≤ 330 * sectionPayloadBytes ∧
      438 * sectionPayloadBytes < 402653184 ∧
      402653184 ≤ 439 * sectionPayloadBytes := by decide

/-- Initial setup rounds a payload target by usable section charge, then
applies the processor minimum. It does not use the later resize clamp
on mapped bytes. The caller supplies the processor minimum in sections. -/
def initialSectionCount (requested processorMinimum : Nat) : Nat :=
  max processorMinimum ((requested + sectionPayloadBytes - 1) / sectionPayloadBytes)

theorem initial_mapped_sections_respect_cap_iff (requested processorMinimum cap : Nat) :
    initialSectionCount requested processorMinimum * 1048576 ≤ cap ↔
      processorMinimum ≤ cap / 1048576 ∧
      requested ≤ (cap / 1048576) * sectionPayloadBytes := by
  unfold initialSectionCount sectionPayloadBytes
  omega

/-- A byte ceiling enforced only before rounding can admit more mapped
space than requested. The 2 GiB control allows 2048 physical sections,
which carry 1791.9375 MiB of usable payload in this setup equation. -/
theorem initial_two_gib_section_boundary :
    (2 * 1024 ^ 3 / 1048576) * sectionPayloadBytes = 1878982656 ∧
      initialSectionCount (1791 * 1048576) 2 * 1048576 = 2146435072 ∧
      initialSectionCount (1792 * 1048576) 2 * 1048576 = 2148532224 := by decide

/-- The two explicit CLI controls matched the startup section equation.
These are observed section counts before the timed export phases. -/
theorem native_startup_sections_replay :
    initialSectionCount (1344 * 1048576) 2 = 1537 ∧
      initialSectionCount (1664 * 1048576) 2 = 1902 := by decide

/-- `resize_heap` rounds the target up by the usable section charge,
adds stack sections and clips by the cap after accounting for still objects.
This is the successful minimum-dominated branch with one stack section;
the lower bound is inert when it is at most the rounded target. -/
def minimumTargetSections (minimum still reserve cap : Nat) : Nat :=
  min (((minimum + reserve - still + sectionPayloadBytes - 1) /
      sectionPayloadBytes) + 1) ((cap - still) / 1048576)

theorem minimum_target_sections_respect_cap (minimum still reserve cap : Nat)
    (fits : still ≤ cap) :
    minimumTargetSections minimum still reserve cap * 1048576 + still ≤ cap := by
  have sections := Nat.min_le_right
    (((minimum + reserve - still + sectionPayloadBytes - 1) / sectionPayloadBytes) + 1)
    ((cap - still) / 1048576)
  unfold minimumTargetSections
  omega

/-- A one-GiB minimum provides nominal room for the 384 batch under the
recorded section ledger. The 512 batch needs additional capacity. A 1344
MiB minimum fits the 512 payload with the same heap cap in this model. -/
theorem observed_minimum_section_budgets :
    let reserve := 1638464
    let still := 4876200
    let cap := 2 * 1024 ^ 3
    let small := minimumTargetSections (1024 * 1048576) still reserve cap
    let large := minimumTargetSections (1344 * 1048576) still reserve cap
    budgetedPayload 384 ≤ (small - 97 - 2) * sectionPayloadBytes ∧
    (small - 117 - 2) * sectionPayloadBytes < budgetedPayload 512 ∧
    budgetedPayload 512 ≤ (large - 117 - 2) * sectionPayloadBytes := by
  decide

/-- At the default live ratio, a retained still object enters the live
numerator as well as the charged occupancy. Below the cap, adding a
word of still payload can buy at most one word of raw movable headroom
apart from divide-first rounding. At the cap it consumes headroom.
This envelope excludes section rounding, stacks, reserve and history. -/
def cappedRawHeadroom50 (live cap : Nat) : Nat :=
  min (proportionalTargetWords live 0 50) cap - live

theorem capped_raw_headroom50_bound (live cap : Nat) :
    cappedRawHeadroom50 live cap ≤ min live (cap - live) := by
  unfold cappedRawHeadroom50 proportionalTargetWords
  simp only [Nat.zero_max]
  omega

/-- The largest raw interval across all possible live sizes under this
envelope is at most half the cap. A 512-vertex batch charges more than
that even before accounting for captured views, stacks or probes. This
does not rule out carrying a larger mapped target in the history ring. -/
theorem still_padding_raw_limit (live : Nat) :
    8 * cappedRawHeadroom50 live (2 * 1024 ^ 3 / 8) < budgetedPayload 512 := by
  have bound := capped_raw_headroom50_bound live (2 * 1024 ^ 3 / 8)
  have payload : budgetedPayload 512 = 1207959552 := by decide
  rw [payload]
  omega

/-- Dropping one root family can reclaim only objects outside the reach of
all surviving roots. Retained objects can overlap across root families. -/
theorem dropping_root_reclaims_only_exclusive {Obj : Type}
    (removed surviving : Obj → Prop) (object : Obj) :
    ((removed object ∨ surviving object) ∧ ¬ surviving object) ↔
      removed object ∧ ¬ surviving object := by
  constructor
  · rintro ⟨reached, absent⟩
    exact ⟨reached.resolve_right absent, absent⟩
  · rintro ⟨reached, absent⟩
    exact ⟨Or.inl reached, absent⟩

open RuleGraphClosure (Reachable) in
/-- The exact boundary of a young-only collection consists of young
roots and young targets of edges from reachable older objects. Traversal
stays in the young subgraph. Real remembered sets may conservatively
include edges from unreachable old objects, retaining additional cells.
This statement does not model a Gambit write barrier or relocation. -/
theorem young_reach_from_boundary {Obj : Type} (edge : Obj → Obj → Prop)
    (roots young : Obj → Prop) (object : Obj) :
    (young object ∧ Reachable edge roots object) ↔
      Reachable (fun source target => young target ∧ edge source target)
        (fun target => young target ∧ (roots target ∨
          ∃ source, ¬ young source ∧ Reachable edge roots source ∧ edge source target))
        object := by
  constructor
  · rintro ⟨isYoung, reached⟩
    induction reached with
    | seed root => exact .seed ⟨isYoung, Or.inl root⟩
    | @follow source target sourceReached step ih =>
      by_cases sourceYoung : young source
      · exact .follow (ih sourceYoung) ⟨isYoung, step⟩
      · exact .seed ⟨isYoung, Or.inr ⟨source, sourceYoung, sourceReached, step⟩⟩
  · intro reached
    induction reached with
    | seed boundary =>
      obtain ⟨isYoung, root | ⟨source, _, sourceReached, step⟩⟩ := boundary
      · exact ⟨isYoung, .seed root⟩
      · exact ⟨isYoung, .follow sourceReached step⟩
    | follow _ step ih => exact ⟨step.1, .follow ih.2 step.2⟩

open RuleGraphClosure (Reachable) in
/-- Conservatively remembering extra targets can retain extra objects,
but including the exact boundary prevents reclamation of reachable
young objects. `remembered` must cover edges introduced by both Scheme
pair mutation and promotion in a native implementation. -/
theorem remembered_boundary_preserves_young {Obj : Type}
    (edge : Obj → Obj → Prop) (roots young remembered : Obj → Prop)
    (records : ∀ source target, ¬ young source → young target →
      Reachable edge roots source → edge source target → remembered target)
    (object : Obj) (isYoung : young object) (live : Reachable edge roots object) :
    Reachable (fun source target => young target ∧ edge source target)
      (fun target => young target ∧ (roots target ∨ remembered target)) object := by
  have exactBoundary := (young_reach_from_boundary edge roots young object).mp ⟨isYoung, live⟩
  clear isYoung live
  induction exactBoundary with
  | seed boundary =>
    obtain ⟨targetYoung, root | ⟨source, sourceOld, sourceReached, step⟩⟩ := boundary
    · exact .seed ⟨targetYoung, Or.inl root⟩
    · exact .seed ⟨targetYoung, Or.inr (records source _ sourceOld targetYoung sourceReached step)⟩
  | follow _ step ih => exact .follow ih step

namespace RememberedPairEdges

/-- Keep the two mutable pair fields distinct when recording a changed
edge. The remembered predicate may retain old entries until a rescan. -/
inductive Field where
  | car | cdr
  deriving DecidableEq

variable {Obj : Type}

def store [DecidableEq Obj] (slots : Obj → Field → Option Obj) (owner : Obj) (field : Field)
    (value : Option Obj) (source : Obj) (slot : Field) : Option Obj :=
  if source = owner ∧ slot = field then value else slots source slot

def Covers (young remembered : Obj → Prop) (slots : Obj → Field → Option Obj) : Prop :=
  ∀ source field target, ¬ young source → young target →
    slots source field = some target → remembered target

/-- The old-to-young boundary survives a pair write when the installed
target is recorded. A write of a scalar has no new target. -/
theorem store_covers [DecidableEq Obj]
    (young remembered next : Obj → Prop) (slots : Obj → Field → Option Obj)
    (owner : Obj) (field : Field) (value : Option Obj)
    (before : Covers young remembered slots)
    (retains : ∀ target, remembered target → next target)
    (records : ∀ target, ¬ young owner → young target → value = some target → next target) :
    Covers young next (store slots owner field value) := by
  intro source slot target sourceOld targetYoung points
  by_cases written : source = owner ∧ slot = field
  · obtain ⟨rfl, rfl⟩ := written
    simp [store] at points
    exact records target sourceOld targetYoung points
  · simp [store, written] at points
    exact retains target (before source slot target sourceOld targetYoung points)

/-- Promotion changes the boundary even without a pair write. Every
outgoing reference from a newly old object into the remaining young
region must be covered. -/
theorem promotion_covers (young remaining remembered next : Obj → Prop)
    (slots : Obj → Field → Option Obj) (before : Covers young remembered slots)
    (subset : ∀ target, remaining target → young target)
    (retains : ∀ target, remembered target → next target)
    (records : ∀ source field target, young source → ¬ remaining source → remaining target →
      slots source field = some target → next target) :
    Covers remaining next slots := by
  intro source field target sourceOld targetYoung points
  by_cases wasYoung : young source
  · exact records source field target wasYoung sourceOld targetYoung points
  · exact retains target (before source field target wasYoung (subset target targetYoung) points)

open RuleGraphClosure (Reachable) in
/-- Combine the conservative boundary with the existing young-reach
theorem for the graph made up of the two fields. Other object slots and
runtime roots require their corresponding source rules. -/
theorem covered_pair_reach (young remembered roots : Obj → Prop)
    (slots : Obj → Field → Option Obj) (covered : Covers young remembered slots)
    (target : Obj) (targetYoung : young target)
    (live : Reachable (fun source dest => ∃ field, slots source field = some dest) roots target) :
    Reachable (fun source dest => young dest ∧ ∃ field, slots source field = some dest)
      (fun dest => young dest ∧ (roots dest ∨ remembered dest)) target := by
  apply remembered_boundary_preserves_young _ roots young remembered ?_ target targetYoung live
  rintro source dest sourceOld destYoung _ ⟨field, points⟩
  exact covered source field dest sourceOld destYoung points

/-- A remembered slot belongs to an owner and identifies a concrete
field. Loading its value at collection time also handles overwrites. -/
def SlotCoverage (young : Obj → Prop) (recorded : Obj → Field → Prop)
    (slots : Obj → Field → Option Obj) : Prop :=
  ∀ source field target, ¬ young source → young target →
    slots source field = some target → recorded source field

/-- Scanning only the recorded slots of old owners discovers all
required young targets. A recorded slot observes its current value,
including when a later store replaced the previous target. -/
theorem scan_recorded_slots_covers
    (young : Obj → Prop) (recorded : Obj → Field → Prop)
    (slots : Obj → Field → Option Obj) (covered : SlotCoverage young recorded slots) :
    Covers young
      (fun target => ∃ source field, ¬ young source ∧ recorded source field ∧
        slots source field = some target) slots := by
  intro source field target old isYoung points
  exact ⟨source, field, old, covered source field target old isYoung points, points⟩

/-- Rewrite the actual incoming slot after movement. Every slot that
referred to a given value now refers to that same forwarded value. -/
theorem forwarded_slot_exact
    (young : Obj → Prop) (recorded : Obj → Field → Prop)
    [∀ source field, Decidable (recorded source field)]
    (slots : Obj → Field → Option Obj) (covered : SlotCoverage young recorded slots)
    (forward : Obj → Obj) (source target : Obj) (field : Field)
    (old : ¬ young source) (isYoung : young target)
    (points : slots source field = some target) :
    (if recorded source field then
      (slots source field).map forward else slots source field) = some (forward target) := by
  simp [covered source field target old isYoung points, points]

/-- Two aliases can discover the same young target. Visiting one of
their slots is enough for reachability, but the other alias still
points to the old address after the target is forwarded. -/
theorem target_only_misses_second_alias :
    let slots := fun (_ : Nat) (_ : Field) => some 1
    let rewritten := store slots 0 .car (some 2)
    rewritten 0 .car = some 2 ∧ rewritten 0 .cdr = some 1 := by decide

end RememberedPairEdges

/-- The frozen Gambit GC hash table has five metadata words and
two words per bucket. Cleanup's descending scan visits every bucket
when values are weak or when keys are both weak and heap-allocated. -/
def weakTableCleanupVisits (words : Nat) (weakKeys allocatedKeys weakValues : Bool) : Nat :=
  if weakValues || (weakKeys && allocatedKeys) then (words - 5) / 2 else 0

theorem weak_table_cleanup_visits_capacity (buckets : Nat)
    (weakKeys allocatedKeys weakValues : Bool)
    (scans : (weakValues || (weakKeys && allocatedKeys)) = true) :
    weakTableCleanupVisits (5 + 2 * buckets) weakKeys allocatedKeys weakValues = buckets := by
  simp only [weakTableCleanupVisits, scans, ite_true]
  omega

/-- Linking each reached table and traversing its weak buckets are
separate operations. Tables with strong keys and values contribute
one cleanup table entry even when no bucket loop runs. -/
theorem weak_table_cleanup_visit_bound (tables : List (Nat × Bool × Bool × Bool)) :
    (tables.map (fun (words, weakKeys, allocatedKeys, weakValues) =>
      weakTableCleanupVisits words weakKeys allocatedKeys weakValues)).sum ≤
      (tables.map (fun entry => (entry.1 - 5) / 2)).sum := by
  induction tables with
  | nil => simp
  | cons table rest ih =>
    obtain ⟨words, weakKeys, allocatedKeys, weakValues⟩ := table
    simp only [List.map_cons, List.sum_cons]
    exact Nat.add_le_add (by unfold weakTableCleanupVisits; split <;> omega) ih

/-- The first branch of mark_array leaves a scalar word unchanged.
Skipping that invocation preserves the slot updates, including their
order. The native candidate still reads and classifies every slot. -/
theorem skip_immediate_mark_calls {Word : Type} (allocated : Word → Bool)
    (mark : Word → Word) (scalar : ∀ word, allocated word = false → mark word = word)
    (words : List Word) :
    (words.map fun word => if allocated word then mark word else word) = words.map mark := by
  apply List.map_congr_left
  intro word _
  cases kind : allocated word
  · simpa using (scalar word kind).symm
  · simp

/-- Across a fixed collection, the guard removes exactly one marking
call per immediate field. Table reads and the work inside the
remaining calls are still charged. -/
theorem immediate_guard_call_count {Word : Type} (allocated : Word → Bool)
    (words : List Word) :
    words.countP allocated + words.countP (fun word => !(allocated word)) = words.length := by
  induction words with
  | nil => rfl
  | cons word rest ih =>
    cases kind : allocated word <;> simp [kind] <;> omega

/-- A movable pair whose first field is immediate can return to the next
pending root without reentering tail marking. The second field stays in
the scan queue in either case. The eager first-field pass is an identity
for this field class and creates no new forwarding entry. -/
theorem copied_pair_skips_scalar_cdr {Word State : Type} (allocated : Word → Bool)
    (visit : Word → State → Word × State)
    (immediate : ∀ word state, allocated word = false → visit word state = (word, state))
    (first second : Word) (state : State) :
    (if allocated first then
      let (updated, next) := visit first state
      (updated, second, next)
    else (first, second, state)) =
      (let (updated, next) := visit first state
       (updated, second, next)) := by
  cases kind : allocated first
  · simp [immediate first state kind]
  · simp

/-- The collector stores one header and two fields and then resumes marking
at the first field's destination. A fast copy is admitted only when neither
the destination section nor its scan chunk requires boundary handling. -/
theorem pair_copy_inside_chunk (header first second : Word)
    (dest sectionEnd chunkEnd : Nat)
    (sectionFits : dest + 3 ≤ sectionEnd) (chunkFits : dest + 3 < chunkEnd) :
    (header :: [first, second]) = [header, first, second] ∧
      dest + (header :: [first, second]).length = dest + 3 ∧
      dest + 2 < sectionEnd ∧ dest + 2 < chunkEnd ∧
      dest + 1 < dest + 3 := by
  simp only [List.length_cons, List.length_nil, true_and]
  omega

/-- The installed 64-bit Gambit header packs a three-bit header tag,
five-bit subtype, and byte size above them. The exact pair header
implies every decoded field tested by the previous copy guard.
Noncanonical encodings fall back to the generic collector. -/
theorem exact_movable_pair_header_sound (header : Nat)
    (exactPair : header = 16 * 256 + 1 * 8 + 0) :
    header % 8 = 0 ∧ header / 8 % 32 = 1 ∧ (header / 256 + 7) / 8 = 2 := by
  subst header
  decide

/-- A rounded word-count test has the converse for byte-aligned pair
headers. Byte sizes that round to two words need not be pair layouts. -/
theorem exact_movable_pair_header_of_aligned_fields (header : Nat)
    (movable : header % 8 = 0) (pair : header / 8 % 32 = 1)
    (words : (header / 256 + 7) / 8 = 2) (aligned : header / 256 % 8 = 0) :
    header = 16 * 256 + 1 * 8 + 0 := by
  omega

open RuleGraphClosure (Reachable) in
/-- Will executability is decided from strong roots. Once a will can
run, its testator supplies a new seed, including any young descendants
reachable through an older testator. This is the separate closure
required before reclaiming the region or delivering the callback. -/
theorem executable_will_descendant_survives {Obj : Type}
    (edge : Obj → Obj → Prop) (roots executable : Obj → Prop)
    (testator target : Obj) (will : executable testator)
    (path : Reachable edge (fun obj => obj = testator) target) :
    Reachable edge (fun obj => roots obj ∨ executable obj) target := by
  induction path with
  | seed root => exact .seed (Or.inr (root ▸ will))
  | follow _ step ih => exact .follow ih step

open RuleGraphClosure (Reachable) in
/-- Strong reachability alone can reclaim a pair that an executable
will on an older object must still deliver to Scheme. -/
theorem strong_edges_alone_miss_will_descendant :
    let edge := fun source target : Nat => source = 0 ∧ target = 1
    let roots : Nat → Prop := fun _ => False
    let executable := fun obj : Nat => obj = 0
    ¬ Reachable edge roots 1 ∧ Reachable edge (fun obj => roots obj ∨ executable obj) 1 := by
  dsimp only
  constructor
  · intro reached
    have noRoot (key : Nat)
        (path : Reachable (fun source target => source = 0 ∧ target = 1)
          (fun _ => False) key) : False := by
      induction path with
      | seed root => exact root
      | follow _ _ impossible => exact impossible
    exact noRoot 1 reached
  · exact .follow (.seed (Or.inr rfl)) ⟨rfl, rfl⟩

/-- Count the young collections that occur while an export has a live
prefix. The input trace assigns a monotonically increasing call number
to each collection inside the measured loop. -/
def exportSurvivals (call : Nat) (collectingCalls : List Nat) : Nat :=
  collectingCalls.count call

/-- With detached results and no retained output, a pair can survive
only collections in its own call. Requiring two survivals excludes
promotion when that call encounters at most one collection. -/
theorem two_survivals_exclude_transient_promotion (call : Nat) (collectingCalls : List Nat)
    (pairSurvivals : Nat) (bounded : pairSurvivals ≤ exportSurvivals call collectingCalls)
    (oneCollection : exportSurvivals call collectingCalls ≤ 1) :
    pairSurvivals < 2 := by omega

theorem distinct_collecting_calls_count_at_most_one (calls : List Nat)
    (distinct : calls.Nodup) (call : Nat) : exportSurvivals call calls ≤ 1 := by
  induction calls with
  | nil => simp [exportSurvivals]
  | cons head rest ih =>
    obtain ⟨absent, tailDistinct⟩ := List.nodup_cons.mp distinct
    by_cases same : head = call
    · subst head
      have zero : rest.count call = 0 := List.count_eq_zero.mpr absent
      simp [exportSurvivals, zero]
    · have bounded := ih tailDistinct
      simpa [exportSurvivals, List.count_cons, same] using bounded

/-- To guarantee that a complete export crosses at most one local
collection from any entry position, the renewal must accommodate its
whole allocation charge after copying the live prefix. `overhead`
bounds other allocations through the end of the call. -/
theorem one_collection_covers_remaining_export (payload before copied overhead capacity : Nat)
    (prefixBound : before ≤ payload) (copiedBound : copied ≤ before)
    (enough : payload + overhead ≤ capacity) :
    payload - before + overhead ≤ capacity - copied := by
  omega

/-- The modeled allocation region starts a call with a charged cursor.
At a crossing only the active call's prefix survives. The returned
pair is the new cursor and the optional copied charge. The caller must
establish `charge ≤ capacity` and release all prior output. -/
def releasedExportStep (capacity used charge : Nat) : Nat × Option Nat :=
  if used + charge ≤ capacity then (used + charge, none)
  else (charge, some (capacity - used))

theorem released_export_step_bounded (capacity used charge : Nat)
    (cursor : used ≤ capacity) (fits : charge ≤ capacity) :
    (releasedExportStep capacity used charge).1 ≤ capacity ∧
      ∀ copied, (releasedExportStep capacity used charge).2 = some copied → copied < charge := by
  unfold releasedExportStep
  split
  · simp_all
  · rename_i crosses
    refine ⟨fits, ?_⟩
    intro copied same
    simp at same
    omega

/-- A crossing first allocates the copied prefix at the new cursor.
Finishing the same call accounts for exactly the complete output charge. -/
theorem released_export_crossing_conserves_charge (capacity used charge : Nat)
    (cursor : used ≤ capacity) (crosses : capacity < used + charge) :
    let copied := capacity - used
    releasedExportStep capacity used charge = (copied + (charge - copied), some copied) := by
  have notFit : ¬ used + charge ≤ capacity := by omega
  have splitCharge : capacity - used + (charge - (capacity - used)) = charge := by omega
  simp [releasedExportStep, notFit, splitCharge]

/-- Accumulate collection count and copied charge across one fixed batch.
Carry the ending cursor forward to the next batch without a free reset. -/
def releasedExportBatch (capacity used : Nat) (charges : List Nat) : Nat × Nat × Nat :=
  charges.foldl (fun (cursor, collections, totalCopied) charge =>
    match releasedExportStep capacity cursor charge with
    | (next, none) => (next, collections, totalCopied)
    | (next, some copied) => (next, collections + 1, totalCopied + copied)) (used, 0, 0)

/-- A fixed-size output class can fill a region with whole calls. After
`count` exports a cursor aligned to `charge` has no partial call to copy.
The next call renews the region before constructing its output. -/
theorem aligned_region_renews_without_copy (count charge : Nat) (nonempty : 0 < charge) :
    releasedExportStep (count * charge) (count * charge) charge = (charge, some 0) := by
  have exhausted : ¬ count * charge + charge ≤ count * charge := by omega
  simp [releasedExportStep, exhausted]

namespace PairCopy

/-- The append-only forwarding directory records each source identity once.
Its list position is the destination slot, independent of traversal order. -/
def forward (limit source : Nat) (directory : List Nat) : Option (Nat × List Nat) :=
  match directory.idxOf? source with
  | some slot => some (slot, directory)
  | none =>
      if directory.length < limit then some (directory.length, directory ++ [source])
      else none

theorem forward_preserves_directory (limit source : Nat) (directory : List Nat)
    (unique : directory.Nodup) (fits : directory.length ≤ limit)
    (slot : Nat) (next : List Nat)
    (copied : forward limit source directory = some (slot, next)) :
    next.Nodup ∧ next.length ≤ limit ∧ next[slot]? = some source ∧
      next.take directory.length = directory := by
  unfold forward at copied
  split at copied
  · rename_i found lookup
    cases copied
    refine ⟨unique, fits, ?_, by simp⟩
    obtain ⟨inside, exactSource, _⟩ := List.idxOf?_eq_some_iff.mp lookup
    simpa [List.getElem?_eq_getElem inside] using exactSource
  · rename_i absent
    split at copied
    · rename_i room
      cases copied
      have fresh : source ∉ directory := List.idxOf?_eq_none_iff.mp absent
      refine ⟨?_, by simpa using Nat.succ_le_of_lt room, ?_, by simp⟩
      · apply List.nodup_append.mpr
        refine ⟨unique, by simp, ?_⟩
        intro a present b singleton same
        have named : b = source := by simpa using singleton
        exact fresh ((same.trans named) ▸ present)
      · simp
    · simp at copied

theorem full_copy_rejects_new_identity (limit source : Nat) (directory : List Nat)
    (full : directory.length = limit) (fresh : source ∉ directory) :
    forward limit source directory = none := by
  simp [forward, List.idxOf?_eq_none_iff.mpr fresh, full]

/-- Each successful insertion records its bucket before following more
edges. Clearing the recorded buckets therefore resets a private empty
table after success or refusal. Probing and physical writes must refine
the occupied-bucket premise. -/
theorem clear_recorded_buckets {Bucket : Type} (occupied recorded : Bucket → Prop)
    (covers : ∀ bucket, occupied bucket → recorded bucket) (bucket : Bucket) :
    ¬ (occupied bucket ∧ ¬ recorded bucket) :=
  fun ⟨entry, retained⟩ => retained (covers bucket entry)

/-- An aligned pair header is identified by its page number and word offset.
The page table must additionally refuse aliases between distinct pages. -/
theorem aligned_pair_page_key_injective (a b : Nat)
    (alignedA : a % 8 = 0) (alignedB : b % 8 = 0)
    (page : a / 4096 = b / 4096)
    (word : a / 8 % 512 = b / 8 % 512) : a = b := by
  omega

/-- A 4 KiB address block has 512 aligned words. Eight 64-bit
bitmap words identify all of them without aliasing. -/
theorem pair_bitmap_key_injective (a b : Nat)
    (alignedA : a % 8 = 0) (alignedB : b % 8 = 0)
    (page : a / 4096 = b / 4096)
    (bitmapWord : (a / 8 % 512) / 64 = (b / 8 % 512) / 64)
    (bitmapBit : a / 8 % 64 = b / 8 % 64) : a = b := by
  apply aligned_pair_page_key_injective a b alignedA alignedB page
  omega

/-- Zero denotes an untouched offset. Every destination within the C
entry's signed 32-bit capacity has a nonzero, reversible marker. -/
theorem page_marker_fits (slot limit : Nat) (allocated : slot < limit)
    (bounded : limit < 2 ^ 31) :
    0 < 2 * slot + 1 ∧ 2 * slot + 1 < 2 ^ 32 ∧ (2 * slot + 1) / 2 = slot := by
  omega

/-- In an admitted row the terminal and tuple headers are at fixed
offsets from the spine header. Identity at either role implies
identity of the spine header at the same role in the other row. -/
theorem same_triple_role_implies_same_spine (a b field : Nat)
    (same : a + 24 * field = b + 24 * field) : a = b := by omega

/-- On one concrete pair, an allocated car denotes the outer role,
a scalar car with a pair cdr denotes the tuple role, and a scalar
car with an empty cdr denotes the terminal role. A pair cannot
have different roles in two accepted rows. -/
def tripleRole (carIsPair cdrIsPair : Bool) : Nat :=
  if carIsPair then 2 else if cdrIsPair then 1 else 0

theorem triple_roles_distinct (outer tuple terminal : Nat)
    (carIsPair cdrIsPair : Nat → Bool)
    (outerCar : carIsPair outer = true)
    (tupleCar : carIsPair tuple = false) (tupleCdr : cdrIsPair tuple = true)
    (terminalCar : carIsPair terminal = false) (terminalCdr : cdrIsPair terminal = false) :
    tripleRole (carIsPair outer) (cdrIsPair outer) = 2 ∧
      tripleRole (carIsPair tuple) (cdrIsPair tuple) = 1 ∧
      tripleRole (carIsPair terminal) (cdrIsPair terminal) = 0 := by
  simp [tripleRole, outerCar, tupleCar, tupleCdr, terminalCar, terminalCdr]

/-- The scalar receipt convention uses odd nonzero references into
the destination. Indexing rows by triples gives distinct cells for
all three roles without directory lookups. -/
theorem triple_destination_injective (row next field slot : Nat)
    (inside : field < 3) (otherInside : slot < 3)
    (same : 2 * (3 * row + field) + 1 = 2 * (3 * next + slot) + 1) :
    row = next ∧ field = slot := by
  omega

/-- A bitmap entry records visitation, not a forwarding address.
It suffices for private row encoding because a repeated source pair
is refused and a destination is computed from its row and role. -/
theorem bitmap_row_copy_keeps_distinct_destinations (source : Nat → Nat → Nat)
    (rows : Nat) (dst : Nat → Nat → Nat)
    (unique : ∀ row < rows, ∀ field < 3, ∀ next < rows, ∀ slot < 3,
      source row field = source next slot → row = next ∧ field = slot)
    (address : ∀ row < rows, ∀ field < 3, dst row field = 2 * (3 * row + field) + 1)
    {row field next slot : Nat}
    (current : row < rows) (inside : field < 3)
    (other : next < rows) (otherInside : slot < 3) :
    source row field = source next slot ↔ dst row field = dst next slot := by
  constructor
  · intro same
    obtain ⟨rfl, rfl⟩ := unique row current field inside next other slot otherInside same
    rfl
  · intro same
    rw [address row current field inside, address next other slot otherInside] at same
    obtain ⟨rfl, rfl⟩ := triple_destination_injective row next field slot inside otherInside same
    rfl

end PairCopy

/-- A block can be reclaimed only after its last surviving pair moves
or dies. The charge uses logical blocks; it excludes allocator metadata. -/
def retainedBlockBytes (blockBytes : Nat) (survivorsByBlock : List Nat) : Nat :=
  blockBytes * survivorsByBlock.countP (fun live => 0 < live)

/-- A single retained pair can pin each of arbitrarily many blocks.
The public list contract permits a caller to keep and detach these pairs. -/
theorem one_survivor_per_block_charge (blockBytes blocks : Nat) :
    retainedBlockBytes blockBytes (List.replicate blocks 1) = blockBytes * blocks := by
  have count : (List.replicate blocks 1).countP (fun live => 0 < live) = blocks := by
    induction blocks with
    | zero => rfl
    | succ blocks ih => simp [List.replicate_succ, ih]
  simp [retainedBlockBytes, count]

/-- A region containing retained pairs cannot provide enough reusable
space unless the unpinned budget covers the next allocation. -/
theorem pinned_blocks_refuse_next_export
    (capacity blockBytes : Nat) (survivorsByBlock : List Nat) (width : Nat)
    (fits : retainedBlockBytes blockBytes survivorsByBlock ≤ capacity)
    (pressure : capacity < retainedBlockBytes blockBytes survivorsByBlock +
      freshRowBytes (width * width)) :
    capacity - retainedBlockBytes blockBytes survivorsByBlock < freshRowBytes (width * width) := by
  omega

/-- Replaying the 512-vertex occupancy with disjoint blocks, whole-block
retention alone exceeds 2 GiB while compact storage of the surviving
pairs stays below 13 MiB. Both sides count payload without metadata. -/
theorem sparse_512_retention_exceeds_cap :
    2 * 1024 ^ 3 < 114 * 4609 * 4096 ∧
      114 * 4609 * 24 < 13 * 1024 ^ 2 := by decide


open RuleGraphClosure (Reachable) in
/-- Publication allows callers to retain a root at any visible cell.
The outer list head can die while a tuple or its terminal cell remains
reachable. The edge into the interior is enough to forbid reuse. -/
theorem unreachable_export_head_does_not_certify_interior :
    let edge := fun source target : Nat => (source = 0 ∧ target = 1) ∨
      (source = 1 ∧ target = 2) ∨ (source = 3 ∧ target = 2)
    let roots := fun cell : Nat => cell = 3
    ¬ Reachable edge roots 0 ∧ Reachable edge roots 2 := by
  dsimp only
  constructor
  · intro head
    cases head with
    | seed root => omega
    | follow _ incoming => omega
  · exact Reachable.follow (source := 3) (.seed rfl) (Or.inr (Or.inr ⟨rfl, rfl⟩))

open RuleGraphClosure (Reachable) in
/-- A death notification can authorize reuse of a distinct published
cell only if every legal caller graph in which that cell is reachable
also keeps a watched cell reachable. Retaining just that cell and
replacing its outgoing pair fields with scalars is a legal caller
graph. Thus a protocol using only the absence of watched live cells
cannot authorize reuse of any unwatched cell. -/
theorem mutable_pair_reuse_requires_watch
    {Cell : Type} (edge : Cell → Cell → Prop) (watched : Cell → Prop)
    (retained : Cell)
    (certifies : (∀ cell, watched cell →
        ¬ Reachable (fun source target => edge source target ∧ source ≠ retained)
          (fun cell => cell = retained) cell) →
      ¬ Reachable (fun source target => edge source target ∧ source ≠ retained)
        (fun cell => cell = retained) retained) :
    watched retained := by
  classical
  apply Classical.byContradiction
  intro unwatched
  have onlyRetained {cell : Cell} (live :
      Reachable (fun source target => edge source target ∧ source ≠ retained)
        (fun cell => cell = retained) cell) : cell = retained := by
    induction live with
    | seed root => exact root
    | follow _ step ih => exact (step.2 ih).elim
  apply certifies _ (Reachable.seed rfl)
  intro cell observed live
  exact unwatched (onlyRetained live ▸ observed)

/-- The prelinked tool can retain fewer startup roots and still start with
less raw free space. In the observed Gambit run, its live-size projection lands
below the native minimum, whereas the dispatcher lands above it. These
are target words before reserve, history and section alignment. -/
theorem test_startup_targets :
    let minimum := 64 * 1048576 / 8
    let dispatcher := 86213560 / 8
    let prelinked := 27803024 / 8
    prelinked < dispatcher ∧
    proportionalTargetWords prelinked minimum 50 = minimum ∧
    proportionalTargetWords dispatcher minimum 50 > minimum ∧
    proportionalTargetWords prelinked minimum 50 - prelinked <
      proportionalTargetWords dispatcher minimum 50 - dispatcher := by
  decide

/-- The pinned Gambit collector retains the maximum of the last sixteen successful
resize targets. The current target enters this window after resizing;
it does not enter on heap overflow. This model is before section rounding. -/
def heapHistoryMax : List Nat → Nat
  | [] => 0
  | target :: rest => max target (heapHistoryMax rest)

def recentHeapTarget (current : Nat) (newestFirst : List Nat) : Nat :=
  max current (heapHistoryMax (newestFirst.take 16))

theorem heapHistoryMax_replicate (target count : Nat) :
    heapHistoryMax (List.replicate (count + 1) target) = target := by
  induction count with
  | zero => simp [heapHistoryMax]
  | succ count ih =>
    change max target (heapHistoryMax (List.replicate (count + 1) target)) = target
    rw [ih]
    omega

theorem expired_heap_target (low high : Nat) :
    recentHeapTarget low (List.replicate 16 low ++ [high]) = low := by
  have window : (List.replicate 16 low ++ [high]).take 16 =
      List.replicate 16 low := by simp
  rw [recentHeapTarget, window, heapHistoryMax_replicate low 15]
  omega

theorem retained_heap_target (low high : Nat) (ordered : low ≤ high) :
    recentHeapTarget low (high :: List.replicate 15 low) = high := by
  have window : (high :: List.replicate 15 low).take 16 =
      high :: List.replicate 15 low := by simp
  rw [recentHeapTarget, window, heapHistoryMax, heapHistoryMax_replicate low 14]
  omega

/-- Restoring the setup minimum after a successful resize does not restore
the effective target. A recorded larger target is still consulted after
any number of newer successful resizes below the history window length.
The history is newest first, as an abstract view of the native ring. -/
theorem restored_minimum_retains_resize_target
    (current large : Nat) (newer older : List Nat) (within : newer.length < 16) :
    large ≤ recentHeapTarget current (newer ++ large :: older) := by
  have lower (history : List Nat) (target : Nat) (inside : target ∈ history) :
      target ≤ heapHistoryMax history := by
    induction history with
    | nil => simp at inside
    | cons first rest ih =>
      simp only [List.mem_cons] at inside
      rcases inside with rfl | member
      · exact Nat.le_max_left _ _
      · exact Nat.le_trans (ih member) (Nat.le_max_right _ _)
  have present : large ∈ (newer ++ large :: older).take 16 := by
    rw [List.take_append]
    have positive : 0 < 16 - newer.length := by omega
    have split : 16 - newer.length = (16 - newer.length - 1) + 1 := by omega
    rw [split]
    simp
  exact Nat.le_trans (lower _ _ present) (Nat.le_max_right _ _)

/-- Source equation for the successful resize branch. The target includes
the normal overflow reserve, and history can raise it before still
occupancy is subtracted. Both section clamps apply with a nonzero cap. -/
def resizeMappedSections (current history movable still stack processorMin cap : Nat) : Nat :=
  let roundSections (bytes : Nat) := (bytes + sectionPayloadBytes - 1) / sectionPayloadBytes
  let target := roundSections (max current history - still) + stack
  let lower := max processorMin (roundSections movable + stack)
  min (max target lower) ((cap - still) / 1048576)

theorem resize_mapped_sections_within_cap
    (current history movable still stack processorMin cap : Nat) (fits : still ≤ cap) :
    resizeMappedSections current history movable still stack processorMin cap * 1048576 + still ≤ cap := by
  have count : resizeMappedSections current history movable still stack processorMin cap ≤
      (cap - still) / 1048576 := by
    unfold resizeMappedSections
    exact Nat.min_le_right _ _
  omega

/-- A previous target can keep a successful resize at the mapped cap
after the caller drops completed lists. The condition checks the current
still charge and stack count because these can change after release. -/
theorem retained_history_saturates_mapped_sections
    (current history movable still stack processorMin cap : Nat)
    (saturated : (cap - still) / 1048576 ≤
      (history - still + sectionPayloadBytes - 1) / sectionPayloadBytes + stack) :
    resizeMappedSections current history movable still stack processorMin cap =
      (cap - still) / 1048576 := by
  unfold resizeMappedSections
  apply Nat.min_eq_right
  have more : history - still ≤ max current history - still :=
    Nat.sub_le_sub_right (Nat.le_max_right current history) still
  have rounded : (history - still + sectionPayloadBytes - 1) / sectionPayloadBytes ≤
      (max current history - still + sectionPayloadBytes - 1) / sectionPayloadBytes :=
    Nat.div_le_div_right (Nat.sub_le_sub_right
      (Nat.add_le_add_right more sectionPayloadBytes) 1)
  exact Nat.le_trans saturated
    (Nat.le_trans (Nat.add_le_add_right rounded stack) (Nat.le_max_left _ _))

theorem discarded_history_cannot_raise_resize
    (current history movable still stack processorMin cap : Nat) :
    resizeMappedSections current 0 movable still stack processorMin cap ≤
      resizeMappedSections current history movable still stack processorMin cap := by
  unfold resizeMappedSections
  simp only [Nat.max_zero]
  have larger : current ≤ max current history := Nat.le_max_left _ _
  have shifted := Nat.sub_le_sub_right larger still
  have padded := Nat.add_le_add_right shifted sectionPayloadBytes
  have rounded : (current - still + sectionPayloadBytes - 1) / sectionPayloadBytes ≤
      (max current history - still + sectionPayloadBytes - 1) / sectionPayloadBytes :=
    Nat.div_le_div_right (Nat.sub_le_sub_right padded 1)
  have targets := Nat.add_le_add_right rounded stack
  exact Nat.le_min.mpr ⟨
    Nat.le_trans (Nat.min_le_left _ _)
      (Nat.max_le.mpr ⟨Nat.le_trans targets (Nat.le_max_left _ _), Nat.le_max_right _ _⟩),
    Nat.min_le_right _ _⟩

/-- Replay the retained and released 512-vertex observations from the
native still-vector study. These are successive cases of the same
resize branch, with one stack section and an inactive lower bound.
After release, the high target survives one more resize while the
still occupancy is deducted at its new, much smaller value. -/
theorem still_vector_resize_replay :
    let cap := 2 * 1024 ^ 3
    let reserve := 1638464
    let retained := 541613944
    let released := 4742984
    let high := 8 * proportionalTargetWords (626442824 / 8) 0 50
    let low := 8 * proportionalTargetWords (89572152 / 8) 0 50
    let retainedSections := minimumTargetSections high retained reserve cap
    let releasedSections := minimumTargetSections (max low high) released reserve cap
    retainedSections * 1048576 + retained = 1358454648 ∧
      releasedSections * 1048576 + released = 1435000648 ∧
      releasedSections - retainedSections = 585 := by
  decide

/-- A group with one owner and no quotient edge captures one self product.
Reading its immutable members directly preserves the ordered rectangle plan,
logical row count and the member-plus-descriptor unit count. -/
theorem closed_owner_capture_exact
    (family : ProviderRectangles.Components α C) (owner : C) :
    let members := family.members owner
    let plan := ProviderRectangles.componentPlan family [(owner, owner)]
    plan = [⟨members, members⟩] ∧
      ProviderRectangles.count plan = members.length * members.length ∧
      members.length + plan.length = members.length + 1 := by
  simp [ProviderRectangles.componentPlan, ProviderRectangles.count]

/-- At ten percent the integer division rounds down before multiplying.
Thus the target is within 90 words of ten times live, absent the floor. -/
theorem ten_percent_rounding (live : Nat) :
    10 * live - 90 ≤ proportionalTargetWords live 0 10 ∧
    proportionalTargetWords live 0 10 ≤ 10 * live := by
  have split := Nat.mod_add_div live 10
  have rem := Nat.mod_lt live (by decide : 0 < 10)
  unfold proportionalTargetWords
  simp only [Nat.zero_max]
  omega

/-- At this observed live budget, seven percent leaves room in the
target for the 512-vertex pair payload and additional runtime costs.
These are target bytes before the collector's clamp and rounding. -/
theorem seven_percent_observed_target :
    proportionalTargetWords (108553768 / 8) 0 7 * 8 = 1550768000 ∧
    1550768000 - 108553768 - budgetedPayload 512 = 234254680 := by
  decide

/-- At this live observation, eight percent leaves positive target headroom
for the pair payload, whereas nine percent cannot fit it in the target.
Neither statement includes reserve, rounding, or non-pair allocations. -/
theorem adjacent_targets_observed :
    proportionalTargetWords (108553768 / 8) 0 8 * 8 =
      108553768 + budgetedPayload 512 + 40408280 ∧
    proportionalTargetWords (108553768 / 8) 0 9 * 8 + 110360520 =
      108553768 + budgetedPayload 512 := by
  decide

/-- An additive ledger for one observed interval. If all work outside its
collection intervals keeps the same wall cost, replacing the collector cost
alone cannot bring that interval below its outside-collector cost. Scheduling
and heap changes can change both terms in an actual subsequent run. -/
theorem fixed_outside_cost_rejects_strict_gate
    (wall collection replacement limit : Nat)
    (outsideExceeds : limit ≤ wall - collection) :
    ¬ (wall - collection + replacement < limit) := by
  omega

/-- The dual ledger obligation: optimizing the joins, capture, list loops or
validation alone cannot admit an interval whose retained collector wall cost
already reaches the whole limit. This is conditional on preserving that cost;
it does not claim GC duration is invariant under an algorithm or heap change. -/
theorem fixed_collector_cost_rejects_strict_gate
    (collection replacementOutside limit : Nat)
    (collectionExceeds : limit ≤ collection) :
    ¬ (collection + replacementOutside < limit) := by
  omega

/-- With GC costs held fixed, any sample whose collector alone reaches
the limit fails after an arbitrary nonnegative change to outside work.
This counts independently observed intervals without subtracting
percentiles or using CPU as wall time. -/
theorem unchanged_gc_exceedances_persist
    (observations : List (Nat × Nat)) (limit : Nat) :
    (observations.filter (fun sample => decide (limit ≤ sample.1))).length ≤
      (observations.filter (fun sample => decide (limit ≤ sample.1 + sample.2))).length := by
  induction observations with
  | nil => simp
  | cons sample rest ih =>
    by_cases gc : limit ≤ sample.1
    · have total : limit ≤ sample.1 + sample.2 := by omega
      simpa [gc, total] using Nat.succ_le_succ ih
    · by_cases total : limit ≤ sample.1 + sample.2
      · simpa [gc, total] using Nat.le_succ_of_le ih
      · simpa [gc, total] using ih

/-- A candidate that preserves a lower bound on outside-collector work
must improve the sum of collection intervals, not just their count.
Use one unit and one clock for all three terms. -/
theorem collector_budget_from_outside_floor (outside floor collection limit : Nat)
    (lower : floor ≤ outside) (pass : outside + collection < limit) :
    collection < limit - floor := by
  omega

/-- For a synchronized CPU sample, retain a floor for the work outside GC
and compare the full GC CPU total. Using 512-vertex paired-lane floors
from the cold snapshot, more than 60.557 ms must be removed from GC CPU
to fit below 100 ms. Those observed floors are premises, not invariants
of a new VM policy or measurements of the independent wall lane. -/
theorem cold_large_collector_cpu_reduction
    (outside oldCollection newCollection : Nat)
    (outsideFloor : 31593 ≤ outside) (collectionFloor : 128964 ≤ oldCollection)
    (fits : outside + newCollection < 100000) :
    60557 < oldCollection - newCollection := by
  omega

/-- For the paired CPU lane only: the observed minimum outside-collector
CPU rounded down to whole microseconds. These are conditional budgets
for the next CPU diagnostic, not bounds on admission wall time. -/
theorem paired_cpu_collector_budgets (outside collection : Nat) :
    (19577 ≤ outside → outside + collection < 100000 → collection < 80423) ∧
    (33756 ≤ outside → outside + collection < 100000 → collection < 66244) := by
  constructor <;> intro lower pass
  · exact collector_budget_from_outside_floor outside 19577 collection 100000 lower pass
  · exact collector_budget_from_outside_floor outside 33756 collection 100000 lower pass

/-- Conservative microsecond bounds for the slowest aligned diagnostic
attempt. Wall is rounded down and the collection duration rounded up. -/
theorem measured_outside_cost_exceeds_gate :
    100000 ≤ 524068 - 220310 := by decide

/-- Exact no-GC counter difference under unchanged stack and still occupancy.
The frozen C counter charges both semispaces for movable allocations. -/
theorem heap_advance_snapshot_delta
    (adjusted heap stack processorStill vmStill allocated : Int) :
    counter adjusted (heap + allocated) stack processorStill vmStill -
      counter adjusted heap stack processorStill vmStill = 2 * allocated := by
  unfold counter movableBudget
  omega

/-- `_kernel.scm` field 16 is assigned from `latest_gc_alloc_`. No GC leaves
that watermark unchanged even when a positive movable allocation advances
field 7. Its difference cannot stand for interval allocation in that case. -/
theorem last_gc_watermark_misses_no_gc_allocation
    (adjusted heap stack processorStill vmStill allocated watermark : Int)
    (positive : 0 < allocated) :
    watermark - watermark = 0 ∧
    0 < counter adjusted (heap + allocated) stack processorStill vmStill -
      counter adjusted heap stack processorStill vmStill := by
  rw [heap_advance_snapshot_delta]
  omega


/-! The typed production bridge currently serializes every answer before it
classifies scalar support. Classification may inspect that private serialized
answer instead of calling the snapshot's complete materializer again. This
proof needs classification-preserving serialization; it is not a theorem
about arbitrary callbacks, query-label aliasing or native compiler extraction. -/
namespace SourceProjection

def projectRows (project : α → β) (rows : List (List α)) : List (List β) :=
  rows.map (List.map project)

def supports (scalar : α → Bool) (rows : List (List α)) : Bool :=
  rows.all (fun row => row.all scalar)

theorem projected_support_exact (project : α → β) (native : α → Bool)
    (wire : β → Bool) (faithful : ∀ value, wire (project value) = native value)
    (rows : List (List α)) :
    supports wire (projectRows project rows) = supports native rows := by
  simp [supports, projectRows, List.all_map, Function.comp_def, faithful]

inductive SourceKind where
  | internedSymbol | text | integer | boolean | opaque

inductive WireKind where
  | text | integer | boolean | reference

def nativeScalar : SourceKind → Bool
  | .opaque => false
  | _ => true

def serializeKind : SourceKind → WireKind
  | .internedSymbol | .text => .text
  | .integer => .integer
  | .boolean => .boolean
  | .opaque => .reference

def wireScalar : WireKind → Bool
  | .reference => false
  | _ => true

theorem serialization_preserves_classification (value : SourceKind) :
    wireScalar (serializeKind value) = nativeScalar value := by
  cases value <;> rfl

/-- All-scalar queries force both the answer materializer and the old status
materializer. Row projection is unchanged; its own charge is retained. -/
theorem supported_queries_save_one_export (queries exportCharge projectCharge : Nat) :
    queries * (exportCharge + projectCharge + exportCharge) =
      queries * (exportCharge + projectCharge) + queries * exportCharge := by
  simp only [Nat.mul_add]

/- Reuse is restricted to a detached private result whose values already have
the wire representation. This proves value equality, not producer freshness,
FFI refinement, collector time or the safety of borrowing mutable engine rows. -/
def reuseRows (owned : Bool) (stable : α → Bool) (project : α → α)
    (rows : List (List α)) :=
  if owned && supports stable rows then rows else projectRows project rows

theorem stable_row_identity (stable : α → Bool) (project : α → α)
    (fixed : ∀ value, stable value = true → project value = value)
    (row : List α) (admitted : row.all stable = true) : row.map project = row := by
  induction row with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.all_cons, Bool.and_eq_true] at admitted
    simp only [List.map_cons, fixed head admitted.1, ih admitted.2]

theorem stable_rows_identity (stable : α → Bool) (project : α → α)
    (fixed : ∀ value, stable value = true → project value = value)
    (rows : List (List α)) (admitted : supports stable rows = true) :
    projectRows project rows = rows := by
  induction rows with
  | nil => rfl
  | cons head tail ih =>
    simp only [supports, List.all_cons, Bool.and_eq_true] at admitted
    simp only [projectRows, List.map_cons]
    rw [stable_row_identity stable project fixed head admitted.1]
    exact congrArg (List.cons head) (ih admitted.2)

theorem reuse_rows_exact (stable : α → Bool) (project : α → α)
    (fixed : ∀ value, stable value = true → project value = value)
    (rows : List (List α)) (owned : Bool) :
    reuseRows owned stable project rows = projectRows project rows := by
  unfold reuseRows
  split
  next accepted =>
    have admitted : supports stable rows = true := by
      cases owned <;> simp_all
    exact (stable_rows_identity stable project fixed rows admitted).symm
  next => rfl

theorem foreign_rows_keep_projection (stable : α → Bool) (project : α → α)
    (rows : List (List α)) :
    reuseRows false stable project rows = projectRows project rows := by
  simp [reuseRows]

/-- Only the redundant serialization spines are removed. Producer allocation
and the output's ownership obligation are retained in both charges. -/
theorem stable_rows_copy_charge (producer rows columns : Nat) (nonempty : 0 < rows) :
    producer < producer + rows * (columns + 1) := by
  have positive := Nat.mul_pos nonempty (by omega : 0 < columns + 1)
  omega

def detachedWireSchemeSource : String :=
"(def (wire-preserved? value)\n  (or (string? value) (exact-integer? value) (boolean? value)))\n\n(def (ascent-serialize-detached-rows rows (owned? #f))\n  ;; rows-of has already detached the public spines from the session snapshot.\n  ;; Only this private answer owns them; do not cache caller objects or views.\n  ;; A foreign export callback can return a shared spine. Its caller must keep\n  ;; the ordinary copy even when every returned value is already scalar.\n  (if (and owned? (andmap (lambda (row) (andmap wire-preserved? row)) rows))\n    rows\n    (map (lambda (row)\n           (map (lambda (value)\n                  (cond ((interned-symbol? value) (symbol->string value))\n                        ((wire-preserved? value) value)\n                        (else (hash (\"encoding\" \"owned-result-reference\"))))) row))\n         rows)))\n"

end SourceProjection

/-! The ABI determines whether an admitted exact integer is a fixnum. No
word-width or tagged-object layout is duplicated in the consumer. Only the
explicit unsupported projection falls back; other native failures propagate.
These are codec/call-count statements, not a compiler/FFI refinement. -/
namespace ExactIntegerTransfer

inductive Probe (Fault : Type) where
  | word : Int → Probe Fault
  | unsupported : Probe Fault
  | failure : Fault → Probe Fault

def decode (probe : Probe Fault) (fallback : Unit → Except Fault Int) : Except Fault Int :=
  match probe with
  | .word value => .ok value
  | .unsupported => fallback ()
  | .failure error => .error error

/-- No magnitude buffer or fallback action is needed for an admitted word. -/
theorem word_exact (value : Int) (fallback : Unit → Except Fault Int) :
    decode (.word value) fallback = .ok value := rfl

theorem unsupported_exact (fallback : Unit → Except Fault Int) :
    decode .unsupported fallback = fallback () := rfl

theorem failures_propagate (error : Fault) (fallback : Unit → Except Fault Int) :
    decode (.failure error) fallback = .error error := rfl

/-- Given the native word observation is exact, both successful paths decode
identically to the reference magnitude codec. This premise is tested against
that native codec; its C/Scheme implementation is not proved here. -/
theorem successful_paths_agree (value : Int) (probe : Probe Fault)
    (fallback : Unit → Except Fault Int) (reference : fallback () = .ok value)
    (sound : ∀ observed, probe = .word observed → observed = value)
    (noFailure : ∀ error, probe ≠ .failure error) :
    decode probe fallback = .ok value := by
  cases probe with
  | word observed => simp only [decode, sound observed rfl]
  | unsupported => exact reference
  | failure error => exact False.elim (noFailure error rfl)

-- Include the unchanged kind query: old = kind + size + copy; new fixnum =
-- kind + scalar; new bignum = kind + rejected scalar + size + copy.
def oldCalls (words bigs : Nat) := 3 * (words + bigs)
def newCalls (words bigs : Nat) := 2 * words + 4 * bigs

theorem call_saving_exact (words bigs : Nat) :
    newCalls words bigs + words = oldCalls words bigs + bigs := by
  unfold oldCalls newCalls
  omega

theorem no_call_regression (words bigs : Nat) (majority : bigs ≤ words) :
    newCalls words bigs ≤ oldCalls words bigs := by
  unfold oldCalls newCalls
  omega

end ExactIntegerTransfer

/-! Proposed ASCENT-owned row transfer over GSR's existing signed numeric
vector API. This proves shape/order and a conditional native-call charge;
it does not prove the numeric ABI, Scheme compiler, GC timing or wall latency.
The ordinary codec remains authoritative for unsupported cell families. -/
namespace IntegerRowTransfer

/-- The binary frozen-rectangle order, reused from the provider specification.
No intermediate list is required by a native buffer writer implementing this
sequence. This sequence model alone does not prove the mutable writer. -/
def rectangleCells (left right : List Int) : List Int :=
  left.flatMap fun a => right.flatMap fun b => [a, b]

theorem rectangle_cells_order (left right : List Int) :
    rectangleCells left right =
      ((ProviderRectangles.rows ⟨left, right⟩).map
        (fun row => [row.1, row.2])).flatten := by
  simp [rectangleCells, ProviderRectangles.rows, List.flatten_eq_flatMap,
    List.flatMap_map, List.flatMap_assoc]

/-- Removing the disposable ordinary binary-row graph eliminates three pairs
per row. Buffer slots are a separate unit, not a byte or RSS bound. -/
theorem direct_rectangle_pair_saving (left right : List Int) :
    (collectProductCost left right ([], 0)).2 =
      3 * (left.length * right.length) := by
  rw [collectProductCost_exact]
  simp

def unpack (width : Nat) : Nat → List Int → Option (List (List Int))
  | 0, cells => if cells.isEmpty then some [] else none
  | count + 1, cells =>
      if width ≤ cells.length then
        (unpack width count (cells.drop width)).map (cells.take width :: ·)
      else none

theorem unpack_flatten (width : Nat) (rows : List (List Int))
    (rectangular : ∀ row ∈ rows, row.length = width) :
    unpack width rows.length rows.flatten = some rows := by
  induction rows with
  | nil => rfl
  | cons row rest ih =>
    have size : row.length = width := rectangular row (by simp)
    have tail : ∀ item ∈ rest, item.length = width := by
      intro item member
      exact rectangular item (by simp [member])
    have enough : width ≤ (row ++ rest.flatten).length := by
      simp only [List.length_append, size]
      omega
    simp only [List.length_cons, List.flatten_cons, unpack, enough, ↓reduceIte,
      List.take_left' size, List.drop_left' size, ih tail, Option.map_some]

theorem flattened_size (width : Nat) (rows : List (List Int))
    (rectangular : ∀ row ∈ rows, row.length = width) :
    rows.flatten.length = rows.length * width := by
  induction rows with
  | nil => simp
  | cons row rest ih =>
    have size := rectangular row (by simp)
    have tail : ∀ item ∈ rest, item.length = width := by
      intro item member
      exact rectangular item (by simp [member])
    simp only [List.flatten_cons, List.length_append, List.length_cons, size, ih tail,
      Nat.add_mul, Nat.one_mul]
    omega

def lower : Int := -9223372036854775808
def upper : Int := 9223372036854775807
def fits (value : Int) : Prop := lower ≤ value ∧ value ≤ upper

theorem rectangle_cells_size (left right : List Int) :
    (rectangleCells left right).length = 2 * (left.length * right.length) := by
  have rectangular : ∀ row ∈ (ProviderRectangles.rows ⟨left, right⟩).map
      (fun pair => [pair.1, pair.2]), row.length = 2 := by
    intro row member
    obtain ⟨pair, _, rfl⟩ := List.mem_map.mp member
    rfl
  have size := flattened_size 2 _ rectangular
  rw [← rectangle_cells_order] at size
  simp only [List.length_map, ProviderRectangles.rectangle_length] at size
  omega

/-- Writer offset starts after the two header words and advances by two.
The size preflight must additionally establish native allocation/index bounds. -/
theorem rectangle_write_bounds (rows row : Nat) (inside : row < rows) :
    2 + 2 * row < 2 + 2 * rows ∧ 2 + 2 * row + 1 < 2 + 2 * rows := by omega

/-- Word payload of the existing binary rectangle transfer. The two header
words contain row count and width. Excludes vector headers, capture,
fallback, bridge copies and Rust-owned output. -/
def binaryVectorPayload (rows : Nat) : Nat := 8 * (2 + 2 * rows)

/-- Producing a packed buffer after constructing detached lists pays for
both payloads. Direct rectangular packing removes the list term from the
transfer candidate. The ordinary list consumer still needs that term. -/
theorem direct_binary_payload_saving (rows : Nat) :
    binaryVectorPayload rows + freshRowBytes rows - binaryVectorPayload rows =
      freshRowBytes rows := by
  omega

theorem dense_512_binary_transfer_payload :
    32 * binaryVectorPayload (512 * 512) = 134218240 ∧
    payload 512 = 603979776 := by decide

/-- After rectangular admission, every write and next offset remain within
    the checked allocation bound. The bridge must realize this bound as a
    nonnegative native fixnum before selecting the specialized increment. -/
theorem cell_increment_within_capacity (size limit offset : Nat)
    (allocation : size ≤ limit) (inside : offset < size) :
    offset + 1 ≤ size ∧ offset + 1 ≤ limit := by
  omega

theorem packed_cells_retain_range (rows : List (List Int))
    (admitted : ∀ row ∈ rows, ∀ value ∈ row, fits value) :
    ∀ value ∈ rows.flatten, fits value := by
  intro value member
  obtain ⟨row, present, inside⟩ := List.mem_flatten.mp member
  exact admitted row present value inside

-- Reference word-row charge: inspect/promote/reinspect/length/snapshot,
-- two root releases and kind+scalar per cell. This excludes fixed envelope
-- work and the Scheme packing traversal. Numeric kind+size+copy costs three.
def ordinaryRowCalls (rows columns : Nat) := rows * (7 + 2 * columns)
-- The current candidate passes the snapshot's observed kind to the shared
-- owned decoder. Root promotion, length, snapshot and releases are unchanged.
def knownKindRowCalls (rows columns : Nat) := rows * (6 + 2 * columns)
def packedCalls : Nat := 3

theorem known_kind_removes_one_query_per_row (rows columns : Nat) :
    knownKindRowCalls rows columns + rows = ordinaryRowCalls rows columns := by
  unfold knownKindRowCalls ordinaryRowCalls
  simp only [Nat.mul_add]
  omega

/-- Only classification queries are counted here. The shared decoder body,
root promotion, scalar projection and cleanup retain their original charges. -/
theorem known_kind_graph_query_saving (roots scalarChildren promotedChildren : Nat) :
    roots + scalarChildren + 2 * promotedChildren =
      (roots + scalarChildren + promotedChildren) + promotedChildren := by
  omega

/-- Reusing a classification is sound under the bridge's type-stability law
for root promotion. That native ownership law remains an explicit premise;
this theorem does not establish a Rust/C ABI implementation refinement. -/
theorem known_kind_dispatch_equivalent {Value Kind Answer : Type}
    (classify : Value → Kind) (promote : Value → Value)
    (dispatch : Value → Kind → Answer) (value : Value)
    (stable : classify (promote value) = classify value) :
    dispatch (promote value) (classify (promote value)) =
      dispatch (promote value) (classify value) := by
  rw [stable]

theorem fewer_native_calls (rows columns : Nat) (nonempty : 0 < rows)
    (positiveWidth : 0 < columns) : packedCalls < ordinaryRowCalls rows columns := by
  unfold packedCalls ordinaryRowCalls
  have factor : 9 ≤ 7 + 2 * columns := by omega
  have bound := Nat.mul_le_mul_left rows factor
  omega

-- Only disposable vector payload slots, not bytes/RSS/cumulative allocation.
-- The original public rows and the final Rust-owned rows remain fresh.
theorem fewer_snapshot_slots (rows columns : Nat) (nonempty : 0 < rows)
    (positiveWidth : 0 < columns) :
    2 + rows * columns ≤ 2 * rows + 2 * (rows * columns) := by
  have positive : 0 < rows * columns := Nat.mul_pos nonempty positiveWidth
  omega

/-- Source emission shares the exact signed bounds with the range model. -/
def schemeSource : String :=
  ";;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Private typed transfer of already captured business rows, never an evaluator.\n(import :gerbil/runtime)\n(export ascent-pack-integer-rows ascent-pack-row-relations!\n        ascent-serialize-detached-rows)\n\n(def (signed-word? value)\n  (and (exact-integer? value)\n       (<= " ++
    toString lower ++
    " value " ++
    toString upper ++
    ")))\n\n;; ascent-pack-integer-rows\n;; : (forall (a) (-> a (Or a S64Vector)))\n;; : (-> RowGraph PackedOrOriginalRows)\n;; | doc m%\n;;     Copy a nonempty rectangular signed-64 relation to a fresh count/width\n;;     buffer. Preserve the original graph by identity for unsupported inputs.\n;;     The fixnum allocation bound also bounds every cell offset and its next\n;;     position, so the checked writer uses fx+ without narrowing row values.\n;;\n;;     # Examples\n;;\n;;     ```scheme\n;;     (ascent-pack-integer-rows '((1 2)))\n;;     ;; => #s64(1 2 1 2)\n;;     ```\n;;   %\n(def (ascent-pack-integer-rows rows)\n  ;; Empty and zero-column relations keep the ordinary list representation.\n  ;; Every unsupported value retains that exact graph and its existing codec.\n  (if (and (list? rows) (pair? rows)\n           (list? (car rows)) (pair? (car rows)))\n    (let* ((width (length (car rows)))\n           (count (length rows))\n           (size (+ 2 (* count width))))\n      (if (and (fixnum? size)\n               (<= count " ++
    toString upper ++
    ")\n               (<= width " ++
    toString upper ++
    ")\n               (andmap (lambda (row)\n                         (and (list? row) (= (length row) width)\n                              (andmap signed-word? row)))\n                       rows))\n        (let (packed (make-s64vector size))\n          (s64vector-set! packed 0 count)\n          (s64vector-set! packed 1 width)\n          (let copy-rows ((pending rows) (offset 2))\n            (if (null? pending) packed\n              (let copy-cells ((cells (car pending)) (offset offset))\n                (if (null? cells)\n                  (copy-rows (cdr pending) offset)\n                  (begin\n                    (s64vector-set! packed offset (car cells))\n                    (copy-cells (cdr cells) (fx+ offset 1))))))))\n        rows))\n    rows))\n\n(def (ascent-pack-row-relations! reply)\n  ;; The application owns this answer map. Snapshot its few entries before\n  ;; replacing values; never mutate a table while traversing its live buckets.\n  (let (relations (hash-ref reply \"relations\"))\n    (for-each\n      (lambda (entry)\n        (hash-put! relations (car entry)\n                   (ascent-pack-integer-rows (cdr entry))))\n      (hash->list relations)))\n  reply)\n" ++
    "\n;; BEGIN GENERATED DETACHED WIRE ROWS\n" ++
    SourceProjection.detachedWireSchemeSource ++
    ";; END GENERATED DETACHED WIRE ROWS\n"

end IntegerRowTransfer

namespace TerminalReplay

structure Batch (α : Type) where
  probe : α
  cells : List α

def writeBatch [DecidableEq α] (mask : α → Bool) (batch : Batch α) : α → Bool :=
  fun key => if key ∈ batch.cells then true else mask key

def markedBatches [DecidableEq α] (mask : α → Bool) : List (Batch α) → List α
  | [] => []
  | batch :: rest =>
      if mask batch.probe then markedBatches mask rest
      else batch.cells ++ markedBatches (writeBatch mask batch) rest

theorem batch_observation_congr [DecidableEq α] (left right : α → Bool)
    (batches : List (Batch α))
    (agree : ∀ batch ∈ batches, left batch.probe = right batch.probe) :
    markedBatches left batches = markedBatches right batches := by
  induction batches generalizing left right with
  | nil => rfl
  | cons batch rest ih =>
      have tailAgree : ∀ item ∈ rest, left item.probe = right item.probe := by
        intro item member
        exact agree item (by simp [member])
      have same := agree batch (by simp)
      cases observed : left batch.probe with
      | true =>
          have other : right batch.probe = true := same.symm.trans observed
          simpa [markedBatches, observed, other] using ih left right tailAgree
      | false =>
          have other : right batch.probe = false := same.symm.trans observed
          simp only [markedBatches, observed, other, Bool.false_eq_true, ↓reduceIte]
          congr 1
          apply ih
          intro item member
          by_cases written : item.probe ∈ batch.cells
          · simp [writeBatch, written]
          · simp [writeBatch, written, tailAgree item member]

/-- A weighted root pair writes all its member cells. Future root probes
must lie outside that batch; singleton-address uniqueness alone is insufficient. -/
theorem final_batch_marks_unobservable [DecidableEq α] (mask : α → Bool)
    (batches : List (Batch α))
    (safe : batches.Pairwise (fun first later => later.probe ∉ first.cells)) :
    markedBatches mask batches =
      batches.flatMap (fun batch => if mask batch.probe then [] else batch.cells) := by
  induction batches generalizing mask with
  | nil => rfl
  | cons batch rest ih =>
      have separated := List.pairwise_cons.mp safe
      cases observed : mask batch.probe with
      | true => simpa [markedBatches, observed] using ih mask separated.2
      | false =>
          simp only [markedBatches, observed, Bool.false_eq_true, ↓reduceIte,
            List.flatMap_cons]
          congr 1
          have stable : ∀ later ∈ rest,
              writeBatch mask batch later.probe = mask later.probe := by
            intro later member
            simp [writeBatch, separated.1 later member]
          rw [batch_observation_congr _ mask rest stable, ih mask separated.2]

theorem disjoint_members_protect_probe (first later : Batch α)
    (member : later.probe ∈ later.cells)
    (separate : ∀ cell ∈ later.cells, cell ∉ first.cells) :
    later.probe ∉ first.cells := separate later.probe member

/-- Read-then-mark projection for distinct root-pair addresses. These are
addresses in the temporary replay matrix, not user-value hashes. -/
def marked [DecidableEq α] (mask : α → Bool) : List α → List α
  | [] => []
  | address :: rest =>
      if mask address then marked mask rest
      else address :: marked (fun key => if key = address then true else mask key) rest

theorem untouched_filter [DecidableEq α] (mask : α → Bool) (address : α)
    (rest : List α) (absent : address ∉ rest) :
    rest.filter (fun key => !(if key = address then true else mask key)) =
      rest.filter (fun key => !(mask key)) := by
  apply List.filter_congr
  intro key member
  have different : key ≠ address := by
    intro same
    exact absent (same ▸ member)
  simp [different]

/-- Final private marking is unnecessary for output selection when no later
probe repeats an address. The source must establish disjoint root components,
unique root-pair traversal and that no later injection reads the matrix. -/
theorem final_marks_unobservable [DecidableEq α] (mask : α → Bool)
    (addresses : List α) (unique : addresses.Nodup) :
    marked mask addresses = addresses.filter (fun key => !(mask key)) := by
  induction addresses generalizing mask with
  | nil => rfl
  | cons address rest ih =>
      have distinct := List.nodup_cons.mp unique
      cases observed : mask address with
      | true => simp [marked, observed, ih mask distinct.2]
      | false =>
          simp only [marked, observed, Bool.false_eq_true, ↓reduceIte,
            List.filter_cons, Bool.not_false, ↓reduceIte]
          rw [ih _ distinct.2, untouched_filter mask address rest distinct.1]

/-- A duplicate address is an essential negative control: dropping writes
without the uniqueness premise would publish the missing fact twice. -/
theorem duplicate_address_rejected :
    marked (fun _ : Nat => false) [0, 0] ≠
      [0, 0].filter (fun _ => true) := by decide

def present (bits : List Bool) : Nat := (bits.filter id).length
def missing (bits : List Bool) : Nat := (bits.filter (! ·)).length

theorem bitmap_partition (bits : List Bool) :
    present bits + missing bits = bits.length := by
  induction bits with
  | nil => rfl
  | cons bit rest ih => cases bit <;> simp [present, missing] at * <;> omega

theorem singleton_cut_missing (bits : List Bool) (vertices : Nat)
    (complete : bits.length = vertices * vertices) :
    missing bits = vertices * vertices - present bits := by
  have partition := bitmap_partition bits
  omega

def bitmapWords (cells : Nat) : Nat := (cells + 15) / 16

theorem bulk_count_uses_fewer_probes (cells : Nat) (nontrivial : 2 ≤ cells) :
    bitmapWords cells < cells := by
  unfold bitmapWords
  omega

/-- Only terminal matrix stores are charged here. Output, root probes,
preparation and GC still cost work even when the discarded-state writes vanish. -/
theorem terminal_store_saving [DecidableEq α] (mask : α → Bool) (addresses : List α)
    (unique : addresses.Nodup) :
    (marked mask addresses).length =
      (addresses.filter (fun key => !(mask key))).length := by
  rw [final_marks_unobservable mask addresses unique]

/-- The terminal writer leaves the retained mask unchanged. With output
declined it has no result, so all of its candidate probes can be omitted. -/
theorem declined_terminal_writer [DecidableEq α] (mask : α → Bool)
    (addresses : List α) (emit : Bool) (unique : addresses.Nodup) :
    (if emit then marked mask addresses else []) =
      (if emit then addresses.filter (fun key => !(mask key)) else []) := by
  cases emit <;> simp [final_marks_unobservable mask addresses unique]

end TerminalReplay

namespace ReplayColumn

/-- A fresh target has only its reflexive bit. Extending an old vertex to
that target adds exactly the old vertex's predecessor column. Word OR
retains the reflexive bit and leaves unrelated words outside the column. -/
theorem merge_word (old fresh bit : Nat) :
    (fresh ||| old).testBit bit = (fresh.testBit bit || old.testBit bit) :=
  Nat.testBit_or fresh old bit

theorem fresh_target_column (old fresh source target : Nat)
    (reflexive : fresh.testBit source = decide (source = target)) :
    (fresh ||| old).testBit source =
      (decide (source = target) || old.testBit source) := by
  rw [merge_word, reflexive]

/-- Words form disjoint, fixed-size columns, including the padding in
the last word. A copy over one column has no write in another column. -/
theorem disjoint_column_words (words first second i j : Nat)
    (earlier : first < second) (inside : i < words) :
    first * words + i < second * words + j := by
  calc
    first * words + i < first * words + words := by omega
    _ = (first + 1) * words := by simp [Nat.add_mul]
    _ ≤ second * words := Nat.mul_le_mul_right words earlier
    _ ≤ second * words + j := by omega

theorem aligned_position (words target source : Nat) :
    (target * (words * 16) + source) / 16 =
      target * words + source / 16 ∧
    (target * (words * 16) + source) % 16 = source % 16 := by
  rw [← Nat.mul_assoc]
  omega

theorem copy_reduces_dense_writes (width predecessors : Nat)
    (dense : (width + 15) / 16 < predecessors) :
    TerminalReplay.bitmapWords width < predecessors := dense

theorem copy_then_mark_reflexive (old target : Nat)
    (bit : Nat) :
    (old ||| 2 ^ target).testBit bit =
      (old.testBit bit || decide (target = bit)) := by
  rw [Nat.testBit_or, Nat.testBit_two_pow]

theorem predecessor_flag [DecidableEq α] (outbound predecessor : α → Bool)
    (source vertex : α)
    (self : predecessor source = true)
    (prior : vertex ≠ source → predecessor vertex = true → outbound vertex = true) :
    (outbound vertex || predecessor vertex) =
      (outbound vertex || decide (vertex = source)) := by
  by_cases same : vertex = source
  · subst vertex
    simp [self]
  · cases reached : predecessor vertex
    · simp [same]
    · simp [same, prior same reached]

/-- The capture can copy a column only when the number of cells in the
fresh cross-product exceeds the number of machine words. The copy is
followed by one store restoring the target's reflexive bit. The original
writer had already performed the initial reflexive store too. -/
def freshTargetStores (width cells : Nat) : Nat :=
  min (TerminalReplay.bitmapWords width + 1) cells

theorem guarded_target_store_bound (width cells : Nat) :
    freshTargetStores width cells ≤ cells := Nat.min_le_right _ _

theorem strict_target_store_saving (width cells : Nat)
    (dense : TerminalReplay.bitmapWords width + 1 < cells) :
    freshTargetStores width cells < cells := by
  exact Nat.lt_of_le_of_lt (Nat.min_le_left _ _) dense

end ReplayColumn

namespace PrivateSpine

/-- The private skeleton is sized before either coordinate is written. A
fill step overwrites one empty slot with the next row. No consumer can see
the intermediate slots. -/
def fill {Row : Type} : List (Option Row) → List Row → List (Option Row)
  | _ :: slots, row :: rows => some row :: fill slots rows
  | slots, _ => slots

theorem fill_exact {Row : Type} (rows : List Row) :
    fill (List.replicate rows.length none) rows = rows.map some := by
  induction rows with
  | nil => rfl
  | cons row rest ih => simp [fill, List.replicate_succ, ih]

/-- One preallocated outer cell and two fresh row cells per binary row.
The result size is unchanged. Differences in copying, pause duration and
wall time depend on the physical allocation sequence and must be measured. -/
theorem binary_fill_cells (leftWidth rightWidth : Nat) :
    leftWidth * rightWidth + 2 * (leftWidth * rightWidth) =
      3 * (leftWidth * rightWidth) := by omega

/-- At the same number of completed tuples the skeleton has more live
pair cells than the interleaved construction, until the final tuple. -/
theorem skeleton_live_prefix (rows filled : Nat) (bound : filled ≤ rows) :
    3 * filled ≤ rows + 2 * filled := by omega

/-- Draining the row directory from right to left preserves row order.
Each visited slot may be cleared once its row is linked to the result. -/
theorem drain_directory_exact {Row : Type} (rows tail : List Row) :
    rows.reverse.foldl (fun output row => row :: output) tail = rows ++ tail := by
  induction rows generalizing tail with
  | nil => rfl
  | cons row rest ih => simp [List.reverse_cons, List.foldl_append, ih]

end PrivateSpine

namespace PairBlock

/-- A private chain stores the two row values during allocation. Publication
needs only three pointer writes: outer car and cdr, and the tuple tail cdr.
The tuple head already points at its tail. Here an empty link models null. -/
structure FilledTriple (α : Type) where
  outer : Nat
  head : Nat
  tail : Nat
  next : Option Nat
  left : α
  right : α

def FilledTriple.publish (triple : FilledTriple α) :
    (Nat × Nat × Option Nat) × (Nat × α × Nat) × (Nat × α × Option Nat) :=
  ((triple.outer, triple.head, triple.next),
   (triple.head, triple.left, triple.tail), (triple.tail, triple.right, none))

theorem filled_triple_preserves_cells_and_values (triple : FilledTriple α) :
    let (outer, head, tail) := triple.publish
    [outer.1, head.1, tail.1] = [triple.outer, triple.head, triple.tail] ∧
      (head.2.1, tail.2.1) = (triple.left, triple.right) ∧
      outer.2 = (head.1, triple.next) ∧ head.2.2 = tail.1 ∧ tail.2.2 = none := by
  simp [FilledTriple.publish]

/-- Prepending an outer placeholder and both already-filled row cells
while walking reversed axes produces left-major triples. The backwards
traversal applies only to the private allocation phase. -/
theorem filled_triple_allocation_order (left right : List α) :
    (left.reverse.flatMap (fun a => right.reverse.map (fun b => (a, b)))).reverse =
      ProviderRectangles.rows ⟨left, right⟩ := by
  simp [ProviderRectangles.rows, List.reverse_flatMap, Function.comp_def]

theorem filled_triple_publication_saves_value_stores (rows : Nat) :
    5 * rows = 3 * rows + 2 * rows := by omega

/-- Assign each consecutive triple of fresh cells to one output row. The
native writer uses the middle cell for the tuple head, the final cell for
its tail, and the first cell for the outer list. -/
def reshape {Row : Type} : List Nat → List Row → Option (List (BinaryRowCells × Row))
  | [], [] => some []
  | outer :: first :: second :: remaining, row :: rows =>
    (reshape remaining rows).map (fun tail => (⟨outer, first, second⟩, row) :: tail)
  | _, _ => none

theorem reshape_exact {Row : Type} (rows : List Row) (cells : List Nat)
    (width : cells.length = 3 * rows.length) :
    ∃ result, reshape cells rows = some result ∧ result.map Prod.snd = rows ∧
      exportCells (result.map Prod.fst) = cells := by
  induction rows generalizing cells with
  | nil =>
    cases cells <;> simp_all [reshape, exportCells]
  | cons row rows ih =>
    cases cells with
    | nil => simp at width
    | cons outer cells =>
      cases cells with
      | nil => simp at width; omega
      | cons first cells =>
        cases cells with
        | nil => simp at width; omega
        | cons second remaining =>
          have remainingWidth : remaining.length = 3 * rows.length := by
            simp only [List.length_cons] at width
            omega
          obtain ⟨tail, shape, values, layout⟩ := ih remaining remainingWidth
          refine ⟨(⟨outer, first, second⟩, row) :: tail, ?_, ?_, ?_⟩
          · simp [reshape, shape]
          · simp [values]
          · simpa [exportCells] using layout

/-- Only one right-axis block can be allocated ahead of publication. The
model charges pair identities, independently of runtime heap accounting. -/
theorem pair_block_live_bound (published prepared width : Nat) (bounded : prepared ≤ width) :
    3 * (published + prepared) ≤ 3 * published + 3 * width := by omega

/-- Before the detached result is assembled, a linear scratch chain has
an immediate car in every pair. The final tuple representation introduces
one car-to-pair edge per row. The frozen collector follows cdr first, so
the scratch chain defers no pair-valued car until finalization. -/
def pairCarEdges (layout : List Bool) : Nat :=
  (layout.filter id).length

def binaryCarLayout : Nat → List Bool
  | 0 => []
  | n + 1 => true :: false :: false :: binaryCarLayout n

theorem binary_car_layout (rows : Nat) :
    (binaryCarLayout rows).length = 3 * rows ∧
      pairCarEdges (binaryCarLayout rows) = rows := by
  induction rows with
  | zero => decide
  | succ n ih =>
    have lengthEq := ih.1
    have edgeEq := ih.2
    unfold pairCarEdges at edgeEq
    simp [binaryCarLayout, pairCarEdges, lengthEq, edgeEq, Nat.mul_add]

theorem scratch_defers_fewer_pair_edges (rows : Nat) (nonempty : 0 < rows) :
    pairCarEdges (List.replicate (3 * rows) false) <
      pairCarEdges (binaryCarLayout rows) := by
  rw [(binary_car_layout rows).2]
  simpa [pairCarEdges] using nonempty

/-- A full-size scratch chain retains exactly the same payload as the
finished result. This equality gives no bound on copies between collections. -/
theorem scratch_pair_charge (rows : Nat) : 24 * (3 * rows) = 72 * rows := by omega

end PairBlock

/-- The collector can encounter an unfinished list and previously returned
lists. Each returned binary row owns a spine cell and two tuple cells.
The multiplier is the native semispace accounting charge, not RSS. -/
def visibleBinaryPairCharge (width retained inFlightRows : Nat) : Nat :=
  2 * 3 * 24 * (retained * (width * width) + inFlightRows)

theorem visible_binary_pair_charge_splits (width retained inFlightRows : Nat) :
    visibleBinaryPairCharge width retained inFlightRows =
      visibleBinaryPairCharge width retained 0 +
      visibleBinaryPairCharge width 0 inFlightRows := by
  simp [visibleBinaryPairCharge, Nat.mul_add]

/-- Once the caller drops every completed output, at most one export's
detached pairs are charged. Other heap roots remain outside this bound. -/
theorem released_exports_bound (width inFlightRows : Nat)
    (prefixBound : inFlightRows ≤ width * width) :
    visibleBinaryPairCharge width 0 inFlightRows ≤
      visibleBinaryPairCharge width 1 0 := by
  simp [visibleBinaryPairCharge]
  omega

/-- Both traces use the same semispace accounting unit. Compare the corrected
pre-collection watermark against its call start, and the post-collection
movable charge against the loaded no-output baseline. The measured tolerance
covers chunk links, stack and other live changes without assigning their bytes
to individual objects. -/
theorem live_prefix_residual_bounds
    (start watermark still baseline live tolerance : Int)
    (lower : -(tolerance) ≤ (live - baseline) - (watermark + still - start))
    (upper : (live - baseline) - (watermark + still - start) ≤ tolerance) :
    baseline + (watermark + still - start) - tolerance ≤ live ∧
    live ≤ baseline + (watermark + still - start) + tolerance := by
  omega

/-- Gambit 64-bit copies charge both semispaces. At 255 payload words per
full chunk, one link word costs 16 accounting bytes per 4080 payload
accounting bytes. This describes complete payload-only chunks; section
transitions, chunk overruns, mixed objects and the stack are external. -/
theorem complete_chunk_link_charge (chunks tail : Nat) (withinChunk : tail < 4080) :
    16 * ((4080 * chunks + tail) / 4080) = 16 * chunks := by
  omega

/-- Blocking left coordinates bounds the in-flight detached pairs. It still
charges the entire output over all blocks when they cover the original axis.
This is an attribution control with a streaming consumer. -/
theorem blocked_product_preserves_payload (left right : Nat) (blocks : List Nat)
    (coverage : blocks.sum = left) :
    (blocks.map fun width => 144 * (width * right)).sum = 144 * (left * right) := by
  subst left
  induction blocks with
  | nil => simp
  | cons width rest ih =>
    simp only [List.map_cons, List.sum_cons, Nat.add_mul, Nat.mul_add]
    rw [ih]

theorem blocked_product_preserves_order (blocks : List (List α)) (right : List α) :
    blocks.flatMap (fun left => ProviderRectangles.rows ⟨left, right⟩) =
      ProviderRectangles.rows ⟨blocks.flatten, right⟩ := by
  induction blocks with
  | nil => rfl
  | cons block rest ih =>
    simp only [List.flatMap_cons, List.flatten_cons] at *
    rw [ih]
    simp [ProviderRectangles.rows, List.flatMap_append]

/-- Lowering the average pause does not lower total GC CPU if the added
collections consume the saving. Use sums from each matched batch; the
cross-products avoid rounding the per-collection means. -/
theorem extra_collections_can_erase_pause_gain
    (fullCount shortCount fullCPU shortCPU : Nat)
    (positive : 0 < fullCount)
    (gainErased : fullCPU * fullCount ≤ shortCPU * fullCount)
    (lowerMean : shortCPU * fullCount < fullCPU * shortCount) :
    fullCPU ≤ shortCPU ∧ fullCount < shortCount := by
  have cpu : fullCPU ≤ shortCPU := Nat.le_of_mul_le_mul_right gainErased positive
  have increased : fullCPU * fullCount < fullCPU * shortCount :=
    Nat.lt_of_le_of_lt gainErased lowerMean
  exact ⟨cpu, Nat.lt_of_mul_lt_mul_left increased⟩

theorem four_retained_exports_charge :
    visibleBinaryPairCharge 384 4 0 = 84934656 ∧
    visibleBinaryPairCharge 512 4 0 = 150994944 := by decide

/-- Allocating the outer pair before the tuple changes the order of the
three allocations. It leaves the result and every pair identity intact
when all fields are initialized before the row becomes visible. -/
theorem spine_first_row_publication
    (left right : α) (outer first second : Nat)
    (fresh : [outer, first, second].Nodup) :
    PairBlock.reshape [outer, first, second] [(left, right)] =
      some [(⟨outer, first, second⟩, (left, right))] ∧
    (exportCells [⟨outer, first, second⟩]).Nodup := by
  exact ⟨rfl, by simpa [exportCells] using fresh⟩

namespace ReplayRepresentative

/-- The bitmap needs only one entry for a pair of live owners. The
existing SCC update must first establish uniform reachability to and
from the winning representative. Entries for retired IDs are unobserved. -/
def read (bits : Nat → Nat → Bool) (owner : Nat → Nat) (a b : Nat) : Bool :=
  bits (owner a) (owner b)

/-- Closing one new arc adds its predecessor-by-successor product.
Transitivity of the old relation makes a second pass unnecessary. -/
def extend (old : Nat → Nat → Prop) (source target a b : Nat) : Prop :=
  old a b ∨ (old a source ∧ old target b)

theorem extend_transitive (old : Nat → Nat → Prop) (source target : Nat)
    (transitive : ∀ a b c, old a b → old b c → old a c)
    (a b c : Nat) (ab : extend old source target a b)
    (bc : extend old source target b c) : extend old source target a c := by
  rcases ab with ab | ⟨aSource, targetB⟩
  · rcases bc with bc | ⟨bSource, targetC⟩
    · exact Or.inl (transitive a b c ab bc)
    · exact Or.inr ⟨transitive a b source ab bSource, targetC⟩
  · rcases bc with bc | ⟨_, targetC⟩
    · exact Or.inr ⟨aSource, transitive target b c targetB bc⟩
    · exact Or.inr ⟨aSource, targetC⟩

theorem extend_adds_arc (old : Nat → Nat → Prop) (source target : Nat)
    (sourceRefl : old source source) (targetRefl : old target target) :
    extend old source target source target :=
  Or.inr ⟨sourceRefl, targetRefl⟩

theorem extend_least (old closed : Nat → Nat → Prop) (source target : Nat)
    (includes : ∀ a b, old a b → closed a b)
    (transitive : ∀ a b c, closed a b → closed b c → closed a c)
    (edge : closed source target) (a b : Nat)
    (added : extend old source target a b) : closed a b := by
  rcases added with present | ⟨left, right⟩
  · exact includes a b present
  · exact transitive a target b
      (transitive a source target (includes a source left) edge)
      (includes target b right)

theorem exact_after_merge (bits : Nat → Nat → Bool) (owner : Nat → Nat)
    (reachable : Nat → Nat → Bool)
    (exactRepresentative : ∀ a b, bits (owner a) (owner b) = reachable a b) :
    read bits owner = reachable := by
  funext a b
  exact exactRepresentative a b

theorem nonwinning_cells_are_unobserved
    (before after : Nat → Nat → Bool) (owner : Nat → Nat)
    (liveCells : ∀ a b, after (owner a) (owner b) = before (owner a) (owner b)) :
    read after owner = read before owner := by
  funext a b
  exact liveCells a b

/-- Once the new component edges have been committed, replacing any
merged owner by the winner preserves both directions of every query. -/
theorem merge_preserves_representative_reads
    (bits : Nat → Nat → Bool) (owner : Nat → Nat) (merging : Nat → Bool)
    (winner : Nat)
    (outbound : ∀ a b, merging a = true → bits winner b = bits a b)
    (inbound : ∀ a b, merging b = true → bits a winner = bits a b) :
    read bits (fun v => if merging (owner v) then winner else owner v) =
      read bits owner := by
  funext a b
  unfold read
  cases ha : merging (owner a) <;> cases hb : merging (owner b)
  · simp [ha, hb]
  · simpa [ha, hb] using inbound (owner a) (owner b) hb
  · simpa [ha, hb] using outbound (owner a) (owner b) ha
  · simpa [ha, hb] using
      (outbound (owner a) winner ha).trans (inbound (owner a) (owner b) hb)

/-- A completed closure makes every member of the merged SCC
interchangeable as a source and as a target. -/
theorem mutual_reach_has_same_neighborhood
    (bits : Nat → Nat → Bool)
    (transitive : ∀ a b c, bits a b = true → bits b c = true → bits a c = true)
    (winner other : Nat) (out : bits winner other = true)
    (back : bits other winner = true) (vertex : Nat) :
    bits winner vertex = bits other vertex ∧
      bits vertex winner = bits vertex other := by
  constructor
  · cases h₁ : bits winner vertex <;> cases h₂ : bits other vertex
    · rfl
    · exact False.elim (Bool.noConfusion (h₁.symm.trans (transitive winner other vertex out h₂)))
    · exact False.elim (Bool.noConfusion (h₂.symm.trans (transitive other winner vertex back h₁)))
    · rfl
  · cases h₁ : bits vertex winner <;> cases h₂ : bits vertex other
    · rfl
    · exact False.elim (Bool.noConfusion (h₁.symm.trans (transitive vertex other winner h₂ back)))
    · exact False.elim (Bool.noConfusion (h₂.symm.trans (transitive vertex winner other h₁ out)))
    · rfl

/-- Store cost for nonempty components. Member traversal remains in the
row-producing lane. It has zero visits when the consumer declines rows. -/
theorem one_store_per_admitted_pair (left right : Nat)
    (multirow : 1 < left * right) : 1 < left * right ∧
      (left * right - 1) + 1 = left * right := by
  omega

end ReplayRepresentative

/-- Forward traversal with private prepends records precisely the reverse
of the remaining ordered values in front of the already allocated spine. -/
theorem reverse_collector_exact (rows accumulator : List α) :
    (rows.foldl (fun spine row => row :: spine) accumulator).reverse =
      accumulator.reverse ++ rows := by
  induction rows generalizing accumulator with
  | nil => simp
  | cons row rest ih =>
    simp only [List.foldl_cons, ih, List.reverse_cons, List.append_assoc,
      List.singleton_append]

/-- Either cursor layout allocates the same three output cells. Removing
the sentinel and cursor box changes only the constant constructor term. -/
theorem register_cursor_payload (width : Nat) :
    144 * (width * width) + 80 = 2 * builderConstructorPayload width := by
  unfold builderConstructorPayload
  omega

/-- A complete public list owns a distinct spine cell and both tuple cells
per binary row. Each coordinate occurrence remains writable after export.
These charges exclude the collector, auxiliary state and all object headers
other than the three native pair headers. -/
def detachedBatchPairPayload (width exports : Nat) : Nat :=
  exports * (width * width) * (3 * 24)

theorem strict_workload_pair_payload :
    detachedBatchPairPayload 384 32 = 339738624 ∧
    detachedBatchPairPayload 512 32 = 603979776 := by decide

/-- A different builder can reduce auxiliary work while still paying the
same public payload. Meeting the strict wall cap also requires the remaining
collector interval to fit after that payload has been constructed. -/
theorem detached_batch_requires_collector_budget
    (width exports allocated materialize collect limit : Nat)
    (payload : detachedBatchPairPayload width exports ≤ allocated)
    (pass : materialize + collect < limit) :
    detachedBatchPairPayload width exports ≤ allocated ∧
      collect < limit - materialize := by
  exact ⟨payload, by omega⟩

/-- Work at each whole-heap marking phase. `background` includes the
reachable roots of the loaded VM and `inFlight` is the live result of the
current export. The lists price actual pauses, not distinct heap objects. -/
def repeatedExportMarking (background : Nat) (inFlight : List Nat) : Nat :=
  (inFlight.map (background + ·)).sum

theorem repeated_export_marking (background : Nat) (inFlight : List Nat) :
    repeatedExportMarking background inFlight =
      inFlight.length * background + inFlight.sum := by
  induction inFlight with
  | nil => simp [repeatedExportMarking]
  | cons live rest ih =>
    simp only [repeatedExportMarking, List.map_cons, List.sum_cons] at ih ⊢
    rw [ih, List.length_cons, Nat.add_mul]
    omega

/-- Eliminating all in-flight work still leaves one background charge
for every whole-heap pause. This accounts for the source work under a
fixed schedule and price. Collector scheduling remains a native premise. -/
theorem collector_background_floor (background : Nat) (inFlight : List Nat) :
    inFlight.length * background ≤ repeatedExportMarking background inFlight := by
  rw [repeated_export_marking]
  omega

end Ascent.WeightedCapacity
