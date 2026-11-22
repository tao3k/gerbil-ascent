-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
import RuntimeMeasurement

/-! Measurement scope and the independent complete-row oracle. This does not
prove the Scheme bitmap, rule evaluator, concrete allocation or achieved speed. -/
namespace Ascent.MillionQueryWorkload

def inputFacts (groups width : Nat) : Nat := groups * (width - 1)
def closureRows (groups width : Nat) : Nat := groups * width * (width - 1) / 2
def materializedFacts (groups width : Nat) : Nat :=
  inputFacts groups width + closureRows groups width

theorem million_input_profile : inputFacts 1000000 2 = 1000000 := by decide
theorem recursive_input_profile : inputFacts 128 128 = 16256 := by decide
theorem recursive_output_profile : closureRows 128 128 = 1040384 := by decide
theorem million_total_profile : materializedFacts 1000000 2 = 2000000 := by decide
theorem recursive_total_profile : materializedFacts 128 128 = 1056640 := by decide

theorem ten_thousand_closure_profile :
    inputFacts 1000 5 = 4000 ∧
    inputFacts 1000 5 + 1000 = 5000 ∧ closureRows 1000 5 = 10000 := by
  decide

/-- The branching control adds edges whose two-step witnesses already exist.
Both inputs therefore have the same transitive supersets and least closure.
The native benchmark independently checks every delivered row. -/
theorem redundant_shortcuts_preserve_closure {Vertex : Type}
    (base shortcut : Vertex → Vertex → Prop)
    (witness : ∀ a b, shortcut a b → ∃ mid, base a mid ∧ base mid b)
    (relation : Vertex → Vertex → Prop)
    (closed : ∀ a b c, relation a b → relation b c → relation a c) :
    (∀ a b, base a b → relation a b) ↔
      (∀ a b, base a b ∨ shortcut a b → relation a b) := by
  constructor
  · intro admitted a b edge
    rcases edge with regular | redundant
    · exact admitted a b regular
    · obtain ⟨mid, left, right⟩ := witness a b redundant
      exact closed a mid b (admitted a mid left) (admitted mid b right)
  · intro admitted a b edge
    exact admitted a b (.inl edge)

def affineField (first stride : Int) (index : Nat) : Int :=
  first + (index : Int) * stride

theorem affine_field_next (first stride : Int) (index : Nat) :
    affineField first stride (index + 1) = affineField first stride index + stride := by
  simp [affineField, Int.add_mul, Int.add_assoc]

/-- With positive stride the upper bound on the product and the upper bound
on the actual field give the last safe ordinal. Both lower bounds follow
from a nonnegative ordinal and an admitted first field. -/
theorem affine_positive_ordinal_bound (lo hi first stride index : Int)
    (zeroLo : lo ≤ 0) (firstLo : lo ≤ first)
    (positive : 0 < stride) (nonnegative : 0 ≤ index) :
    index ≤ min (hi / stride) ((hi - first) / stride) ↔
      (lo ≤ index * stride ∧ index * stride ≤ hi) ∧
        (lo ≤ first + index * stride ∧ first + index * stride ≤ hi) := by
  rw [Int.le_min, Int.le_ediv_iff_mul_le positive, Int.le_ediv_iff_mul_le positive]
  have product := Int.mul_nonneg nonnegative (Int.le_of_lt positive)
  omega

/-- For descending fields use the magnitude of the negative stride. The
asymmetric lower end of the fixnum range applies to both calculations. -/
theorem affine_negative_ordinal_bound (lo hi first stride index : Int)
    (hiZero : 0 ≤ hi) (firstHi : first ≤ hi)
    (negative : stride < 0) (nonnegative : 0 ≤ index) :
    index ≤ min ((-lo) / (-stride)) ((first - lo) / (-stride)) ↔
      (lo ≤ index * stride ∧ index * stride ≤ hi) ∧
        (lo ≤ first + index * stride ∧ first + index * stride ≤ hi) := by
  have positive : 0 < -stride := by omega
  rw [Int.le_min, Int.le_ediv_iff_mul_le positive, Int.le_ediv_iff_mul_le positive,
      Int.mul_neg]
  have product := Int.mul_nonpos_of_nonneg_of_nonpos nonnegative (Int.le_of_lt negative)
  omega

theorem affine_field_bounds (first stride : Int) (index last : Nat) (inside : index ≤ last) :
    min first (affineField first stride last) ≤ affineField first stride index ∧
      affineField first stride index ≤ max first (affineField first stride last) := by
  have hi : (index : Int) ≤ (last : Int) := Int.ofNat_le.mpr inside
  have lo : (0 : Int) ≤ index := Int.natCast_nonneg index
  by_cases positive : 0 ≤ stride
  · have nonneg := Int.mul_nonneg lo positive
    have ordered := Int.mul_le_mul_of_nonneg_right hi positive
    exact ⟨Int.le_trans (Int.min_le_left _ _) (by simp only [affineField]; omega),
      Int.le_trans (by simp only [affineField]; omega :
        affineField first stride index ≤ affineField first stride last) (Int.le_max_right _ _)⟩
  · have nonpos : stride ≤ 0 := by omega
    have nonposField := Int.mul_nonpos_of_nonneg_of_nonpos lo nonpos
    have ordered := Int.mul_le_mul_of_nonpos_right hi nonpos
    exact ⟨Int.le_trans (Int.min_le_right _ _) (by simp only [affineField]; omega),
      Int.le_trans (by simp only [affineField]; omega :
        affineField first stride index ≤ first) (Int.le_max_left _ _)⟩

section AffineExport

abbrev AffineRow := Int × Int

def affineRowAt (first stride : AffineRow) (ordinal : Nat) : AffineRow :=
  (affineField first.1 stride.1 ordinal, affineField first.2 stride.2 ordinal)

def precedingAffineRow (stride current : AffineRow) : AffineRow :=
  (current.1 - stride.1, current.2 - stride.2)

theorem preceding_affine_row_exact (first stride : AffineRow) (ordinal : Nat) :
    precedingAffineRow stride (affineRowAt first stride (ordinal + 1)) =
      affineRowAt first stride ordinal := by
  simp [precedingAffineRow, affineRowAt, affine_field_next]

def indexedAffineExport (first stride : AffineRow) : Nat → List AffineRow → List AffineRow
  | 0, tail => affineRowAt first stride 0 :: tail
  | n + 1, tail => indexedAffineExport first stride n (affineRowAt first stride (n + 1) :: tail)

def steppedAffineExport (stride : AffineRow) : Nat → AffineRow → List AffineRow → List AffineRow
  | 0, row, tail => row :: tail
  | n + 1, row, tail => steppedAffineExport stride n (precedingAffineRow stride row) (row :: tail)

/-- Moving the arithmetic to a carried cursor preserves the precise list
order, including the existing tail. The zero case emits without stepping. -/
theorem stepped_affine_export_exact (first stride : AffineRow) (last : Nat)
    (tail : List AffineRow) :
    steppedAffineExport stride last (affineRowAt first stride last) tail =
      indexedAffineExport first stride last tail := by
  induction last generalizing tail with
  | zero => rfl
  | succ n ih =>
    simp only [steppedAffineExport, indexedAffineExport, preceding_affine_row_exact]
    exact ih _

theorem indexed_affine_export_count (first stride : AffineRow) (last : Nat)
    (tail : List AffineRow) :
    (indexedAffineExport first stride last tail).length = last + 1 + tail.length := by
  induction last generalizing tail with
  | zero => simp [indexedAffineExport, Nat.add_comm]
  | succ n ih =>
    simp only [indexedAffineExport, ih, List.length_cons]
    omega

/-- Each decrement lands within the admitted ordinal interval. If both extrema
are within the fixnum range the destination is representable at either sign
of the stride, so a source-level wrapping subtraction agrees with subtraction. -/
theorem affine_decrement_fits (first stride lo hi : Int) (ordinal last : Nat)
    (inside : ordinal + 1 ≤ last)
    (startFits : lo ≤ first ∧ first ≤ hi)
    (endFits : lo ≤ affineField first stride last ∧ affineField first stride last ≤ hi) :
    lo ≤ affineField first stride (ordinal + 1) - stride ∧
      affineField first stride (ordinal + 1) - stride ≤ hi := by
  have ordered := affine_field_bounds first stride ordinal last (by omega)
  rw [affine_field_next, Int.add_sub_cancel]
  omega

/-- Source-level accounting for a nonempty export. The visit count is
arithmetic; the affine branch reads no stored row objects. -/
structure AffineExportWork where
  ordinals : Nat
  fieldMultiplications : Nat
  publishedConsCells : Nat
  deriving DecidableEq

def indexedAffineWork (last : Nat) : AffineExportWork :=
  ⟨last + 1, 2 * (last + 1), 3 * (last + 1)⟩

def steppedAffineWork (last : Nat) : AffineExportWork :=
  ⟨last + 1, 2, 3 * (last + 1)⟩

theorem stepped_affine_allocation_unchanged (last : Nat) :
    (steppedAffineWork last).publishedConsCells = (indexedAffineWork last).publishedConsCells := rfl

theorem stepped_affine_ordinal_work_unchanged (last : Nat) :
    (steppedAffineWork last).ordinals = (indexedAffineWork last).ordinals := rfl

theorem stepped_affine_avoids_per_row_multiplication (last : Nat) :
    (indexedAffineWork last).fieldMultiplications =
      (steppedAffineWork last).fieldMultiplications + 2 * last := by
  simp [indexedAffineWork, steppedAffineWork, Nat.mul_add, Nat.add_comm]

theorem affine_copy_row_step (first stride : AffineRow) (i : Nat) :
    affineRowAt first stride (i + 1) =
      ((affineRowAt first stride i).1 + stride.1, (affineRowAt first stride i).2 + stride.2) := by
  simp [affineRowAt, affine_field_next]

/-- A validated destination interval gives both fields of every ordinal
a distinct in-range address, even when the caller starts at an odd cell. -/
theorem affine_copy_cell_bounds (start count capacity i : Nat)
    (room : start + 2 * count ≤ capacity) (inside : i < count) :
    start + 2 * i < capacity ∧ start + 2 * i + 1 < capacity := by omega

theorem affine_copy_ordinals_disjoint (start a b : Nat) (before : a < b) :
    start + 2 * a + 1 < start + 2 * b := by omega

end AffineExport

section ProjectionCollector

/-- Three two-field objects per row: the outer cell and two row cells.
Each object has one header word. This footprint counts a complete,
reachable detached prefix once and excludes heap section and stack costs. -/
def projectionCopyWords (rows : Nat) : Nat := rows * (3 * (1 + 2))

-- The outer cdr contributes one fewer pointer than there are rows.
-- Each outer car and each first row cdr points to another cell.
def projectionPointerSlots (rows : Nat) : Nat := 2 * rows + (rows - 1)

-- One empty row tail and two immediate fields per row, plus the final
-- empty outer tail if the prefix is nonempty.
def projectionImmediateSlots (rows : Nat) : Nat :=
  3 * rows + (if rows = 0 then 0 else 1)

theorem projection_body_slots_exact (rows : Nat) :
    projectionPointerSlots rows + projectionImmediateSlots rows = 6 * rows := by
  cases rows with
  | zero => decide
  | succ n => simp [projectionPointerSlots, projectionImmediateSlots]; omega

theorem million_projection_word_counts :
    projectionCopyWords 1000000 = 9000000 ∧
      projectionPointerSlots 1000000 = 2999999 ∧
      projectionImmediateSlots 1000000 = 3000001 := by decide

/-- The exporter visits the ordinals backwards and prepends each result.
After a prefix of the visit order, the held list is the corresponding
suffix of the ordered public result. -/
theorem projection_accumulator_order {Row : Type} (rows : List Row) (emitted : Nat) :
    (rows.reverse.take emitted).reverse = rows.drop (rows.length - emitted) := by
  simp [List.reverse_take]

/-- The probe holds disjoint caller lists and an independently detached
accumulator. This counts their layout only, independently of GC timing
and module-owned metadata. -/
def projectionRootPairWords (inputLists retainedOutputRows : Nat) : Nat :=
  inputLists * projectionCopyWords 1000000 + projectionCopyWords retainedOutputRows

theorem projection_root_probe_extents :
    projectionRootPairWords 2 500000 = 22500000 ∧
    projectionRootPairWords 0 500000 = 4500000 ∧
    projectionRootPairWords 2 0 = 18000000 ∧
    projectionRootPairWords 1 500000 = 13500000 ∧
    projectionRootPairWords 2 1000000 = 27000000 := by decide

/-- A collection moved to the start of export observes an empty suffix.
Two independently held source lists still contribute their full extent.
This counts pair words and makes no assumption about the collector clock. -/
theorem moving_projection_collection_to_boundary (emitted : Nat) :
    projectionRootPairWords 2 emitted =
      projectionRootPairWords 2 0 + projectionCopyWords emitted := by
  simp [projectionRootPairWords, projectionCopyWords]

/-- When the remaining request work stays fixed, moving a collection can
cross a strict bound only by saving more than the original excess.
The two collection clocks must come from observations or separate premises. -/
theorem projection_boundary_needs_pause_saving (bound remaining oldPause newPause : Nat)
    (oldMiss : bound ≤ remaining + oldPause)
    (newPass : remaining + newPause < bound) :
    remaining + oldPause - bound < oldPause - newPause := by omega

/-- Removing a duplicate route to a live object does not remove any
objects from the collector's reachable set. The premise must follow from
another live owner, such as the benchmark's independent caller references. -/
theorem redundant_projection_root_no_reachable_saving {Root Object : Type}
    (reaches : Root → Object → Prop) (live : Root → Prop) (extra : Root)
    (covered : ∀ obj, reaches extra obj → ∃ root, live root ∧ reaches root obj)
    (obj : Object) :
    (∃ root, (live root ∨ root = extra) ∧ reaches root obj) ↔
      (∃ root, live root ∧ reaches root obj) := by
  constructor
  · rintro ⟨root, available, reachable⟩
    rcases available with owned | rfl
    · exact ⟨root, owned, reachable⟩
    · exact covered obj reachable
  · rintro ⟨root, owned, reachable⟩
    exact ⟨root, Or.inl owned, reachable⟩

/-- The affine slot's ordered promise forces its newest-first lane
before reversing the outer list. Reversal shares each inner row. -/
def affineFallbackPairWords (rows : Nat) (newestForced orderedForced : Bool) : Nat :=
  (if newestForced || orderedForced then projectionCopyWords rows else 0) +
    (if orderedForced then 3 * rows else 0)

theorem affine_views_leave_fallback_unforced (rows : Nat) :
    affineFallbackPairWords rows false false = 0 := rfl

theorem affine_ordered_fallback_shares_row_cells (rows : Nat) (newestForced : Bool) :
    affineFallbackPairWords rows newestForced true = projectionCopyWords rows + 3 * rows := by
  simp [affineFallbackPairWords]

end ProjectionCollector

section FunctionalOriginOwnership

/-- The origin constructor only accepts nonnegative fixnum labels. The
offered interval covers all assigned labels and reserves distinct slots
for distinct labels. Holes in the private lane carry the absent sentinel. -/
theorem functional_origin_slot (first extent label : Nat)
    (within : first ≤ label ∧ label < first + extent) :
    label - first < extent ∧ first + (label - first) = label := by omega

/-- The signed lane lookup implements the old origin map when the filled
interval represents its entries and the map has no entry outside it. -/
theorem dense_origin_lookup_exact (first extent : Nat) (lane old : Nat → Option Nat)
    (inside : ∀ i, i < extent → lane i = old (first + i))
    (outside : ∀ key, ¬ (first ≤ key ∧ key < first + extent) → old key = none)
    (key : Nat) :
    (if first ≤ key ∧ key < first + extent then lane (key - first) else none) = old key := by
  by_cases covered : first ≤ key ∧ key < first + extent
  · obtain ⟨fits, exactLabel⟩ := functional_origin_slot first extent key covered
    simp [covered, inside _ fits, exactLabel]
  · simp [covered, outside key covered]

/-- Replacing a published hash lookup by the same private origin ordinals
does not change a subsequent successor walk or its delivery order. -/
theorem functional_origin_replacement (hashLookup search : Nat → Option Nat)
    (walk : Option Nat → List Row) (same : ∀ key, search key = hashLookup key) (key : Nat) :
    walk (search key) = walk (hashLookup key) := by rw [same]

theorem recursive_root_probe_pair_words :
    2 * projectionCopyWords (inputFacts 128 128) = 292608 ∧
    projectionCopyWords (closureRows 128 128 / 2) = 4681728 := by decide

end FunctionalOriginOwnership

/-- The packed solver records a fresh candidate at the end of a private lane.
Walking that lane backward is exactly the worker's prepended delta, including
the effect of discarding duplicate witnesses while visiting them in order. -/
theorem recorded_frontier_exact {Row : Type} [DecidableEq Row]
    (candidates : List Row) (seen recorded : List Row) :
    (candidates.foldl (fun (state : List Row × List Row) row =>
      if row ∈ state.1 then state else (row :: state.1, state.2 ++ [row]))
      (seen, recorded)).2.reverse =
    (candidates.foldl (fun (state : List Row × List Row) row =>
      if row ∈ state.1 then state else (row :: state.1, row :: state.2))
      (seen, recorded.reverse)).2 := by
  induction candidates generalizing seen recorded with
  | nil => rfl
  | cons row rest ih =>
    simp only [List.foldl_cons]
    by_cases present : row ∈ seen
    · simpa only [present, ite_true] using ih seen recorded
    · simpa only [present, ite_false, List.reverse_append, List.reverse_singleton,
        List.singleton_append] using ih (row :: seen) (recorded ++ [row])

/-- Restricting an ordered join round to one independent region retains its
candidate order. The premise must cover every occurrence in the actual
adjacency bucket, including duplicates. -/
theorem regional_candidates_exact {Row : Type}
    (selectRow : Row → Bool) (extend : Row → List Row)
    (closed : ∀ origin row, row ∈ extend origin → selectRow row = selectRow origin)
    (delta : List Row) :
    (delta.flatMap extend).filter selectRow = (delta.filter selectRow).flatMap extend := by
  induction delta with
  | nil => rfl
  | cons origin delta ih =>
    have allFiltered (rows : List Row)
        (hom : ∀ row ∈ rows, selectRow row = selectRow origin) :
        rows.filter selectRow = if selectRow origin then rows else [] := by
      induction rows with
      | nil => split <;> rfl
      | cons row rest tail =>
        have same := hom row (by simp)
        have selected := tail (fun value present => hom value (by simp [present]))
        by_cases keep : selectRow origin <;> simp [same, selected, keep]
    have select := allFiltered (extend origin) (closed origin)
    simp only [List.flatMap_cons, List.filter_append, List.filter_cons]
    rw [select, ih]
    by_cases keep : selectRow origin <;> simp [keep]

/-- Replaying an unchanged prefix's accepted children in its new global
position preserves the entire wave. Merely concatenating complete regions
would change the order when their prefix occurrences interleave. -/
theorem replay_children_in_prefix_order {Row : Type}
    (prefixes : List Row) (changed : Row → Bool)
    (current retained recomputed : Row → List Row)
    (retainedExact : ∀ row ∈ prefixes, changed row = false → retained row = current row)
    (recomputedExact : ∀ row ∈ prefixes, changed row = true → recomputed row = current row) :
    prefixes.flatMap (fun row => if changed row then recomputed row else retained row) =
      prefixes.flatMap current := by
  induction prefixes with
  | nil => rfl
  | cons row rest ih =>
    have tail := ih
      (fun child present => retainedExact child (by simp [present]))
      (fun child present => recomputedExact child (by simp [present]))
    simp only [List.flatMap_cons, tail]
    cases dirty : changed row with
    | false => simp [retainedExact row (by simp) dirty]
    | true => simp [recomputedExact row (by simp) dirty]

/-- Membership, uniqueness and exact cardinality establish complete coverage.
The native oracle must establish all three against its independent universe. -/
theorem complete_oracle {Row : Type} (observed expected : List Row)
    (unique : observed.Nodup) (members : observed ⊆ expected)
    (count : observed.length = expected.length) : expected ⊆ observed := by
  classical
  intro row member
  by_cases found : row ∈ observed
  · exact found
  have absent := found
  apply False.elim
  have extended : (row :: observed).Nodup := List.nodup_cons.mpr ⟨absent, unique⟩
  have included : row :: observed ⊆ expected := by
    intro value inside
    rcases List.mem_cons.mp inside with same | old
    · subst value; exact member
    · exact members old
  have bound := extended.length_le_of_subset included
  simp only [List.length_cons] at bound
  omega

/-- A width-indexed bitmap may encode distinct columns only within that width. -/
def bitmapIndex (width left right : Nat) : Nat := left * width + right

theorem bitmap_index_injective (width left right otherLeft otherRight : Nat)
    (rightBound : right < width) (otherBound : otherRight < width)
    (same : bitmapIndex width left right = bitmapIndex width otherLeft otherRight) :
    left = otherLeft ∧ right = otherRight := by
  have positive : 0 < width := Nat.zero_lt_of_lt rightBound
  have divide := congrArg (fun n => n / width) same
  have remainder := congrArg (fun n => n % width) same
  have quotient (a b : Nat) (bound : b < width) : (a * width + b) / width = a := by
    rw [Nat.add_comm, Nat.add_mul_div_right b a positive, Nat.div_eq_of_lt bound]
    exact Nat.zero_add a
  change (left * width + right) / width = (otherLeft * width + otherRight) / width at divide
  rw [quotient left right rightBound, quotient otherLeft otherRight otherBound] at divide
  simp [bitmapIndex, Nat.add_mod, Nat.mod_eq_of_lt rightBound,
    Nat.mod_eq_of_lt otherBound] at remainder
  exact ⟨divide, remainder⟩

/-- Translate signed labels only after the absolute interval check. -/
theorem oracle_offset_bounds (offset span left right : Int) :
    (offset ≤ left ∧ left < right ∧ right < offset + span) ↔
      (0 ≤ left - offset ∧ left - offset < right - offset ∧ right - offset < span) := by
  omega

/-- One forward step stays in a chain exactly when the origin has an
unused column to its right. This is the projection specialization. -/
theorem projection_successor_group (width left : Nat) (positive : 0 < width) :
    left / width = (left + 1) / width ↔ left % width + 1 < width := by
  let q := left / width
  let r := left % width
  have leftEq : left = r + width * q := (Nat.mod_add_div left width).symm
  have targetEq : left + 1 = (r + 1) + q * width := by
    rw [leftEq, Nat.mul_comm width q]
    omega
  have targetGroup : (left + 1) / width = (r + 1) / width + q := by
    rw [targetEq, Nat.add_mul_div_right _ _ positive]
  change q = (left + 1) / width ↔ r + 1 < width
  rw [targetGroup]
  rw [show (q = (r + 1) / width + q) ↔ (r + 1) / width = 0 by omega]
  exact Nat.div_eq_zero_iff_lt positive

/-- A projected row is determined by its left label. Therefore its
duplicate slot needs only the left ordinal, irrespective of row order. -/
theorem projection_slot_exact (left right otherLeft otherRight : Nat)
    (successor : right = left + 1) (otherSuccessor : otherRight = otherLeft + 1) :
    left = otherLeft ↔ (left, right) = (otherLeft, otherRight) := by
  constructor
  · intro same
    subst otherLeft
    rw [successor, otherSuccessor]
  · exact congrArg Prod.fst

theorem width_two_projection_origin (left : Nat) :
    left % 2 + 1 < 2 ↔ left % 2 = 0 := by omega

theorem width_two_projection_slot (left otherLeft : Nat)
    (even : left % 2 = 0) (otherEven : otherLeft % 2 = 0) :
    left / 2 = otherLeft / 2 ↔ left = otherLeft := by omega

/-- The prepared recursive bound for an origin is the first label of
the next chain. A forward target below that bound is in the same chain. -/
theorem recursive_target_bound (width left right : Nat)
    (positive : 0 < width) (forward : left ≤ right) :
    right < (left / width + 1) * width ↔ left / width = right / width := by
  rw [← Nat.div_lt_iff_lt_mul positive]
  have ordered : left / width ≤ right / width := Nat.div_le_div_right forward
  omega

theorem recursive_gap_slot_exact (width left right otherLeft otherRight : Nat)
    (forward : left ≤ right) (otherForward : otherLeft ≤ otherRight)
    (gap : right - left < width) (otherGap : otherRight - otherLeft < width) :
    bitmapIndex width left (right - left) = bitmapIndex width otherLeft (otherRight - otherLeft)
      ↔ (left, right) = (otherLeft, otherRight) := by
  constructor
  · intro same
    obtain ⟨origin, distance⟩ := bitmap_index_injective width left (right - left)
      otherLeft (otherRight - otherLeft) gap otherGap same
    have target : right = otherRight := by omega
    rw [origin, target]
  · intro same
    have origin := congrArg Prod.fst same
    have target := congrArg Prod.snd same
    simp only at origin target
    rw [origin, target]

/-- Filling the existing bitmap leaves every legal slot with exactly
the value produced by allocating a new zeroed bitmap. -/
theorem oracle_bitmap_reset (previous : List UInt8) (slot : Nat) :
    (previous.map (fun _ => (0 : UInt8)))[slot]? =
      (List.replicate previous.length (0 : UInt8))[slot]? := by
  have reset : previous.map (fun _ => (0 : UInt8)) =
      List.replicate previous.length (0 : UInt8) := by
    induction previous with
    | nil => rfl
    | cons _ _ ih => simp [List.replicate_succ, ih]
  rw [reset]

structure DataEvidence where
  inputFacts : Nat
  exportedRows : Nat
  requests : Nat
  unit : RuntimeMeasurement.Unit

def MillionData (e : DataEvidence) : Prop :=
  1000000 ≤ e.inputFacts ∨ 1000000 ≤ e.exportedRows

theorem million_messages_do_not_establish_million_data :
    ¬ MillionData ⟨0, 0, 1000000, .sessionState⟩ := by
  simp [MillionData]

theorem state_reply_cannot_certify_complete_query
    (e : RuntimeMeasurement.Evidence) (state : e.unit = .sessionState) (bound : Nat) :
    ¬ RuntimeMeasurement.Admitted .relationRun bound e := by
  apply RuntimeMeasurement.different_units_rejected
  simp [state]

/-! Ordered witnesses for the guarded linear rule
`reach(x,z) <- deltaReach(x,y), edge(y,z)`. The bucket contract must hold
for the same static source root until the assignment ends. -/
abbrev BinaryRow (Vertex : Type) := Vertex × Vertex
abbrev JoinWitness (Vertex : Type) := BinaryRow Vertex × BinaryRow Vertex

def scanWitnesses [DecidableEq Vertex] (delta edges : List (BinaryRow Vertex)) :
    List (JoinWitness Vertex) :=
  delta.flatMap fun row =>
    (edges.filter fun edge => decide (edge.1 = row.2)).map (fun edge => (row, edge))

def indexedWitnesses (delta : List (BinaryRow Vertex)) (bucket : Vertex → List (BinaryRow Vertex)) :
    List (JoinWitness Vertex) :=
  delta.flatMap fun row => (bucket row.2).map (fun edge => (row, edge))

/-- Preserve matching order and witness multiplicity, even where several
witnesses derive one output or a source row occurs more than once. -/
theorem indexed_witnesses_exact [DecidableEq Vertex]
    (delta edges : List (BinaryRow Vertex)) (bucket : Vertex → List (BinaryRow Vertex))
    (exactBucket : ∀ key, bucket key = edges.filter fun edge => decide (edge.1 = key)) :
    indexedWitnesses delta bucket = scanWitnesses delta edges := by
  simp only [indexedWitnesses, scanWitnesses, exactBucket]

/-- The source accessor can return an exact index bucket or the entire
small source. The fused reader still checkpoints and matches each visit. -/
theorem routed_witnesses_exact [DecidableEq Vertex]
    (delta edges : List (BinaryRow Vertex)) (rows : Vertex → List (BinaryRow Vertex))
    (exactAfterMatch : ∀ key, (rows key).filter (fun edge => decide (edge.1 = key)) =
      edges.filter (fun edge => decide (edge.1 = key))) :
    indexedWitnesses delta (fun key => (rows key).filter (fun edge => decide (edge.1 = key))) =
      scanWitnesses delta edges :=
  indexed_witnesses_exact delta edges _ exactAfterMatch

def indexedVisits (delta : List (BinaryRow Vertex)) (bucket : Vertex → List (BinaryRow Vertex)) : Nat :=
  (delta.map fun row => (bucket row.2).length).sum

/-- The indexed traversal visits precisely the sum of matching bucket sizes.
One probe per delta row, index construction, novelty and yield remain separate. -/
theorem indexed_visits_exact (delta : List (BinaryRow Vertex))
    (bucket : Vertex → List (BinaryRow Vertex)) :
    (indexedWitnesses delta bucket).length = indexedVisits delta bucket := by
  induction delta with
  | nil => rfl
  | cons row tail ih =>
      simp only [indexedWitnesses, List.flatMap_cons, List.length_append, List.length_map,
        indexedVisits, List.map_cons, List.sum_cons] at *
      rw [ih]

/-! The retained scalar index stores a single row directly. Its list-returning
reader builds a singleton spine on every singleton hit. The ordered delta
reader can instead visit the entry itself. -/
inductive SourceBucket (Row : Type) where
  | missing | single (row : Row) | many (rows : List Row)

def sourceBucketRows : SourceBucket Row → List Row
  | .missing => []
  | .single row => [row]
  | .many rows => rows

def visitSourceBucket (visit : State → Row → State) (initial : State) : SourceBucket Row → State
  | .missing => initial
  | .single row => visit initial row
  | .many rows => rows.foldl visit initial

/-- The state can include the checkpoint, work count, ordered witness trace
and an absorbing refusal. The visit protocol removes only the singleton spine. -/
theorem source_bucket_visit_exact (visit : State → Row → State) (initial : State)
    (bucket : SourceBucket Row) :
    visitSourceBucket visit initial bucket = (sourceBucketRows bucket).foldl visit initial := by
  cases bucket <;> rfl

def singletonSpines (reads : List (SourceBucket Row)) : Nat :=
  (reads.filter (fun bucket => match bucket with | .single _ => true | _ => false)).length

theorem singleton_spines_exact (reads : List (SourceBucket Row)) :
    singletonSpines reads = (reads.map (fun bucket => match bucket with
      | .single _ => 1 | _ => 0)).sum := by
  induction reads with
  | nil => rfl
  | cons bucket rest ih => cases bucket <;> simp_all [singletonSpines, Nat.add_comm]

def detachNewestFirst (copyRow : Row → Detached) (rows : List Row) (tail : List Detached) :
    List Detached :=
  rows.foldl (fun acc row => copyRow row :: acc) tail

/-- An immutable newest-first root needs no ordered intermediate spine for a
complete export. The caller still receives a fresh outer cell and a detached
row at each occurrence, including duplicates. -/
theorem detach_newest_first_exact (copyRow : Row → Detached) (rows : List Row)
    (tail : List Detached) :
    detachNewestFirst copyRow rows tail = rows.reverse.map copyRow ++ tail := by
  induction rows generalizing tail with
  | nil => rfl
  | cons row rest ih =>
    simp only [detachNewestFirst, List.foldl_cons] at ih ⊢
    rw [ih]
    simp [List.reverse_cons]

/-- In a functional input graph, the complete frontier from one start has
at most one endpoint at each distance. A strict rank excludes duplicates
between distances without an output-sized pair membership table. -/
def successorAt (next : Vertex → Option Vertex) (start : Vertex) : Nat → Option Vertex
  | 0 => some start
  | n + 1 => (successorAt next start n).bind next

theorem successor_at_add (next : Vertex → Option Vertex) (start : Vertex) (i j : Nat) :
    successorAt next start (i + j) =
      (successorAt next start i).bind (fun node => successorAt next node j) := by
  induction j with
  | zero => cases successorAt next start i <;> simp [successorAt]
  | succ j ih =>
    rw [Nat.add_succ, successorAt, ih]
    cases successorAt next start i <;> rfl

theorem successor_rank_mono (next : Vertex → Option Vertex) (rank : Vertex → Nat)
    (rising : ∀ source target, next source = some target → rank source < rank target)
    (start : Vertex) (n : Nat) {endpoint : Vertex}
    (found : successorAt next start n = some endpoint) : rank start ≤ rank endpoint := by
  induction n generalizing endpoint with
  | zero =>
    have same : start = endpoint := by simpa [successorAt] using found
    simp [same]
  | succ n ih =>
    cases prior : successorAt next start n with
    | none => simp [successorAt, prior] at found
    | some middle =>
      have edge : next middle = some endpoint := by simpa [successorAt, prior] using found
      exact Nat.le_trans (ih prior) (Nat.le_of_lt (rising middle endpoint edge))

theorem successor_rank_strict (next : Vertex → Option Vertex) (rank : Vertex → Nat)
    (rising : ∀ source target, next source = some target → rank source < rank target)
    (start : Vertex) {n : Nat} {endpoint : Vertex} (nonempty : 0 < n)
    (found : successorAt next start n = some endpoint) : rank start < rank endpoint := by
  cases n with
  | zero => omega
  | succ n =>
    cases prior : successorAt next start n with
    | none => simp [successorAt, prior] at found
    | some middle =>
      have edge : next middle = some endpoint := by simpa [successorAt, prior] using found
      exact Nat.lt_of_le_of_lt (successor_rank_mono next rank rising start n prior)
        (rising middle endpoint edge)

theorem successor_distance_no_repeat (next : Vertex → Option Vertex) (rank : Vertex → Nat)
    (rising : ∀ source target, next source = some target → rank source < rank target)
    (start : Vertex) {i j : Nat} {first second : Vertex} (earlier : i < j)
    (atI : successorAt next start i = some first) (atJ : successorAt next start j = some second) :
    first ≠ second := by
  have rest : successorAt next first (j - i) = some second := by
    have total : i + (j - i) = j := Nat.add_sub_of_le (Nat.le_of_lt earlier)
    rw [← total, successor_at_add, atI] at atJ
    exact atJ
  have grows := successor_rank_strict next rank rising first (by omega : 0 < j - i) rest
  intro equal
  simp [equal] at grows

def successorRows (next : Vertex → Option Vertex) (origins : List Vertex) (depth : Nat) :
    List (Vertex × Vertex) :=
  origins.filterMap (fun origin => (successorAt next origin depth).map (fun endpoint => (origin, endpoint)))

def extendSuccessorRows (next : Vertex → Option Vertex) (rows : List (Vertex × Vertex)) :
    List (Vertex × Vertex) :=
  rows.filterMap (fun (origin, endpoint) => (next endpoint).map (fun target => (origin, target)))

/-- A deterministic one-successor probe extends the ordered frontier without
reordering surviving origins. The native worker reverses each staged round. -/
theorem successor_rows_step (next : Vertex → Option Vertex) (origins : List Vertex) (depth : Nat) :
    extendSuccessorRows next (successorRows next origins depth) =
      successorRows next origins (depth + 1) := by
  induction origins with
  | nil => rfl
  | cons origin rest ih =>
    cases found : successorAt next origin depth with
    | none => simpa [successorRows, extendSuccessorRows, successorAt, found] using ih
    | some endpoint =>
      cases edge : next endpoint <;>
        simp_all [successorRows, extendSuccessorRows, successorAt]

theorem successor_rows_member (next : Vertex → Option Vertex) (origins : List Vertex) (depth : Nat)
    {origin endpoint : Vertex} (present : (origin, endpoint) ∈ successorRows next origins depth) :
    origin ∈ origins ∧ successorAt next origin depth = some endpoint := by
  rcases List.mem_filterMap.mp present with ⟨source, inside, matched⟩
  cases found : successorAt next source depth with
  | none => simp [found] at matched
  | some target =>
    have eq : source = origin ∧ target = endpoint := by simpa [found] using matched
    rcases eq with ⟨rfl, rfl⟩
    exact ⟨inside, found⟩

theorem successor_rows_unique (next : Vertex → Option Vertex) (origins : List Vertex)
    (depth : Nat) (distinct : origins.Nodup) : (successorRows next origins depth).Nodup := by
  induction origins with
  | nil => simp [successorRows]
  | cons origin rest ih =>
    obtain ⟨fresh, unique⟩ := List.nodup_cons.mp distinct
    cases found : successorAt next origin depth with
    | none => simpa [successorRows, found] using ih unique
    | some endpoint =>
      have absent : (origin, endpoint) ∉ successorRows next rest depth :=
        fun present => fresh (successor_rows_member next rest depth present).1
      simpa [successorRows, found] using List.nodup_cons.mpr ⟨absent, ih unique⟩

theorem successor_rows_disjoint (next : Vertex → Option Vertex) (rank : Vertex → Nat)
    (rising : ∀ source target, next source = some target → rank source < rank target)
    (origins : List Vertex) {i j : Nat} (earlier : i < j) (row : Vertex × Vertex)
    (old : row ∈ successorRows next origins i) : row ∉ successorRows next origins j := by
  intro recent
  exact successor_distance_no_repeat next rank rising row.1 earlier
    (successor_rows_member next origins i old).2
    (successor_rows_member next origins j recent).2 rfl

/-- The worker emits in visit order and prepends into the next delta. The
ordered publication therefore depends on the reversal at every depth. -/
def emittedFrontiers (next : Vertex → Option Vertex) (rows : List (BinaryRow Vertex)) :
    Nat → List (List (BinaryRow Vertex))
  | 0 => []
  | n + 1 => rows :: emittedFrontiers next (extendSuccessorRows next rows.reverse) n

/-- The depth and orientation determine the same observable order from
the immutable source root, without referring to stored intermediate pairs. -/
def successorFrontiers (next : Vertex → Option Vertex) (origins : List Vertex)
    (depth : Nat) (reversed : Bool) : Nat → List (List (BinaryRow Vertex))
  | 0 => []
  | n + 1 =>
    (if reversed then (successorRows next origins depth).reverse
     else successorRows next origins depth) ::
      successorFrontiers next origins (depth + 1) (!reversed) n

theorem extend_successor_rows_reverse (next : Vertex → Option Vertex)
    (rows : List (BinaryRow Vertex)) :
    extendSuccessorRows next rows.reverse = (extendSuccessorRows next rows).reverse := by
  simp [extendSuccessorRows, List.filterMap_reverse]

theorem successor_frontiers_exact (next : Vertex → Option Vertex) (origins : List Vertex)
    (depths depth : Nat) (reversed : Bool) :
    emittedFrontiers next
      (if reversed then (successorRows next origins depth).reverse
       else successorRows next origins depth) depths =
      successorFrontiers next origins depth reversed depths := by
  induction depths generalizing depth reversed with
  | zero => rfl
  | succ n ih =>
    cases reversed <;>
      simp [emittedFrontiers, successorFrontiers, extend_successor_rows_reverse,
        successor_rows_step]
    · simpa using ih (depth + 1) true
    · simpa using ih (depth + 1) false

/-- A checked suffix-length table counts visits without materializing the
endpoints. The edge recurrence rules out skipping reachable depths. -/
theorem successor_at_exists_iff (next : Vertex → Option Vertex) (distance : Vertex → Nat)
    (terminal : ∀ source, next source = none → distance source = 0)
    (edge : ∀ source target, next source = some target → distance source = distance target + 1)
    (source : Vertex) (depth : Nat) :
    (∃ target, successorAt next source depth = some target) ↔ depth ≤ distance source := by
  induction depth generalizing source with
  | zero => simp [successorAt]
  | succ n ih =>
    have first : successorAt next source (n + 1) =
        (next source).bind (fun target => successorAt next target n) := by
      rw [show n + 1 = 1 + n by omega, successor_at_add]
      simp [successorAt]
    rw [first]
    cases found : next source with
    | none => simp [terminal source found]
    | some target => simpa [edge source target found] using ih target

theorem successor_rows_length_exact (next : Vertex → Option Vertex) (distance : Vertex → Nat)
    (terminal : ∀ source, next source = none → distance source = 0)
    (edge : ∀ source target, next source = some target → distance source = distance target + 1)
    (origins : List Vertex) (depth : Nat) :
    (successorRows next origins depth).length =
      (origins.filter (fun source => decide (depth ≤ distance source))).length := by
  induction origins with
  | nil => rfl
  | cons origin rest ih =>
    have existsAt := successor_at_exists_iff next distance terminal edge origin depth
    cases found : successorAt next origin depth with
    | none =>
      have absent : ¬ depth ≤ distance origin := by simpa [found] using existsAt
      simpa [successorRows, found, absent] using ih
    | some target =>
      have present : depth ≤ distance origin := existsAt.mp ⟨target, found⟩
      simpa [successorRows, found, present] using congrArg Nat.succ ih

/-- The work stack unwinds exactly the prefix traversed to a cached
endpoint. Each pop charges one edge and maintains the length recurrence. -/
theorem successor_memo_length (next : Vertex → Option Vertex) (distance : Vertex → Nat)
    (edge : ∀ source target, next source = some target → distance source = distance target + 1)
    (source : Vertex) (depth : Nat) {endpoint : Vertex}
    (found : successorAt next source depth = some endpoint) :
    distance source = distance endpoint + depth := by
  induction depth generalizing endpoint with
  | zero =>
    have same : source = endpoint := by simpa [successorAt] using found
    simp [same]
  | succ n ih =>
    cases prior : successorAt next source n with
    | none => simp [successorAt, prior] at found
    | some middle =>
      have advanced : next middle = some endpoint := by simpa [successorAt, prior] using found
      have prefixLength := ih prior
      have lastLength := edge middle endpoint advanced
      omega

/-- The forward cursor writes at or behind the last visited slot. The
reverse cursor writes at or above it. Each write leaves the next reads
unchanged for both packed cursor vectors. -/
theorem forward_compaction_preserves_unread (rows : List Row) (updated : Row)
    (write read : Nat) (behind : write ≤ read) :
    (rows.set write updated).drop (read + 1) = rows.drop (read + 1) := by
  simp [List.drop_set, Nat.lt_succ_of_le behind]

theorem reverse_compaction_preserves_unread (rows : List Row) (updated : Row)
    (write read : Nat) (behind : read ≤ write) :
    (rows.set write updated).take read = rows.take read := by
  rw [List.take_set, List.set_eq_of_length_le (Nat.le_trans (List.length_take_le read rows) behind)]

def suffixCounts (distance : Vertex → Nat) (origins : List Vertex) : Nat → Nat
  | 0 => 0
  | n + 1 =>
    (origins.filter (fun source => decide (n + 1 ≤ distance source))).length +
      suffixCounts distance origins n

/-- Counting by origin with cached suffix lengths charges the same number
of rows as counting all emitted frontiers up to the same maximum depth. -/
theorem suffix_counts_by_origin (distance : Vertex → Nat) (origins : List Vertex)
    (depth : Nat) :
    suffixCounts distance origins depth =
      (origins.map (fun origin => min depth (distance origin))).sum := by
  have peel (origin : Vertex) (rest : List Vertex) (limit : Nat) :
      suffixCounts distance (origin :: rest) limit =
        min limit (distance origin) + suffixCounts distance rest limit := by
    induction limit with
    | zero => simp [suffixCounts]
    | succ n ih =>
      simp only [suffixCounts, ih, List.filter_cons]
      by_cases present : n + 1 ≤ distance origin
      · simp [present] <;> omega
      · simp [present] <;> omega
  induction origins with
  | nil => induction depth with
    | zero => rfl
    | succ n ih => simp [suffixCounts, ih]
  | cons origin rest ih => simp [peel, ih]

def shiftOrdinal (backward : Bool) (origin : Int) (hops : Nat) : Int :=
  if backward then origin - Int.ofNat hops else origin + Int.ofNat hops

def ordinalLink (lo hi : Int) (backward : Bool) (origin : Int) : Option Int :=
  let next := shiftOrdinal backward origin 1
  if lo ≤ next ∧ next < hi then some next else none

/-- In a contiguous ordinal run, the final slot also certifies every
intermediate slot. The export still indexes the stored labels. -/
theorem ordinal_run_reaches (lo hi origin : Int) (backward : Bool) (hops : Nat)
    (inside : lo ≤ origin ∧ origin < hi)
    (endsInside : lo ≤ shiftOrdinal backward origin hops ∧
      shiftOrdinal backward origin hops < hi) :
    successorAt (ordinalLink lo hi backward) origin hops =
      some (shiftOrdinal backward origin hops) := by
  induction hops with
  | zero => cases backward <;> simp [successorAt, shiftOrdinal]
  | succ n ih =>
    have previous : lo ≤ shiftOrdinal backward origin n ∧ shiftOrdinal backward origin n < hi := by
      cases backward <;> simp [shiftOrdinal] at endsInside ⊢ <;> omega
    have moved :
        shiftOrdinal backward (shiftOrdinal backward origin n) 1 =
          shiftOrdinal backward origin (n + 1) := by
      cases backward <;> simp [shiftOrdinal] <;> omega
    rw [successorAt, ih previous]
    simp [ordinalLink, moved, endsInside]

theorem ordinal_run_no_cross (lo hi origin : Int) (backward : Bool) (hops : Nat)
    (inside : lo ≤ origin ∧ origin < hi) :
    ∀ endpoint, successorAt (ordinalLink lo hi backward) origin hops = some endpoint →
      lo ≤ endpoint ∧ endpoint < hi := by
  cases hops with
  | zero =>
    intro endpoint reached
    have same : origin = endpoint := by simpa [successorAt] using reached
    simpa [← same] using inside
  | succ n =>
    intro endpoint reached
    cases previous : successorAt (ordinalLink lo hi backward) origin n with
    | none => simp [successorAt, previous] at reached
    | some middle =>
      have advancing : ordinalLink lo hi backward middle = some endpoint := by
        simpa [successorAt, previous] using reached
      by_cases valid : lo ≤ shiftOrdinal backward middle 1 ∧ shiftOrdinal backward middle 1 < hi
      · have same : shiftOrdinal backward middle 1 = endpoint := by
          simpa [ordinalLink, valid] using advancing
        simpa [← same] using valid
      · simp [ordinalLink, valid] at advancing

theorem ordinal_run_endpoint (lo hi origin : Int) (backward : Bool) (hops : Nat)
    {endpoint : Int} (found : successorAt (ordinalLink lo hi backward) origin hops = some endpoint) :
    endpoint = shiftOrdinal backward origin hops := by
  induction hops generalizing endpoint with
  | zero => simpa [successorAt, shiftOrdinal] using found.symm
  | succ n ih =>
    cases previous : successorAt (ordinalLink lo hi backward) origin n with
    | none => simp [successorAt, previous] at found
    | some middle =>
      have advancing : ordinalLink lo hi backward middle = some endpoint := by
        simpa [successorAt, previous] using found
      by_cases valid : lo ≤ shiftOrdinal backward middle 1 ∧ shiftOrdinal backward middle 1 < hi
      · have current : middle = shiftOrdinal backward origin n := ih previous
        have next : endpoint = shiftOrdinal backward middle 1 := by
          simpa [ordinalLink, valid] using advancing.symm
        cases backward <;> simp [shiftOrdinal] at current next ⊢ <;> omega
      · simp [ordinalLink, valid] at advancing

/-- The half-open origin window used by the native exporter contains
exactly the rows that survive this depth of the cursor traversal. -/
theorem ordinal_run_origin_window (lo hi origin : Int) (backward : Bool) (hops : Nat)
    (inside : lo ≤ origin ∧ origin < hi) :
    (∃ endpoint, successorAt (ordinalLink lo hi backward) origin hops = some endpoint) ↔
      (if backward then lo + Int.ofNat hops ≤ origin ∧ origin < hi
       else lo ≤ origin ∧ origin < hi - Int.ofNat hops) := by
  constructor
  · rintro ⟨endpoint, found⟩
    have finalBounds := ordinal_run_no_cross lo hi origin backward hops inside endpoint found
    rw [ordinal_run_endpoint lo hi origin backward hops found] at finalBounds
    cases backward <;> simp [shiftOrdinal] at finalBounds ⊢ <;> omega
  · intro within
    have endsInside : lo ≤ shiftOrdinal backward origin hops ∧ shiftOrdinal backward origin hops < hi := by
      cases backward <;> simp [shiftOrdinal] at within ⊢ <;> omega
    exact ⟨_, ordinal_run_reaches lo hi origin backward hops inside endsInside⟩

/-- The native list export prepends rows as rounds emit them. A visitor
can deliver that public sequence directly by reversing rounds, runs
within each round, and rows within each run. -/
theorem ordinal_visit_public_order (rounds : List (List (List Row))) :
    (rounds.reverse.map (fun runs => (runs.reverse.map List.reverse).flatten)).flatten =
      ((rounds.map List.flatten).flatten).reverse := by
  simp only [List.reverse_flatten, List.map_reverse, List.map_map, Function.comp_def]

/-- A depth-by-run visitor is selected only when its cursor checks are
within twice the result cardinality. This is an algorithmic guard,
independent of time and heap accounting. -/
theorem ordinal_visit_scan_room (depths runs reported visits : Nat)
    (checked : visits ≤ depths * runs) (admitted : depths * runs ≤ 2 * reported) :
    visits ≤ 2 * reported := Nat.le_trans checked admitted

def orderedOriginsFrom (ascending : Bool) (prior : Int) : List (Int × Value) → Prop
  | [] => True
  | row :: rows =>
    (if ascending then prior < row.1 else row.1 < prior) ∧
      orderedOriginsFrom ascending row.1 rows

theorem ordered_origin_distance (ascending : Bool) (prior : Int)
    (rows : List (Int × Value)) (ordered : orderedOriginsFrom ascending prior rows)
    (row : Int × Value) (member : row ∈ rows) :
    if ascending then prior < row.1 else row.1 < prior := by
  induction rows generalizing prior with
  | nil => simp at member
  | cons first rest ih =>
    obtain ⟨step, tail⟩ := ordered
    rcases List.mem_cons.mp member with same | deeper
    · simpa [same] using step
    · have transitive := ih first.1 tail deeper
      cases ascending <;> simp at step transitive ⊢ <;> omega

/-- A uniform strict comparison of adjacent captured origins excludes
duplicates, so the identity view preserves every physical occurrence. -/
theorem ordered_capture_nodup (ascending : Bool) (prior : Int)
    (rows : List (Int × Value)) (ordered : orderedOriginsFrom ascending prior rows) :
    rows.Nodup := by
  induction rows generalizing prior with
  | nil => simp
  | cons first rest ih =>
    obtain ⟨_, tail⟩ := ordered
    apply List.nodup_cons.mpr
    refine ⟨?_, ih first.1 tail⟩
    intro collision
    have impossible := ordered_origin_distance ascending first.1 rest tail first collision
    cases ascending <;> simp at impossible

def packedBinaryCells : List (Int × Int) → List Int
  | [] => []
  | row :: rows => row.1 :: row.2 :: packedBinaryCells rows

def unpackBinaryCells : List Int → List (Int × Int)
  | left :: right :: cells => (left, right) :: unpackBinaryCells cells
  | _ => []

theorem packed_capture_roundtrip (rows : List (Int × Int)) :
    unpackBinaryCells (packedBinaryCells rows) = rows := by
  induction rows with
  | nil => rfl
  | cons row tail ih => simp [packedBinaryCells, unpackBinaryCells, ih]

/-- Read adjacent packed pairs from the end without swapping fields.
This is the newest-first lane used by the ranked source index. -/
def packedNewestLane (cells : List Int) : List (Int × Int) :=
  (unpackBinaryCells cells.reverse).map Prod.swap

theorem packed_newest_lane_exact (rows : List (Int × Int)) :
    packedNewestLane (packedBinaryCells rows) = rows.reverse := by
  have packedAppend (base extra : List (Int × Int)) :
      packedBinaryCells (base ++ extra) = packedBinaryCells base ++ packedBinaryCells extra := by
    induction base with
    | nil => rfl
    | cons head tail next => simp [packedBinaryCells, next]
  have reversed (ordered : List (Int × Int)) :
      (packedBinaryCells ordered).reverse = packedBinaryCells (ordered.reverse.map Prod.swap) := by
    induction ordered with
    | nil => rfl
    | cons head tail next =>
      simp [packedBinaryCells, List.reverse_cons, next, packedAppend]
  rw [packedNewestLane, reversed, packed_capture_roundtrip, List.map_map]
  simp [Function.comp_def]

def matchesPackedCells : List (Int × Int) → List Int → Bool
  | [], [] => true
  | (left, right) :: rows, storedLeft :: storedRight :: cells =>
      (left == storedLeft) && (right == storedRight) && matchesPackedCells rows cells
  | _, _ => false

/-- Successful borrowed backing requires exact occurrence order, extent and
both fields. A same-sized update with a changed last field cannot borrow. -/
theorem matches_packed_cells_exact (rows : List (Int × Int)) (cells : List Int) :
    matchesPackedCells rows cells = true ↔ cells = packedBinaryCells rows := by
  induction rows generalizing cells with
  | nil => cases cells <;> simp [matchesPackedCells, packedBinaryCells]
  | cons row rest ih =>
    obtain ⟨left, right⟩ := row
    cases cells with
    | nil => simp [matchesPackedCells, packedBinaryCells]
    | cons storedLeft remaining =>
      cases remaining with
      | nil => simp [matchesPackedCells, packedBinaryCells]
      | cons storedRight suffix =>
        simp only [matchesPackedCells, packedBinaryCells, Bool.and_eq_true,
          beq_iff_eq, ih, List.cons.injEq]
        constructor
        · rintro ⟨⟨l, r⟩, tail⟩
          exact ⟨l.symm, r.symm, tail⟩
        · rintro ⟨l, r, tail⟩
          exact ⟨⟨l.symm, r.symm⟩, tail⟩

/-- A former packed cut only saves a capture when all occurrences match.
Discarding it after an affine publication can change acquisition cost,
but not the cells of a later independently admitted packed replacement. -/
def captureOrBorrowPacked (cached : Option (List Int)) (rows : List (Int × Int)) : List Int :=
  match cached with
  | none => packedBinaryCells rows
  | some cells => if matchesPackedCells rows cells then cells else packedBinaryCells rows

theorem affine_drops_packed_alternate (cached : Option (List Int)) (rows : List (Int × Int)) :
    captureOrBorrowPacked none rows = captureOrBorrowPacked cached rows := by
  cases cached with
  | none => rfl
  | some cells =>
    by_cases exactMatch : matchesPackedCells rows cells = true
    · have same := (matches_packed_cells_exact rows cells).mp exactMatch
      simp [captureOrBorrowPacked, same]
    · simp [captureOrBorrowPacked, exactMatch]

theorem packed_capture_exact_extent (rows : List (Int × Int)) :
    (packedBinaryCells rows).length = 2 * rows.length := by
  induction rows with
  | nil => rfl
  | cons row tail ih => simp [packedBinaryCells, ih]; omega

section OrderedBinaryReply

def binaryReply (rows : List (Int × Int)) : List Int :=
  (Int.ofNat rows.length) :: 2 :: packedBinaryCells rows

/-- The view owns one version's field sequence. The callback cursor must finish
at the admitted extent, and the caller must still be live to receive it. -/
def admitBinaryReply (rows : List (Int × Int)) (count slots written : Nat)
    (live : Bool) : Option (List Int) :=
  if live && decide (0 < count ∧ 2 + 2 * count ≤ slots ∧ rows.length = count ∧ written = count)
  then some (binaryReply rows) else none

theorem binary_reply_matches_complete_export (rows : List (Int × Int)) :
    binaryReply rows.reverse.reverse = binaryReply rows ∧
      unpackBinaryCells ((binaryReply rows).drop 2) = rows := by
  simp [binaryReply, packed_capture_roundtrip]

theorem binary_reply_writes_fit (count row slots : Nat)
    (inside : row < count) (admitted : 2 + 2 * count ≤ slots) :
    2 + 2 * row < slots ∧ 3 + 2 * row < slots := by omega

theorem binary_reply_refuses_partial (rows : List (Int × Int)) (count slots written : Nat)
    (failed : written ≠ count ∨ slots < 2 + 2 * count ∨ live = false) :
    admitBinaryReply rows count slots written live = none := by
  rcases failed with incomplete | extent | canceled
  · simp [admitBinaryReply, incomplete]
  · have tooSmall : ¬ 2 + 2 * count ≤ slots := by omega
    simp [admitBinaryReply, tooSmall]
  · simp [admitBinaryReply, canceled]

def publishBinaryReply {Version : Type} [DecidableEq Version] (captured current : Version)
    (packet : Option (List Int)) : Option (Version × List Int) :=
  if captured = current then packet.map (fun data => (captured, data)) else none

/-- A reply pairs its captured version with its exact fields. A reentrant
source replacement cannot publish those fields under the new version. -/
theorem binary_reply_keeps_capture {Version : Type} [DecidableEq Version]
    (captured current label : Version) (packet : Option (List Int)) (data : List Int)
    (published : publishBinaryReply captured current packet = some (label, data)) :
    label = captured ∧ current = captured ∧ packet = some data := by
  by_cases same : captured = current
  · cases packet with
    | none => simp [publishBinaryReply, same] at published
    | some cells =>
      have equal : captured = label ∧ cells = data := by
        simpa [publishBinaryReply, same] using published
      obtain ⟨labelEq, dataEq⟩ := equal
      exact ⟨labelEq.symm, same.symm, congrArg some dataEq⟩
  · simp [publishBinaryReply, same] at published

/-- The caller owns the destination. A completed capture supplies the ordered
fields while the private packet is staged. The last liveness check precedes
the only write to the destination. -/
def copyBinaryReply {Version : Type}
    (capture : Option (Version × List (Int × Int))) (destination : List Int)
    (start packetLimit : Nat) (live : Bool) :
    List Int × Option (Version × Nat) :=
  match capture with
  | none => (destination, none)
  | some (version, rows) =>
    let count := rows.length
    if live && decide (0 < count ∧ 2 + 2 * count ≤ packetLimit ∧
        start + 2 * count ≤ destination.length) then
      (destination.take start ++ (binaryReply rows).drop 2 ++
        destination.drop (start + 2 * count), some (version, count))
    else (destination, none)

theorem copy_binary_reply_keeps_capture_and_order {Version : Type}
    (version : Version) (rows : List (Int × Int)) (destination : List Int)
    (start packetLimit : Nat)
    (fits : 0 < rows.length ∧ 2 + 2 * rows.length ≤ packetLimit ∧
        start + 2 * rows.length ≤ destination.length) :
    copyBinaryReply (some (version, rows)) destination start packetLimit true =
      (destination.take start ++ packedBinaryCells rows ++
        destination.drop (start + 2 * rows.length), some (version, rows.length)) ∧
    unpackBinaryCells (packedBinaryCells rows) = rows := by
  simp [copyBinaryReply, fits, binaryReply, packed_capture_roundtrip]

theorem copy_binary_reply_refusal_preserves_destination {Version : Type}
    (version : Version) (rows : List (Int × Int)) (destination : List Int)
    (start packetLimit : Nat) (live : Bool)
    (refused : live = false ∨ rows.length = 0 ∨
        packetLimit < 2 + 2 * rows.length ∨ destination.length < start + 2 * rows.length) :
    copyBinaryReply (some (version, rows)) destination start packetLimit live =
      (destination, none) := by
  rcases refused with canceled | empty | packet | buffer
  · simp [copyBinaryReply, canceled]
  · simp [copyBinaryReply, empty]
  · have exceeds : ¬ 2 + 2 * rows.length ≤ packetLimit := by omega
    simp [copyBinaryReply, exceeds]
  · have exceeds : ¬ start + 2 * rows.length ≤ destination.length := by omega
    simp [copyBinaryReply, exceeds]

theorem copy_binary_reply_without_capture {Version : Type}
    (destination : List Int) (start packetLimit : Nat) (live : Bool) :
    copyBinaryReply (Version := Version) none destination start packetLimit live =
      (destination, none) := rfl

/-- A frozen packed lane in export order supplies exactly the packet payload.
Copying that lane directly has the same slice effect as staging the header
and dropping it. Neither route changes cells outside the affected slice. -/
theorem copy_packed_lane_matches_staged {Version : Type}
    (version : Version) (rows : List (Int × Int)) (lane destination : List Int)
    (start packetLimit : Nat)
    (ordered : lane = packedBinaryCells rows)
    (fits : 0 < rows.length ∧ 2 + 2 * rows.length ≤ packetLimit ∧
        start + 2 * rows.length ≤ destination.length) :
    copyBinaryReply (some (version, rows)) destination start packetLimit true =
      (destination.take start ++ lane ++ destination.drop (start + lane.length),
        some (version, rows.length)) := by
  subst lane
  simp [copyBinaryReply, fits, binaryReply, packed_capture_exact_extent]

end OrderedBinaryReply

/-- Replacement preflight checks the outer extent and each complete
binary tuple while matching the already frozen backing cells. -/
def matchesPackedRows : List (List Int) → List Int → Bool
  | [], [] => true
  | row :: rows, left :: right :: cells =>
      (row == [left, right]) && matchesPackedRows rows cells
  | _, _ => false

theorem packed_replacement_preflight_exact (frozen : List (Int × Int))
    (replacement : List (List Int)) :
    matchesPackedRows replacement (packedBinaryCells frozen) = true ↔
      replacement = frozen.map (fun row => [row.1, row.2]) := by
  induction frozen generalizing replacement with
  | nil => cases replacement <;> simp [matchesPackedRows, packedBinaryCells]
  | cons row rest ih =>
    cases replacement <;>
      simp [matchesPackedRows, packedBinaryCells, ih]

theorem packed_replacement_preflight_count (frozen : List (Int × Int))
    (replacement : List (List Int))
    (matched : matchesPackedRows replacement (packedBinaryCells frozen) = true) :
    (packedBinaryCells frozen).length / 2 = replacement.length := by
  rw [(packed_replacement_preflight_exact frozen replacement).mp matched,
    List.length_map, packed_capture_exact_extent]
  omega

/-- Signed 32-bit cells preserve labels after the range test. Labels
outside this range continue through the full fixnum representation. -/
theorem signed32_cell_exact (label : Int)
    (lower : -2147483648 ≤ label) (upper : label < 2147483648) :
    (label + 2147483648) % 4294967296 - 2147483648 = label := by
  rw [Int.emod_eq_of_lt (by omega) (by omega)]
  omega

theorem packed_row_indices_fit (rows : List (Int × Int)) (row : Nat)
    (present : row < rows.length) :
    2 * row < (packedBinaryCells rows).length ∧
      2 * row + 1 < (packedBinaryCells rows).length := by
  rw [packed_capture_exact_extent]
  omega

/-- The source and identity projection borrow the same chronological
value sequence. The ordinary newest-first lane remains its reversal. -/
theorem packed_capture_forward_and_lane (rows : List (Int × Int)) :
    unpackBinaryCells (packedBinaryCells rows) = rows ∧
      (unpackBinaryCells (packedBinaryCells rows)).reverse = rows.reverse := by
  rw [packed_capture_roundtrip]
  exact ⟨rfl, rfl⟩

/-- The unselected visitor reads successive cell pairs. Its delivery prefix
is exactly the corresponding prefix of the frozen rows even when a consumer
exits before scanning the rest. -/
theorem packed_visit_prefix_exact (rows : List (Int × Int)) (emitted : Nat) :
    (unpackBinaryCells (packedBinaryCells rows)).take emitted = rows.take emitted := by
  rw [packed_capture_roundtrip]

/-- Each received row is valid for the same captured cut. Publication of a
different source does not take part in addressing this cut. -/
theorem packed_visit_read_fits (rows : List (Int × Int)) (ordinal : Nat)
    (next : ordinal < rows.length) :
    2 * ordinal + 1 < (packedBinaryCells rows).length := by
  exact (packed_row_indices_fit rows ordinal next).2

/-- Writing a forward cursor into descending slots gives the same ordinals
as reading the materialized newest-first lane. -/
theorem forward_cursor_preserves_newest_first_slot {Row : Type} (rows : List Row)
    (i : Nat) (inBounds : i < rows.length) :
    ∃ slotBound : rows.length - 1 - i < rows.reverse.length,
      rows.reverse[rows.length - 1 - i]'slotBound = rows[i] := by
  have slotBound : rows.length - 1 - i < rows.reverse.length := by
    rw [List.length_reverse]
    omega
  refine ⟨slotBound, ?_⟩
  rw [List.getElem_reverse]
  congr 1
  omega

/-- A closed identity rule reads the newest-first lane and performs the
two existing reversals before publication. Direct export yields that
same chronological sequence for both the source and the target. -/
theorem packed_identity_commit_order (rows : List (Int × Int)) :
    (unpackBinaryCells (packedBinaryCells rows)).reverse.reverse = rows := by
  rw [List.reverse_reverse, packed_capture_roundtrip]

theorem packed_identity_resource_room (rows : List (Int × Int))
    (input derived total : Nat)
    (inputRoom : rows.length ≤ input)
    (derivedRoom : rows.length ≤ derived)
    (totalRoom : rows.length + rows.length ≤ total) :
    (unpackBinaryCells (packedBinaryCells rows)).length ≤ input ∧
    (unpackBinaryCells (packedBinaryCells rows)).length ≤ derived ∧
    rows.length + (unpackBinaryCells (packedBinaryCells rows)).length ≤ total := by
  simp [packed_capture_roundtrip, inputRoom, derivedRoom, totalRoom]

/-- The recursive result's room is the intersection of the derived
and total budgets after admitting the frozen source. -/
theorem ranked_room_exact (source derived total result : Nat) (sourceFits : source ≤ total) :
    result ≤ min derived (total - source) ↔ result ≤ derived ∧ source + result ≤ total := by
  rw [Nat.le_min]
  omega

/-- Field delivery supplies the same two arguments that applying the
consumer to each detached binary row would supply, including after an
early exit. -/
theorem packed_visit_fields_exact {State : Type} (consume : State → Int → Int → State)
    (initial : State) (rows : List (Int × Int)) (emitted : Nat) :
    ((unpackBinaryCells (packedBinaryCells rows)).take emitted).foldl
        (fun state (left, right) => consume state left right) initial =
      (rows.take emitted).foldl (fun state row => consume state row.1 row.2) initial := by
  rw [packed_visit_prefix_exact]

/-- The packed base and ordered append index publish a single chronological
cut. Extending the suffix leaves the previous root readable as before. -/
theorem packed_append_publication (base tail : List (Int × Int)) (row : Int × Int) :
    unpackBinaryCells (packedBinaryCells base) ++ (tail ++ [row]) =
      (base ++ tail) ++ [row] := by
  rw [packed_capture_roundtrip, List.append_assoc]

theorem packed_append_index_selection (base tail : List (Int × Int)) (key : Int) :
    ((unpackBinaryCells (packedBinaryCells base) ++ tail).filter
      (fun row => decide (row.1 = key))) =
      (base.filter (fun row => decide (row.1 = key))) ++
        (tail.filter (fun row => decide (row.1 = key))) := by
  rw [packed_capture_roundtrip, List.filter_append]

theorem packed_append_partition_disjoint (base tail : List (Int × Int))
    (ascending : Bool) (last : Int)
    (baseBound : ∀ row ∈ base, if ascending then row.1 ≤ last else last ≤ row.1)
    (tailOrder : orderedOriginsFrom ascending last tail)
    (key : Int × Int) (inBase : key ∈ base) (inTail : key ∈ tail) : False := by
  have bound := baseBound key inBase
  have strict := ordered_origin_distance ascending last tail tailOrder key inTail
  cases ascending <;> simp at bound strict <;> omega

/-- Returning all rows takes one publication visit per logical row even when
an append updates only the ordered suffix index. -/
theorem packed_append_export_visits (base tail : List (Int × Int)) :
    (unpackBinaryCells (packedBinaryCells base) ++ tail).length = base.length + tail.length := by
  rw [packed_capture_roundtrip, List.length_append]

/-- Export allocates fresh rows while prepending in emission order. Public
publication reverses the same terminal lane and detaches its stored rows. -/
theorem terminal_export_exact (emitted : List Row) (detach : Row → PublicRow) :
    emitted.foldl (fun output row => detach row :: output) [] =
      emitted.reverse.map detach := by
  have ordered : ∀ (rest : List Row) (output : List PublicRow),
      rest.foldl (fun out row => detach row :: out) output =
        rest.reverse.map detach ++ output := by
    intro rest
    induction rest with
    | nil => simp
    | cons row rest ih => intro output; simp [ih, List.reverse_cons, List.append_assoc]
  rw [ordered, List.append_nil]

/-- The binary exporter may emit four adjacent rows in one native block.
Keeping the accumulator operation identical preserves the detached order. -/
theorem detached_export_four {Row PublicRow : Type} (detach : Row → PublicRow)
    (a b c d : Row) (rest : List Row) (tail : List PublicRow) :
    (a :: b :: c :: d :: rest).foldl (fun rows row => detach row :: rows) tail =
      rest.foldl (fun rows row => detach row :: rows)
        (detach d :: detach c :: detach b :: detach a :: tail) := rfl

/-- For the detached binary list ABI, an outer pair and both row pairs
are separate cells. Distinct row/field coordinates occupy distinct slots. -/
theorem detached_binary_pair_slot (row other : Nat) (part otherPart : Fin 3)
    (same : 3 * row + part.val = 3 * other + otherPart.val) :
    row = other ∧ part = otherPart := by
  have left := part.isLt
  have right := otherPart.isLt
  have rows : row = other := by omega
  exact ⟨rows, Fin.ext (by omega)⟩

/-- The slot for each cell of any row lies within the exported cell extent.
Runtime allocation bytes and collection time are separate observations. -/
theorem detached_binary_pair_extent (rows row : Nat) (part : Fin 3) (inside : row < rows) :
    3 * row + part.val < 3 * rows := by
  have width := part.isLt
  omega

/-- Appending by changing the private tail link maintains the published
sequence. The premise is that the private spine is unreleased until the
walk completes. This states content and order, independent of GC layout. -/
theorem detached_forward_order {Row PublicRow : Type} (detach : Row → PublicRow)
    (rows : List Row) (completed : List PublicRow) :
    rows.foldl (fun output row => output ++ [detach row]) completed =
      completed ++ rows.map detach := by
  induction rows generalizing completed with
  | nil => simp
  | cons row tail ih =>
    rw [List.foldl_cons, ih]
    simp [List.append_assoc]

/-- Connecting complete private output blocks in source order produces
exactly the usual detached sequence. -/
theorem detached_block_splice_order {Row PublicRow : Type} (detach : Row → PublicRow)
    (blocks : List (List Row)) :
    (blocks.map (List.map detach)).flatten = blocks.flatten.map detach :=
  (List.map_flatten (f := detach) (L := blocks)).symm

/-- A fresh row's spine and field cells lie beyond every previously
initialized row. Appending may change the private old tail's cdr only. -/
theorem detached_forward_cells_fresh (new old : Nat) (inside : old < new)
    (part prior : Fin 3) : 3 * old + prior.val < 3 * new + part.val := by
  have width := prior.isLt
  omega

/-- Each slot's summary describes the values the engine initializes from
that slot of the current cut. Appending combines the two classifications. -/
theorem scalar_slot_append {Value : Type} (scalar : Value → Bool)
    (old added : List Value) :
    (added ++ old).all scalar = (added.all scalar && old.all scalar) := by
  simp

/-- Scanning the summaries of the admitted slots gives the same scalar
classification as scanning the current owned values. The declarations,
including the original row spines, are outside this premise. -/
theorem actor_scalar_cut_summary {Value : Type} (scalar : Value → Bool)
    (slots : List (List Value)) (flags : List Bool)
    (admitted : flags = slots.map (fun values => values.all scalar)) :
    flags.all id = slots.all (fun values => values.all scalar) := by
  subst flags
  induction slots with
  | nil => rfl
  | cons values rest ih => simp [ih]

/-- A newly materialized prefix can link to a fresh, private suffix.
The suffix contains the remaining rows of this publication in order. -/
theorem detached_chunk_join {Row PublicRow : Type} (detach : Row → PublicRow)
    (rows : List Row) (cut : Nat) :
    (rows.take cut).map detach ++ (rows.drop cut).map detach = rows.map detach := by
  rw [← List.map_append, List.take_append_drop]

/-- A weak suffix either supplies the exact unpublished suffix or is absent.
Absence executes the complete ordinary export once from the same publication. -/
theorem detached_weak_suffix_exact {Row PublicRow : Type} (detach : Row → PublicRow)
    (rows : List Row) (cut : Nat) (suffix : Option (List PublicRow))
    (exact : ∀ tail, suffix = some tail → tail = (rows.drop cut).map detach) :
    (match suffix with
     | none => rows.map detach
     | some tail => (rows.take cut).map detach ++ tail) = rows.map detach := by
  cases suffix with
  | none => rfl
  | some tail =>
    change (rows.take cut).map detach ++ tail = rows.map detach
    rw [exact tail rfl, detached_chunk_join]

/-- All row-wise prefixes fit if the certified complete cardinality fits
both existing budgets. Refused counts keep the ordered failure route. -/
theorem compact_terminal_prefix_fits (source derived output count : Nat)
    (factsFit : count ≤ derived) (outputFits : source + count ≤ output)
    (accepted : Nat) (visited : accepted ≤ count) :
    accepted ≤ derived ∧ source + accepted ≤ output := by omega

end Ascent.MillionQueryWorkload

#print axioms Ascent.MillionQueryWorkload.complete_oracle
#print axioms Ascent.MillionQueryWorkload.bitmap_index_injective
#print axioms Ascent.MillionQueryWorkload.state_reply_cannot_certify_complete_query
#print axioms Ascent.MillionQueryWorkload.indexed_witnesses_exact
#print axioms Ascent.MillionQueryWorkload.routed_witnesses_exact
#print axioms Ascent.MillionQueryWorkload.indexed_visits_exact
#print axioms Ascent.MillionQueryWorkload.source_bucket_visit_exact
#print axioms Ascent.MillionQueryWorkload.detach_newest_first_exact
#print axioms Ascent.MillionQueryWorkload.successor_distance_no_repeat
#print axioms Ascent.MillionQueryWorkload.successor_rows_step
#print axioms Ascent.MillionQueryWorkload.successor_rows_unique
#print axioms Ascent.MillionQueryWorkload.successor_rows_disjoint
#print axioms Ascent.MillionQueryWorkload.successor_frontiers_exact
#print axioms Ascent.MillionQueryWorkload.successor_rows_length_exact
#print axioms Ascent.MillionQueryWorkload.successor_memo_length
#print axioms Ascent.MillionQueryWorkload.forward_compaction_preserves_unread
#print axioms Ascent.MillionQueryWorkload.reverse_compaction_preserves_unread
#print axioms Ascent.MillionQueryWorkload.suffix_counts_by_origin
#print axioms Ascent.MillionQueryWorkload.ordinal_run_reaches
#print axioms Ascent.MillionQueryWorkload.ordinal_run_no_cross
#print axioms Ascent.MillionQueryWorkload.ordinal_run_origin_window
#print axioms Ascent.MillionQueryWorkload.ordinal_visit_public_order
#print axioms Ascent.MillionQueryWorkload.ordinal_visit_scan_room
#print axioms Ascent.MillionQueryWorkload.ordered_capture_nodup
#print axioms Ascent.MillionQueryWorkload.packed_capture_forward_and_lane
#print axioms Ascent.MillionQueryWorkload.packed_newest_lane_exact
#print axioms Ascent.MillionQueryWorkload.packed_capture_exact_extent
#print axioms Ascent.MillionQueryWorkload.packed_replacement_preflight_exact
#print axioms Ascent.MillionQueryWorkload.packed_replacement_preflight_count
#print axioms Ascent.MillionQueryWorkload.signed32_cell_exact
#print axioms Ascent.MillionQueryWorkload.matches_packed_cells_exact
#print axioms Ascent.MillionQueryWorkload.packed_row_indices_fit
#print axioms Ascent.MillionQueryWorkload.packed_visit_prefix_exact
#print axioms Ascent.MillionQueryWorkload.packed_visit_read_fits
#print axioms Ascent.MillionQueryWorkload.packed_identity_commit_order
#print axioms Ascent.MillionQueryWorkload.packed_identity_resource_room
#print axioms Ascent.MillionQueryWorkload.ranked_room_exact
#print axioms Ascent.MillionQueryWorkload.packed_visit_fields_exact
#print axioms Ascent.MillionQueryWorkload.packed_append_publication
#print axioms Ascent.MillionQueryWorkload.packed_append_index_selection
#print axioms Ascent.MillionQueryWorkload.packed_append_partition_disjoint
#print axioms Ascent.MillionQueryWorkload.packed_append_export_visits
#print axioms Ascent.MillionQueryWorkload.terminal_export_exact
#print axioms Ascent.MillionQueryWorkload.detached_binary_pair_slot
#print axioms Ascent.MillionQueryWorkload.detached_binary_pair_extent
#print axioms Ascent.MillionQueryWorkload.compact_terminal_prefix_fits
