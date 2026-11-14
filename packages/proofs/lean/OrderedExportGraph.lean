-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Ordered factorised export, before source integration.
These laws concern immutable, already captured values. They do not authorize
caching author callbacks, admission results, or mutable UF nodes. Source
correspondence, retained capacity and native latency are independent obligations.
-/
namespace Ascent.OrderedExportGraph

variable {α : Type}

def productRows (leading left right : List α) : List (List α) :=
  left.flatMap (fun a => right.map (fun b => leading ++ [a, b]))

theorem product_rows_count (leading left right : List α) :
    (productRows leading left right).length = left.length * right.length := by
  induction left with
  | nil => simp [productRows]
  | cons a tail ih =>
    simp only [productRows, List.flatMap_cons, List.length_append, List.length_map]
    change right.length + (productRows leading tail right).length = _
    rw [ih]
    simp [Nat.add_mul, Nat.add_comm]

inductive Graph (α : Type) where
  | empty
  | product (leading left right : List α)
  | append (first second : Graph α)
  | backwards (body : Graph α)

def rows : Graph α → List (List α)
  | .empty => []
  | .product leading left right => productRows leading left right
  | .append first second => rows first ++ rows second
  | .backwards body => (rows body).reverse

def rowCount : Graph α → Nat
  | .empty => 0
  | .product _ left right => left.length * right.length
  | .append first second => rowCount first + rowCount second
  | .backwards body => rowCount body

theorem row_count_exact (graph : Graph α) : (rows graph).length = rowCount graph := by
  induction graph with
  | empty => rfl
  | product leading left right => exact product_rows_count leading left right
  | append first second ih1 ih2 => simp [rows, rowCount, ih1, ih2]
  | backwards body ih => simp [rows, rowCount, ih]

-- Derived journal batches reverse whole rows, never tuple columns.
theorem derived_order_exact (first second : Graph α) :
    rows (.backwards (.append first second)) =
      rows (.append (.backwards second) (.backwards first)) := by
  simp [rows]

theorem reverse_product_order (leading left right : List α) :
    rows (.backwards (.product leading left right)) =
      productRows leading left.reverse right.reverse := by
  simp [rows, productRows, List.reverse_flatMap, Function.comp_def]


-- A retained terminal mask filters whole rows without changing their order.
-- It is immutable for all later exports. Predicate/capture ownership remains
-- an obligation on the Scheme constructor, not a property of arbitrary callbacks.
def selectedRows (keep : List α → Bool) (leading left right : List α) :=
  (productRows leading left right).filter keep

theorem selected_reverse_order (keep : List α → Bool) (leading left right : List α) :
    (selectedRows keep leading left right).reverse =
      selectedRows keep leading left.reverse right.reverse := by
  have order := reverse_product_order leading left right
  simp only [rows] at order
  simp only [selectedRows, ← List.filter_reverse, order]

theorem selected_rows_bounded (keep : List α → Bool) (leading left right : List α) :
    (selectedRows keep leading left right).length ≤ left.length * right.length := by
  rw [← product_rows_count leading left right]
  exact List.length_filter_le _ _

-- Extensional equality is ordered equality, not set equality. It therefore
-- cannot silently discard duplicate occurrences or reorder an event batch.
theorem append_congr (a b c d : Graph α)
    (left : rows a = rows b) (right : rows c = rows d) :
    rows (.append a c) = rows (.append b d) := by simp [rows, left, right]

structure CutIdentity where
  owner : Nat
  generation : Nat
  revision : Nat
  lane : Nat
  deriving DecidableEq

-- A source replacement with equal values is still a distinct generation.
def usable (captured current : CutIdentity) : Bool := captured == current

theorem changed_generation_refuses (old next : CutIdentity)
    (changed : old.generation ≠ next.generation) : usable old next = false := by
  simp only [usable, beq_eq_false_iff_ne]
  intro same
  exact changed (congrArg CutIdentity.generation same)

-- k additional reads share only captured graph preparation. Every read still
-- pays its complete output charge. First-read preparation is never subtracted.
def replayWork (reads prepare emit : Nat) : Nat := reads * (prepare + emit)
def retainedWork (reads prepare emit : Nat) : Nat := prepare + reads * emit

theorem repeated_preparation_saving (k prepare emit : Nat) :
    replayWork (k + 1) prepare emit =
      retainedWork (k + 1) prepare emit + k * prepare := by
  simp [replayWork, retainedWork, Nat.add_mul, Nat.mul_add]
  omega

theorem first_read_charged (prepare emit : Nat) :
    replayWork 1 prepare emit = retainedWork 1 prepare emit := by
  simp [replayWork, retainedWork]

theorem full_output_not_elided (reads prepare emit : Nat) :
    reads * emit ≤ retainedWork reads prepare emit := by
  simp [retainedWork]

/-- The decision is scoped to one unchanged cut. Work counts can differ
per request, including high-fanout and unbound keys. Cost inputs must use
the same units and measurement window. -/
def indexWork (build : Nat) (probes : List Nat) : Nat := build + probes.sum

theorem index_pays_within_cut (build output : Nat) (scans probes : List Nat) :
    indexWork build probes + output < scans.sum + output ↔
      build + probes.sum < scans.sum := by
  simp [indexWork]

/-- Each fresh cut pays its own index construction. The expected scan
and probe totals already include any unchanged requests in that cut. -/
theorem replacement_restarts_index_budget (firstBuild nextBuild : Nat)
    (firstProbes nextProbes : List Nat) :
    indexWork firstBuild firstProbes + indexWork nextBuild nextProbes =
      indexWork (firstBuild + nextBuild) (firstProbes ++ nextProbes) := by
  simp only [indexWork, List.sum_append]
  omega

/-- Original empty-bucket fixture, summed over one set of three source
cuts. The 19 skipped canonical probes must pay for cache tests, key and
version comparisons, field stores and fresh cache entries. The supplied
weights are costs in one unit; fixed common work is outside this test. -/
theorem empty_bucket_trace_break_even
    (probe test key version store entry : Nat) :
    73 * probe + (92 * test + 71 * key + 81 * version + 92 * store + 6 * entry) <
        92 * probe ↔
      92 * test + 71 * key + 81 * version + 92 * store + 6 * entry < 19 * probe := by
  omega

/-- The original 0.85 CPU ratio also charges all common solve work.
Even free certificates cannot give that reduction when the unchanged
portion already spends the missing 15 percent of the original budget. -/
theorem empty_bucket_trace_cpu_budget
    (common probe test key version store entry : Nat)
    (gate : 100 * (common + 73 * probe +
      (92 * test + 71 * key + 81 * version + 92 * store + 6 * entry)) ≤
      85 * (common + 92 * probe)) :
    15 * common + 100 * (92 * test + 71 * key + 81 * version + 92 * store + 6 * entry) ≤
      520 * probe := by
  omega

/-- The original empty-bucket ratio charges declaration work in both arms.
Grant the candidate a zero-cost solve. With a fixed declaration, even that
candidate cannot fit when declaration already exceeds the entire target. -/
theorem empty_bucket_solve_only_cannot_pay
    (declaration baselineSolve candidateSolve : Nat)
    (share : 85 * baselineSolve < 15 * declaration) :
    ¬ 100 * (declaration + candidateSolve) ≤ 85 * (declaration + baselineSolve) := by
  omega

/-- A candidate that also changes declaration must save enough there to
cover whatever remains after crediting its solve savings. Input times must
come from matched observation windows in the same units. -/
theorem empty_bucket_needs_declaration_saving
    (declaration baselineSolve candidateDeclaration candidateSolve : Nat)
    (gate : 100 * (candidateDeclaration + candidateSolve) ≤
      85 * (declaration + baselineSolve)) :
    15 * declaration + 100 * candidateSolve ≤
      85 * baselineSolve + 100 * (declaration - candidateDeclaration) := by
  omega

/-- The native observer brackets these synchronous operations in order.
Declaration construction creates the relation and rule values, detaches
source handles, and validates the public Program before the solver runs.
All inputs are elapsed values from the same owner-thread CPU clock. -/
structure EmptyBucketCost where
  declaration : Nat
  solve : Nat
  between : Nat

def EmptyBucketCost.total (cost : EmptyBucketCost) : Nat :=
  cost.declaration + cost.solve + cost.between

/-- Keeping declaration fixed makes its measured cost a necessary condition
for the existing 0.85 CPU ratio, even if the remaining work becomes free. -/
theorem EmptyBucketCost.solve_only_cannot_pay (before after : EmptyBucketCost)
    (same : after.declaration = before.declaration)
    (share : 85 * before.total < 100 * before.declaration) :
    ¬ (100 * after.total ≤ 85 * before.total) := by
  unfold EmptyBucketCost.total at *
  omega

namespace Publication

inductive EventKind where
  | source
  | derived

def eventRows (kind : EventKind) (frontiers : List (Graph α)) : List (List α) :=
  let raw := frontiers.flatMap rows
  match kind with
  | .source => raw
  | .derived => raw.reverse

/-- The derived lane reverses the order of frontiers and each frontier's
rows. Membership of each individual product remains owned by its cut. -/
theorem derived_frontiers_exact (frontiers : List (Graph α)) :
    eventRows .derived frontiers =
      frontiers.reverse.flatMap (fun graph => rows (.backwards graph)) := by
  simp [eventRows, List.reverse_flatMap, rows, Function.comp_def]

/-- The initial delta reverses the chronological rows, preserving each row.
Relinking private outer cells preserves their identities. Copying reverse
would allocate one additional outer cell for every row. -/
theorem initial_delta_spine (cells : List (Nat × List α)) :
    cells.reverse.map Prod.snd = (cells.map Prod.snd).reverse ∧
    (cells.reverse.map Prod.fst).Perm (cells.map Prod.fst) ∧
    3 * cells.length + cells.length = 4 * cells.length := by
  refine ⟨by simp, ?_, by omega⟩
  rw [List.map_reverse]
  exact List.reverse_perm _

/-- A pre-merge component pair has uniform reachability. Once the graph
supplies that bit, retaining a missing block preserves its entire ordered
row sequence. Later root reassignment does not enter this expansion. -/
theorem missing_blocks_exact (blocks : List (Bool × Graph α)) :
    ((blocks.filter (fun block => !block.1)).map Prod.snd).flatMap rows =
      blocks.flatMap (fun (present, graph) => if present then [] else rows graph) := by
  induction blocks with
  | nil => rfl
  | cons block rest ih =>
    obtain ⟨present, graph⟩ := block
    cases present <;> simp [ih]

theorem nonempty_block_units (left right : Nat) (hl : 0 < left) (hr : 0 < right) :
    1 + left + right ≤ 3 * (left * right) := by
  have l : left ≤ left * right := by
    simpa using Nat.mul_le_mul_left left (show 1 ≤ right from hr)
  have r : right ≤ left * right := by
    simpa using Nat.mul_le_mul_right right (show 1 ≤ left from hl)
  omega

def componentRows (missing : List α → List α → Bool)
    (lefts rights : List (List α)) : List (List α) :=
  lefts.flatMap fun left => rights.flatMap fun right =>
    if missing left right then productRows [] left right else []

/-- Terminal component axes share one immutable reachability mask. The
derived lane reverses both component axes and their member axes, while
probing each original component identity. -/
theorem terminal_component_reverse (missing : List α → List α → Bool)
    (lefts rights : List (List α)) :
    (componentRows missing lefts rights).reverse =
      lefts.reverse.flatMap (fun left => rights.reverse.flatMap fun right =>
        if missing left right then productRows [] left.reverse right.reverse else []) := by
  have block (left right : List α) :
      (if missing left right then productRows [] left right else []).reverse =
        (if missing left right then productRows [] left.reverse right.reverse else []) := by
    cases h : missing left right with
    | false => simp
    | true => simpa [h, rows] using reverse_product_order [] left right
  simp [componentRows, List.reverse_flatMap, Function.comp_def, block]

/-- A retained generation owns the membership used to decide the next
ordered frontier. The frontier is chosen before the prospective edit is
published. The graph algorithm supplies candidates in the writer's order. -/
def frontier {Row : Type} (before : Row → Bool) (candidates : List Row) : List Row :=
  candidates.filter (fun row => !(before row))

def publish {Row : Type} [DecidableEq Row] (before : Row → Bool)
    (added : List Row) (row : Row) : Bool :=
  before row || decide (row ∈ added)

theorem untouched_lookup {Row : Type} [DecidableEq Row] (before : Row → Bool)
    (added : List Row) (row : Row) (untouched : row ∉ added) :
    publish before added row = before row := by
  simp [publish, untouched]

theorem publication_contains_candidates {Row : Type} [DecidableEq Row]
    (before : Row → Bool) (candidates : List Row) (row : Row) :
    publish before (frontier before candidates) row =
      (before row || decide (row ∈ candidates)) := by
  cases present : before row <;> simp [publish, frontier, present]

/-- Existing facts cannot reappear in later frontiers. For a repeated
event with the same candidate support, the whole frontier is empty. -/
theorem repeated_event_has_empty_frontier {Row : Type} [DecidableEq Row]
    (before : Row → Bool) (candidates : List Row) :
    frontier (publish before (frontier before candidates)) candidates = [] := by
  apply List.filter_eq_nil_iff.mpr
  intro row member
  rw [publication_contains_candidates]
  simp [member]

/-- The state includes the ordered descriptors and the admission identity.
The transition cost here counts events independently of its graph work. -/
def replay {State Event : Type} (step : State → Event → State)
    (before : State) (events : List Event) : State × Nat :=
  (events.foldl step before, events.length)

theorem retained_prefix_replays_only_suffix {State Event : Type}
    (step : State → Event → State) (before : State) (oldEvents newEvents : List Event) :
    let full := replay step before (oldEvents ++ newEvents)
    let incremental := replay step (replay step before oldEvents).1 newEvents
    full.1 = incremental.1 ∧ full.2 = oldEvents.length + incremental.2 := by
  simp [replay, List.foldl_append]

/-- The storage owner prepends each committed block batch. The publication
reverses only its private batch spine, preserving each injection's order. -/
def retainBatch (batches : List (List (Graph α))) (batch : List (Graph α)) :
    List (List (Graph α)) :=
  batch :: batches

def retainedRows (batches : List (List (Graph α))) : List (List α) :=
  batches.reverse.flatMap fun batch => batch.flatMap rows

theorem retain_batch_rows (batches : List (List (Graph α))) (batch : List (Graph α)) :
    retainedRows (retainBatch batches batch) = retainedRows batches ++ batch.flatMap rows := by
  simp [retainBatch, retainedRows]

theorem retain_batches_rows (batches incoming : List (List (Graph α))) :
    retainedRows (incoming.foldl retainBatch batches) =
      retainedRows batches ++ incoming.flatMap (fun batch => batch.flatMap rows) := by
  induction incoming generalizing batches with
  | nil => simp
  | cons batch rest ih =>
    simp only [List.foldl_cons, ih, retain_batch_rows, List.flatMap_cons, List.append_assoc]

/-- A run of predecessor member spines sharing one target axis can be
represented by a single product. The left order remains the writer's order. -/
theorem factor_shared_right (leading right : List α) (lefts : List (List α)) :
    productRows leading lefts.flatten right =
      lefts.flatMap (fun left => productRows leading left right) := by
  induction lefts with
  | nil => rfl
  | cons left tail ih =>
    simp only [List.flatten_cons, List.flatMap_cons]
    have split : productRows leading (left ++ tail.flatten) right =
        productRows leading left right ++ productRows leading tail.flatten right := by
      simp [productRows, List.flatMap_append]
    rw [split, ih]

/-- A nonempty run borrows one right axis regardless of the number of
source components. Count descriptors and logical axis entries. -/
def sharedRightUnits (leftSizes : List Nat) (rightSize : Nat) : Nat :=
  1 + leftSizes.sum + rightSize

def splitRightUnits (leftSizes : List Nat) (rightSize : Nat) : Nat :=
  leftSizes.sum + leftSizes.length * (1 + rightSize)

theorem factor_descriptor_saving (leftSizes : List Nat) (rightSize : Nat)
    (multiple : 1 < leftSizes.length) :
    sharedRightUnits leftSizes rightSize < splitRightUnits leftSizes rightSize := by
  have cost := Nat.mul_le_mul_right (1 + rightSize) (show 2 ≤ leftSizes.length from multiple)
  simp [sharedRightUnits, splitRightUnits, Nat.succ_mul] at *
  omega

/-- A prefix cursor visits precisely the retained rows, in their original
order. The native owner must verify prefix equality before sharing an axis. -/
def prefixRows (leading axis : List α) (slices : List (α × Nat)) : List (List α) :=
  slices.flatMap fun (left, stop) => productRows leading [left] (axis.take stop)

theorem share_prefix_rows (leading axis : List α)
    (slices : List (α × List α))
    (prefixes : ∀ entry ∈ slices, axis.take entry.2.length = entry.2) :
    prefixRows leading axis (slices.map fun (left, right) => (left, right.length)) =
      slices.flatMap (fun (left, right) => productRows leading [left] right) := by
  induction slices with
  | nil => rfl
  | cons entry rest ih =>
    have tail := ih (fun e h => prefixes e (List.mem_cons_of_mem _ h))
    have head := prefixes entry (by simp)
    simp only [prefixRows, List.map_cons, List.flatMap_cons] at tail ⊢
    rw [head, tail]

/-- The vector stores one scalar per shared endpoint, and each slice stores
its left scalar and exclusive bound. The final one charges the batch header. -/
def prefixUnits (axisLength slices : Nat) : Nat := 1 + axisLength + 2 * slices

theorem cycle512_prefix_fits :
    133374 + prefixUnits 512 511 ≤ 262144 := by decide

/-- The first birth slot can be the source itself. Both compact word
checks and the cursor omit that reflexive slot before counting a prefix. -/
theorem prefix_without_reflexive_head (head : α) (tail : List α) (length : Nat) :
    ((head :: tail).take (length + 1)).drop 1 = tail.take length := by
  simp

/-- Full earlier words add their entire ordered target sequence. The last
word may end at an interior bit, and later words contribute no targets. -/
theorem join_prefix_words (whole last later : List α) (stop : Nat)
    (within : stop ≤ last.length) :
    (whole ++ last ++ later).take (whole.length + stop) =
      whole ++ last.take stop := by
  rw [List.append_assoc, List.take_append]
  simp [List.take_append, List.take_of_length_le (Nat.le_add_right whole.length stop),
    Nat.sub_eq_zero_of_le within]

/-- Source cursors store an exclusive endpoint. At a reflexive head the
stored endpoint includes the skipped head, so the decoded slice is exact. -/
theorem decode_prefix_slice (head : α) (axis : List α) (stop : Nat) (skipHead : Bool) :
    ((head :: axis).take (stop + if skipHead then 1 else 0)).drop
        (if skipHead then 1 else 0) =
      (if skipHead then axis else head :: axis).take stop := by
  cases skipHead <;> simp

/-- Birth slots are assigned once. A descriptor ends at the old size
and remains valid as later births append to the batch's private axis. -/
theorem frozen_birth_prefix (born later : List α) :
    (born ++ later).take born.length = born := by
  simp

theorem retained_predecessor_prefix (born later : List α) (target : α)
    (preds : List α) (full : preds = born) :
    productRows [] ((born ++ later).take born.length) [target] =
      productRows [] preds [target] := by
  rw [frozen_birth_prefix, full]

/-- A complete predecessor axis is known from cardinality once it is
an ordered filter of the active birth roster. -/
theorem full_birth_filter (keep : α → Bool) (born : List α)
    (full : (born.filter keep).length = born.length) : born.filter keep = born := by
  induction born with
  | nil => rfl
  | cons birth rest ih =>
    cases h : keep birth with
    | true => simpa [h] using ih (by simpa [h] using full)
    | false =>
      have bounded := List.length_filter_le keep rest
      simp [h] at full
      omega

/-- For a chain, a bounded cursor pays for one reserved birth directory
and one four-unit descriptor per extension. The expanded axes pay the
sum of predecessor lengths. -/
def retainedChainAxisUnits (birthCapacity extensions : Nat) : Nat :=
  birthCapacity + 4 * extensions

theorem chain_axis_storage_saving :
    retainedChainAxisUnits (2 * 384) 383 < 73536 ∧
      retainedChainAxisUnits (2 * 512) 511 < 130816 := by decide

/-- Add the first binary product, all singleton birth rectangles and
the closing shared target descriptor to the compact predecessor cost. -/
def cycleCaptureUnits (width : Nat) : Nat :=
  retainedChainAxisUnits (2 * width) (width - 2) +
    3 * (width + 1) + prefixUnits width (width - 1)

theorem cycle_birth_directory_cost :
    cycleCaptureUnits 384 = 4602 ∧ cycleCaptureUnits 512 = 6138 := by decide

namespace SimpleCycle

/-- Strict chain reachability in traversal rank. Reflexive births are
part of the admitted UF relation. -/
def chain (width left right : Nat) : Prop :=
  left ≤ right ∧ right < width

instance (width left right : Nat) : Decidable (chain width left right) :=
  inferInstanceAs (Decidable (left ≤ right ∧ right < width))

theorem chain_birth_frontier (width left right : Nat) :
    chain (width + 1) left right ↔
      chain width left right ∨ (right = width ∧ left ≤ width) := by
  unfold chain
  omega

theorem chain_birth_disjoint (width left right : Nat)
    (before : chain width left right) : right ≠ width := by
  have := before.2
  omega

/-- The closing edge supplies the disjoint lower triangle. The native
export uses birth order within each row of this triangle. -/
theorem closing_frontier (width left right : Nat) :
    (left < width ∧ right < width) ↔
      chain width left right ∨ (right < left ∧ left < width) := by
  unfold chain
  omega

theorem closing_disjoint (width left right : Nat)
    (before : chain width left right) : ¬ right < left :=
  Nat.not_lt_of_ge before.1

def cycleEdge (width left right : Nat) : Prop :=
  left < width ∧ (right = left + 1 ∧ right < width ∨ left + 1 = width ∧ right = 0)

/-- The square is the least reflexive transitive relation on the cycle's
vertices. An upper-triangle pair follows the open chain. A lower-triangle
pair follows the chain to its last vertex and crosses the closing edge. -/
theorem cycle_least_closed (width : Nat) (relation : Nat → Nat → Prop)
    (reflexive : ∀ rank, rank < width → relation rank rank)
    (contains : ∀ left right, cycleEdge width left right → relation left right)
    (transitive : ∀ a b c, relation a b → relation b c → relation a c)
    (left right : Nat) (leftIn : left < width) (rightIn : right < width) :
    relation left right := by
  have forward (a b : Nat) (within : b < width) (ordered : a ≤ b) : relation a b := by
    induction b with
    | zero =>
      have : a = 0 := by omega
      subst a
      exact reflexive 0 within
    | succ b ih =>
      by_cases last : a = b + 1
      · subst a
        exact reflexive (b + 1) within
      · exact transitive a b (b + 1) (ih (by omega) (by omega))
          (contains b (b + 1) ⟨by omega, Or.inl ⟨rfl, within⟩⟩)
  by_cases ordered : left ≤ right
  · exact forward left right rightIn ordered
  · have lastIn : width - 1 < width := by omega
    have wrap := contains (width - 1) 0 ⟨lastIn, Or.inr ⟨by omega, rfl⟩⟩
    exact transitive left 0 right
      (transitive left (width - 1) 0 (forward left (width - 1) lastIn (by omega)) wrap)
      (forward 0 right rightIn (Nat.zero_le _))

def chainCount : Nat → Nat
  | 0 => 0
  | n + 1 => chainCount n + n + 1

theorem chain_count_doubles (width : Nat) :
    2 * chainCount width = width * (width + 1) := by
  induction width with
  | zero => rfl
  | succ width ih =>
    simp only [chainCount, Nat.add_mul, Nat.mul_add] at *
    omega

theorem closing_budget_difference (width : Nat) :
    2 * (width * width - chainCount width) = width * width - width := by
  have h := chain_count_doubles width
  rw [Nat.mul_add] at h
  have bound : width ≤ width * width := by
    cases width with
    | zero => simp
    | succ width => simp [Nat.mul_succ]
  omega

/-- The recognized batch's first injection births two singletons.
Subsequent open injections add one right column, and the final edge
admits the entire square. These are cumulative output charges. -/
def prefixCharge (width index : Nat) : Nat :=
  if index + 1 = width then width * width else chainCount (index + 2)

theorem first_prefix_charge (width : Nat) (nontrivial : 2 ≤ width) :
    prefixCharge width 0 = 3 := by
  have openPrefix : 0 + 1 ≠ width := by omega
  simp [prefixCharge, openPrefix, chainCount]

theorem open_prefix_charge (width index : Nat) (openPrefix : index + 2 < width) :
    prefixCharge width (index + 1) = prefixCharge width index + index + 3 := by
  have old : index + 1 ≠ width := by omega
  have next : index + 1 + 1 ≠ width := by omega
  simp [prefixCharge, old, next, chainCount]
  omega

theorem closed_prefix_charge (width index : Nat) (closed : index + 1 = width) :
    prefixCharge width index = width * width := by
  simp [prefixCharge, closed]

/-- The source checker still visits each occurrence before checking its
output charge. These two decisions preserve the absolute budget comparison
of the incremental owner for the same admitted prefix. -/
theorem source_cycle_absolute_charge (prior width index limit : Nat)
    (existing : prior ≤ limit) :
    prior + prefixCharge width index ≤ limit ↔
      prefixCharge width index ≤ limit - prior := by
  omega

/-- The open chain installs one forward arc per nonreflexive admitted
pair. They are all internal to the final component. The direct commit
still has to build its owner/member roster and the public export. -/
def retiredForwardArcs (width : Nat) : Nat := chainCount width - width

theorem retired_arc_counts :
    retiredForwardArcs 384 = 73536 ∧ retiredForwardArcs 512 = 130816 := by
  have h384 := chain_count_doubles 384
  have h512 := chain_count_doubles 512
  unfold retiredForwardArcs
  constructor <;> omega

/-- The first injection emits both reflexive births and then its edge.
Later births use the previously admitted roots in roster order. -/
def rosterPrefix (stop : Nat) : List Nat :=
  if stop = 1 then [0] else [1, 0] ++ (List.range (stop - 2)).map (· + 2)

def birthRows (rank : Nat) : List (Nat × Nat) :=
  (rank, rank) :: (rosterPrefix rank).map (·, rank)

def closingRows (rank : Nat) : List (Nat × Nat) :=
  (rosterPrefix rank).map (rank, ·)

/-- The journal roster visits every earlier rank, in its original order. -/
theorem roster_prefix_sizes (stop : Nat) (positive : 0 < stop) :
    (rosterPrefix stop).length = stop := by
  unfold rosterPrefix
  split
  · simp_all
  · simp only [List.length_append, List.length_cons, List.length_nil, List.length_map,
      List.length_range]
    omega

theorem mem_rosterPrefix (rank stop : Nat) (positive : 0 < stop) :
    rank ∈ rosterPrefix stop ↔ rank < stop := by
  unfold rosterPrefix
  split
  · simp_all
  · simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false,
      List.mem_map, List.mem_range]
    constructor
    · rintro ((rfl | rfl) | ⟨i, inside, rfl⟩) <;> omega
    · intro inside
      by_cases first : rank = 0
      · exact Or.inl (Or.inr first)
      by_cases second : rank = 1
      · exact Or.inl (Or.inl second)
      exact Or.inr ⟨rank - 2, by omega, by omega⟩

theorem birth_and_closing_counts (rank : Nat) (positive : 0 < rank) :
    (birthRows rank).length = rank + 1 ∧ (closingRows rank).length = rank := by
  simp [birthRows, closingRows, roster_prefix_sizes rank positive]

def openRows : Nat → List (Nat × Nat)
  | 0 => [(0, 0), (1, 1), (0, 1)]
  | count + 1 => openRows count ++ birthRows (count + 2)

def closeRows : Nat → List (Nat × Nat)
  | 0 => []
  | count + 1 => closeRows count ++ closingRows (count + 1)

/-- Raw singleton roots in journal replay after the first edge and `extra`
open insertions. `insert-components!` prepends each newly born root. -/
def replayRoots : Nat → List Nat
  | 0 => [0, 1]
  | extra + 1 => (extra + 2) :: replayRoots extra

private theorem replay_roots_writer_order (extra : Nat) :
    (replayRoots extra).reverse = rosterPrefix (extra + 2) := by
  induction extra with
  | zero => rfl
  | succ extra ih =>
    rw [replayRoots, List.reverse_cons, ih]
    have old : extra + 2 ≠ 1 := by omega
    have next : extra + 1 + 2 ≠ 1 := by omega
    simp only [rosterPrefix, ite_eq_right old, ite_eq_right next,
      show extra + 2 - 2 = extra by omega, show extra + 1 + 2 - 2 = extra + 1 by omega]
    rw [List.range_succ, List.map_append, List.append_assoc]
    rfl

/-- With singleton owners and ties left at the first root, `merge-cycle!`
starts with the winner's one member and prepends each loser's member in
roster order. The direct source commit therefore preserves the axis order
that would be obtained from the original insertion roster. -/
theorem source_cycle_merge_members (extra winner : Nat) (losers : List Nat)
    (roster : replayRoots extra = winner :: losers) :
    losers.foldl (fun members loser => loser :: members) [winner] =
      rosterPrefix (extra + 2) := by
  have foldOrder (roots members : List Nat) :
      roots.foldl (fun acc root => root :: acc) members = roots.reverse ++ members := by
    induction roots generalizing members with
    | nil => rfl
    | cons root tail ih => simp [ih, List.reverse_cons, List.append_assoc]
  rw [foldOrder, ← List.reverse_cons, ← roster, replay_roots_writer_order]

/-- A direct endpoint directory may store the final owner for every member
of a freshly closed singleton cycle. The old lookup resolves every stored
endpoint through the winner, so the observable lookup agrees even though
the transient loser nodes are absent from the direct directory. -/
theorem source_cycle_resolved_directory (extra winner rank : Nat)
    (losers : List Nat) (roster : replayRoots extra = winner :: losers) :
    (if rank ∈ rosterPrefix (extra + 2) then some winner else none) =
      (if rank ∈ winner :: losers then some winner else none) := by
  have ordered := replay_roots_writer_order extra
  rw [roster] at ordered
  have membership : rank ∈ rosterPrefix (extra + 2) ↔ rank ∈ winner :: losers := by
    rw [← ordered]
    exact List.mem_reverse
  by_cases present : rank ∈ winner :: losers
  · simp [present, membership.mpr present]
  · simp [present, show rank ∉ rosterPrefix (extra + 2) from fun h => present (membership.mp h)]

/-- The newest singleton is first in the roster except at width two,
where the first endpoint wins the equal-size comparison. -/
theorem source_cycle_winner_rank (extra : Nat) :
    (replayRoots extra).head? = some (if extra = 0 then 0 else extra + 1) := by
  cases extra <;> simp [replayRoots, Nat.add_assoc]

/-- The fast path keeps one endpoint entry per rank but allocates only
the final owner record. The replay roster retains a separate record
for each endpoint. These are record counts, not heap accounting bytes. -/
theorem source_cycle_directory_owner_saving (extra : Nat) :
    (replayRoots extra).length = 1 + (extra + 1) := by
  have count := congrArg List.length (replay_roots_writer_order extra)
  rw [List.length_reverse, roster_prefix_sizes (extra + 2) (by omega)] at count
  omega

/-- `collect-roots` pushes selected roots onto an accumulator. Its output
is the selected subsequence of the reversed root spine. -/
def replayCollect (select : Nat → Bool) : List Nat → List Nat → List Nat
  | [], acc => acc
  | head :: tail, acc => replayCollect select tail (if select head then head :: acc else acc)

private theorem replay_collect_order (select : Nat → Bool) (roots acc : List Nat) :
    replayCollect select roots acc = roots.reverse.filter select ++ acc := by
  induction roots generalizing acc with
  | nil => rfl
  | cons head tail ih =>
    rw [replayCollect, ih, List.reverse_cons, List.filter_append]
    cases h : select head <;> simp [h, List.append_assoc]

/-- The reference creates reflexive births, then visits each selected
root pair in left-major order. For the closing injection, each axis is
the same reversed root roster and the frozen mask excludes the open chain. -/
def replayFrontier (new preds succs : List Nat) (present : Nat → Nat → Bool) :
    List (Nat × Nat) :=
  (new.map fun rank => (rank, rank)) ++
    preds.flatMap fun left => ((succs.filter fun right => !(present left right)).map (left, ·))

theorem initial_replay_order :
    replayFrontier [0, 1] [0] [1] (fun left right => decide (left = right)) = openRows 0 := by
  decide

/-- Open-chain roots all reach the tail. The new target reaches only
itself and is absent from the predecessor axis. This reduces the actual
reference axis/filter order to the specialized column. -/
theorem open_replay_order (extra : Nat) :
    let rank := extra + 2
    let preds := replayCollect (fun root => decide (root ≤ rank - 1))
      (rank :: replayRoots extra) []
    replayFrontier [rank] preds [rank] (fun left right =>
      decide (chain rank left right ∨ left = rank ∧ right = rank)) = birthRows rank := by
  dsimp only
  rw [replay_collect_order, List.append_nil, List.reverse_cons, List.filter_append,
    replay_roots_writer_order]
  have keep : (rosterPrefix (extra + 2)).filter (fun root => decide (root ≤ extra + 2 - 1)) =
      rosterPrefix (extra + 2) := List.filter_eq_self.mpr (by
        intro root member
        have := (mem_rosterPrefix root (extra + 2) (by omega)).mp member
        exact decide_eq_true (by omega))
  simp only [keep, List.filter_cons, List.filter_nil, List.append_nil,
    show ¬ extra + 2 ≤ extra + 2 - 1 by omega, decide_false, Bool.false_eq_true, ite_false]
  simp only [replayFrontier, birthRows, List.map_cons, List.map_nil, List.cons_append]
  congr 1
  have emit (roots : List Nat) (earlier : ∀ root ∈ roots, root < extra + 2) :
      (roots.flatMap fun left => ([extra + 2].filter fun right =>
        !decide (chain (extra + 2) left right ∨ left = extra + 2 ∧ right = extra + 2)).map
          (left, ·)) = roots.map (·, extra + 2) := by
    induction roots with
    | nil => rfl
    | cons head tail ih =>
      have headBound := earlier head (by simp)
      have missing : ¬ (chain (extra + 2) head (extra + 2) ∨
          head = extra + 2 ∧ extra + 2 = extra + 2) := by unfold chain; omega
      have rest := ih (fun root member => earlier root (by simp [member]))
      have singleton : ([extra + 2].filter fun right =>
          !decide (chain (extra + 2) head right ∨ head = extra + 2 ∧ right = extra + 2)) =
          [extra + 2] := by
        apply List.filter_eq_self.mpr
        intro right member
        have equal : right = extra + 2 := List.mem_singleton.mp member
        subst right
        rw [decide_eq_false missing]
        rfl
      rw [List.flatMap_cons, rest, singleton]
      rfl
  exact emit _ (fun root member => (mem_rosterPrefix root (extra + 2) (by omega)).mp member)

private theorem filter_earlier_roster (full bound : Nat) (positive : 0 < bound)
    (enough : bound ≤ full) :
    (rosterPrefix full).filter (fun rank => decide (rank < bound)) = rosterPrefix bound := by
  induction full with
  | zero => omega
  | succ full ih =>
    by_cases equal : bound = full + 1
    · subst bound
      apply List.filter_eq_self.mpr
      intro rank member
      exact decide_eq_true ((mem_rosterPrefix rank (full + 1) (by omega)).mp member)
    · have fullEnough : bound ≤ full := by omega
      cases full with
      | zero => omega
      | succ full =>
        cases full with
        | zero =>
          have : bound = 1 := by omega
          subst bound
          decide
        | succ full =>
          have step := replay_roots_writer_order (full + 1)
          rw [replayRoots, List.reverse_cons, replay_roots_writer_order] at step
          rw [← step, List.filter_append, ih fullEnough]
          have omitted : ¬ full + 2 < bound := by omega
          simp [omitted]

private theorem roster_closing_rows (extra : Nat) :
    ((rosterPrefix (extra + 2)).filter fun rank => decide (rank ≠ 0)).flatMap closingRows =
      closeRows (extra + 1) := by
  induction extra with
  | zero => rfl
  | succ extra ih =>
    have step := replay_roots_writer_order (extra + 1)
    rw [replayRoots, List.reverse_cons, replay_roots_writer_order] at step
    rw [← step, List.filter_append, List.flatMap_append, ih]
    simp [closeRows]

theorem closing_replay_order (extra : Nat) :
    let axis := replayCollect (fun _ => true) (replayRoots extra) []
    replayFrontier [] axis axis (fun left right => decide (chain (extra + 2) left right)) =
      closeRows (extra + 1) := by
  dsimp only
  rw [replay_collect_order, List.append_nil, replay_roots_writer_order]
  simp only [List.filter_eq_self.mpr (fun _ _ => rfl :
    ∀ x ∈ rosterPrefix (extra + 2), (fun _ => true) x), replayFrontier, List.map_nil, List.nil_append]
  rw [← roster_closing_rows extra]
  have emit (roots : List Nat) (within : ∀ root ∈ roots, root < extra + 2) :
      (roots.flatMap fun left => ((rosterPrefix (extra + 2)).filter fun right =>
        !decide (chain (extra + 2) left right)).map (left, ·)) =
      (roots.filter fun rank => decide (rank ≠ 0)).flatMap closingRows := by
    induction roots with
    | nil => rfl
    | cons head tail ih =>
      have rest := ih (fun root member => within root (by simp [member]))
      have mask : (rosterPrefix (extra + 2)).filter (fun right =>
          !decide (chain (extra + 2) head right)) =
          (rosterPrefix (extra + 2)).filter (fun right => decide (right < head)) := by
        apply List.filter_congr
        intro right member
        have rightBound := (mem_rosterPrefix right (extra + 2) (by omega)).mp member
        by_cases ordered : head ≤ right
        · have later : ¬ right < head := by omega
          simp [chain, rightBound, ordered, later]
        · have earlier : right < head := by omega
          simp [chain, ordered, earlier]
      by_cases zero : head = 0
      · subst head
        simp [mask, rest]
      · have headBound := within head (by simp)
        have earlier := filter_earlier_roster (extra + 2) head (by omega) (by omega)
        simp [mask, earlier, closingRows, zero, rest]
  exact emit _ (fun root member => (mem_rosterPrefix root (extra + 2) (by omega)).mp member)

/-- Source-only replay concatenates the insertion frontiers before exposing
rows. The earlier three equations check each reference frontier with its
pre-insertion mask, rather than comparing only the final set or cardinality. -/
def replayOpen : Nat → List (Nat × Nat)
  | 0 => replayFrontier [0, 1] [0] [1] (fun left right => decide (left = right))
  | extra + 1 =>
    let rank := extra + 2
    let preds := replayCollect (fun root => decide (root ≤ rank - 1))
      (rank :: replayRoots extra) []
    replayOpen extra ++ replayFrontier [rank] preds [rank] (fun left right =>
      decide (chain rank left right ∨ left = rank ∧ right = rank))

theorem source_cycle_order (extra : Nat) :
    let axis := replayCollect (fun _ => true) (replayRoots extra) []
    replayOpen extra ++
      replayFrontier [] axis axis (fun left right => decide (chain (extra + 2) left right)) =
      openRows extra ++ closeRows (extra + 1) := by
  have openExact (count : Nat) : replayOpen count = openRows count := by
    induction count with
    | zero => exact initial_replay_order
    | succ count ih =>
      rw [replayOpen, ih, openRows, open_replay_order count]
  dsimp only
  rw [openExact, closing_replay_order extra]

/-- The open mask starts at the first two reflexive births and their
edge. Each subsequent source injection marks a fresh diagonal and a
column from all earlier ranks. The terminal mask is read before merge. -/
def replayOpenMask : Nat → Nat → Nat → Prop
  | 0, left, right => (left = 0 ∧ right = 0) ∨ (left = 1 ∧ right = 1) ∨
      (left = 0 ∧ right = 1)
  | extra + 1, left, right => replayOpenMask extra left right ∨
      (right = extra + 2 ∧ left ≤ extra + 2)

theorem source_cycle_open_mask (extra left right : Nat) :
    replayOpenMask extra left right ↔ chain (extra + 2) left right := by
  induction extra with
  | zero => unfold replayOpenMask chain; omega
  | succ extra ih =>
    rw [replayOpenMask, ih, show extra + 1 + 2 = (extra + 2) + 1 by omega]
    exact (chain_birth_frontier (extra + 2) left right).symm

/-- A set-equivalent change to the roster order would already change
the published closing frontier for three vertices. -/
theorem sorted_roster_changes_closing_order :
    replayFrontier [] [0, 1, 2] [0, 1, 2] (fun left right => decide (chain 3 left right)) ≠
      closeRows 2 := by
  decide

theorem mem_openRows (count left right : Nat) :
    (left, right) ∈ openRows count ↔ chain (count + 2) left right := by
  induction count with
  | zero =>
    simp only [openRows, List.mem_cons, List.not_mem_nil, or_false, Prod.mk.injEq, chain]
    omega
  | succ count ih =>
    simp only [openRows, List.mem_append, ih, birthRows, List.mem_cons, Prod.mk.injEq,
      List.mem_map, mem_rosterPrefix _ (count + 2) (by omega)]
    have frontier := chain_birth_frontier (count + 2) left right
    rw [show count + 1 + 2 = count + 2 + 1 by omega, frontier]
    constructor
    · rintro (before | ⟨rfl, rfl⟩ | ⟨i, inside, rfl, rfl⟩)
      · exact Or.inl before
      · exact Or.inr ⟨rfl, Nat.le_refl _⟩
      · exact Or.inr ⟨rfl, by omega⟩
    · rintro (before | ⟨rfl, bound⟩)
      · exact Or.inl before
      · by_cases same : left = count + 2
        · exact Or.inr (Or.inl ⟨same, rfl⟩)
        · exact Or.inr (Or.inr ⟨left, by omega, rfl, rfl⟩)

theorem mem_closeRows (count left right : Nat) :
    (left, right) ∈ closeRows count ↔ right < left ∧ left ≤ count := by
  induction count with
  | zero =>
    simp only [closeRows, List.not_mem_nil, false_iff]
    omega
  | succ count ih =>
    simp only [closeRows, List.mem_append, ih, closingRows, List.mem_map, Prod.mk.injEq,
      mem_rosterPrefix _ (count + 1) (by omega)]
    constructor
    · rintro (⟨lower, bound⟩ | ⟨i, inside, rfl, rfl⟩) <;> omega
    · rintro ⟨lower, bound⟩
      by_cases last : left = count + 1
      · exact Or.inr ⟨right, by omega, last.symm, rfl⟩
      · exact Or.inl ⟨lower, by omega⟩

/-- The traversal enumerates the reachability square. The open and
closing frontiers partition it by traversal rank. -/
theorem mem_complete_cycle_rows (extra left right : Nat) :
    (left, right) ∈ openRows extra ++ closeRows (extra + 1) ↔
      left < extra + 2 ∧ right < extra + 2 := by
  simp only [List.mem_append, mem_openRows, mem_closeRows, chain]
  omega

/-- Membership is both a closure of the input and contained in any
reflexive transitive closure of the input. This describes rank values
after admission of the source walk. -/
theorem complete_cycle_rows_closed (extra : Nat) :
    let rows := openRows extra ++ closeRows (extra + 1)
    (∀ rank, rank < extra + 2 → (rank, rank) ∈ rows) ∧
    (∀ left right, cycleEdge (extra + 2) left right → (left, right) ∈ rows) ∧
    (∀ a b c, (a, b) ∈ rows → (b, c) ∈ rows → (a, c) ∈ rows) := by
  dsimp only
  simp only [mem_complete_cycle_rows]
  refine ⟨fun rank inside => ⟨inside, inside⟩, ?_, ?_⟩
  · intro left right edge
    rcases edge with ⟨inside, ⟨_, target⟩ | ⟨_, rfl⟩⟩
    · exact ⟨inside, target⟩
    · exact ⟨inside, by omega⟩
  · exact fun _ _ _ first second => ⟨first.1, second.2⟩

private theorem rosterPrefix_nodup (stop : Nat) : (rosterPrefix stop).Nodup := by
  unfold rosterPrefix
  split
  · simp
  · apply List.nodup_append.mpr
    refine ⟨by decide, ?_, ?_⟩
    · apply List.Pairwise.map (· + 2) _ List.nodup_range
      intro a b different same
      exact different (by omega)
    · intro a member b other same
      simp only [List.mem_cons, List.not_mem_nil, or_false] at member
      obtain ⟨rank, _, rfl⟩ := List.mem_map.mp other
      omega

private theorem birthRows_nodup (rank : Nat) (positive : 0 < rank) :
    (birthRows rank).Nodup := by
  refine List.nodup_cons.mpr ⟨?_, ?_⟩
  · intro member
    obtain ⟨prior, inside, equal⟩ := List.mem_map.mp member
    have earlier := (mem_rosterPrefix prior rank positive).mp inside
    exact (Nat.ne_of_lt earlier) (congrArg Prod.fst equal)
  · apply List.Pairwise.map (·, rank) _ (rosterPrefix_nodup rank)
    exact fun _ _ different same => different (congrArg Prod.fst same)

theorem openRows_nodup (count : Nat) : (openRows count).Nodup := by
  induction count with
  | zero => decide
  | succ count ih =>
    refine List.nodup_append.mpr ⟨ih, birthRows_nodup _ (by omega), ?_⟩
    intro ⟨left, right⟩ before row member same
    subst row
    have old := ((mem_openRows count left right).mp before).2
    simp only [birthRows, List.mem_cons, List.mem_map, Prod.mk.injEq] at member
    rcases member with ⟨_, equal⟩ | ⟨_, _, _, equal⟩ <;> omega

theorem closeRows_nodup (count : Nat) : (closeRows count).Nodup := by
  induction count with
  | zero => simp [closeRows]
  | succ count ih =>
    refine List.nodup_append.mpr ⟨ih, ?_, ?_⟩
    · apply List.Pairwise.map (count + 1, ·) _ (rosterPrefix_nodup (count + 1))
      exact fun _ _ different same => different (congrArg Prod.snd same)
    · intro ⟨left, right⟩ before row member same
      subst row
      have old := ((mem_closeRows count left right).mp before).2
      obtain ⟨_, _, equal⟩ := List.mem_map.mp member
      have fresh := congrArg Prod.fst equal
      omega

theorem complete_cycle_rows_nodup (extra : Nat) :
    (openRows extra ++ closeRows (extra + 1)).Nodup := by
  refine List.nodup_append.mpr ⟨openRows_nodup extra, closeRows_nodup (extra + 1), ?_⟩
  intro ⟨left, right⟩ before row after same
  subst row
  exact closing_disjoint (extra + 2) left right ((mem_openRows extra left right).mp before)
    ((mem_closeRows (extra + 1) left right).mp after).1

/-- `label` reads the captured axis. The recognizer rejects repeated
vertices, so rank equality and endpoint equality agree inside the cut.
This lifts the exact rank result to the observable Scheme labels. -/
theorem labelled_cycle_rows_exact (extra : Nat) (label : Nat → α)
    (distinct : ∀ i j, i < extra + 2 → j < extra + 2 → label i = label j → i = j) :
    let relabel := fun (row : Nat × Nat) => (label row.1, label row.2)
    let rows := (openRows extra ++ closeRows (extra + 1)).map relabel
    rows.Nodup ∧ ∀ x y, (x, y) ∈ rows ↔
      (∃ i, i < extra + 2 ∧ label i = x) ∧ (∃ j, j < extra + 2 ∧ label j = y) := by
  dsimp only
  constructor
  · let ranks := openRows extra ++ closeRows (extra + 1)
    change (ranks.map fun row => (label row.1, label row.2)).Nodup
    have injectiveOn : ∀ a ∈ ranks, ∀ b ∈ ranks,
        (label a.1, label a.2) = (label b.1, label b.2) → a = b := by
      intro ⟨i, j⟩ a ⟨k, l⟩ b same
      have left := (mem_complete_cycle_rows extra i j).mp a
      have right := (mem_complete_cycle_rows extra k l).mp b
      exact Prod.ext (distinct i k left.1 right.1 (congrArg Prod.fst same))
        (distinct j l left.2 right.2 (congrArg Prod.snd same))
    have nodupMap (xs : List (Nat × Nat)) (unique : xs.Nodup) (inside : xs ⊆ ranks) :
        (xs.map fun row => (label row.1, label row.2)).Nodup := by
      induction xs with
      | nil => simp
      | cons head tail ih =>
        have parts := List.nodup_cons.mp unique
        refine List.nodup_cons.mpr ⟨?_, ih parts.2 (fun _ member => inside (by simp [member]))⟩
        intro repeated
        obtain ⟨row, member, same⟩ := List.mem_map.mp repeated
        have equal := injectiveOn row (inside (by simp [member])) head (inside (by simp)) same
        exact parts.1 (equal ▸ member)
    exact nodupMap ranks (complete_cycle_rows_nodup extra) (fun _ member => member)
  · intro x y
    constructor
    · intro member
      obtain ⟨⟨i, j⟩, within, same⟩ := List.mem_map.mp member
      have bounds := (mem_complete_cycle_rows extra i j).mp within
      exact ⟨⟨i, bounds.1, congrArg Prod.fst same⟩, ⟨j, bounds.2, congrArg Prod.snd same⟩⟩
    · rintro ⟨⟨i, left, rfl⟩, ⟨j, right, rfl⟩⟩
      exact List.mem_map.mpr ⟨(i, j), (mem_complete_cycle_rows extra i j).mpr ⟨left, right⟩, rfl⟩

theorem open_rows_count (count : Nat) : (openRows count).length = chainCount (count + 2) := by
  induction count with
  | zero => rfl
  | succ count ih =>
    simp only [openRows, List.length_append, ih,
      (birth_and_closing_counts (count + 2) (by omega)).1]
    rfl

theorem close_rows_count (count : Nat) : (closeRows count).length = chainCount count := by
  induction count with
  | zero => rfl
  | succ count ih =>
    change (closeRows count ++ closingRows (count + 1)).length =
      chainCount count + (count + 1)
    rw [List.length_append, (birth_and_closing_counts (count + 1) (by omega)).2, ih]

theorem complete_cycle_rows_count (extra : Nat) :
    (openRows extra ++ closeRows (extra + 1)).length = (extra + 2) * (extra + 2) := by
  have upper := open_rows_count extra
  have lower := close_rows_count (extra + 1)
  have triangle := chain_count_doubles (extra + 2)
  simp only [List.length_append, upper]
  have square := Nat.mul_add (extra + 2) (extra + 2) 1
  rw [Nat.mul_one] at square
  change 2 * chainCount (extra + 2) = (extra + 2) * (extra + 2 + 1) at triangle
  have adjacent : chainCount (extra + 2) = chainCount (extra + 1) + (extra + 2) := rfl
  omega

theorem cold_cycle_skips_private_matrix (width : Nat) :
    width + retiredForwardArcs width = chainCount width := by
  have h : width ≤ chainCount width := by
    cases width with
    | zero => simp
    | succ width => simp [chainCount]
  unfold retiredForwardArcs
  omega

end SimpleCycle

end Publication

-- This term counts logical axis entries, not physical heap bytes. Persistent
-- sharing can reduce physical storage, but needs its own ownership/source proof.
def axisEntries : Graph α → Nat
  | .empty => 0
  | .product leading left right => leading.length + left.length + right.length
  | .append first second => axisEntries first + axisEntries second
  | .backwards body => axisEntries body

example : rowCount (Graph.product ([] : List Nat) [0, 1] [0, 1]) = 4 := rfl
example : axisEntries (Graph.product ([] : List Nat) [0, 1] [0, 1]) = 4 := rfl
example : usable ⟨0, 1, 0, 0⟩ ⟨0, 2, 0, 0⟩ = false := rfl
example : rows (Graph.backwards (.product ([] : List Nat) [1, 2] [3, 4])) =
    [[2, 4], [2, 3], [1, 4], [1, 3]] := rfl

end Ascent.OrderedExportGraph
