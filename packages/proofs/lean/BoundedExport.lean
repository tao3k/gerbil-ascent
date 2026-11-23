-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure
import OrderedExportGraph
import RuntimeMeasurement
import RuleGraphClosure

/-! Exact page delivery from a frozen, ordinal-addressable publication.
The logical list is a specification. The page reader uses only its requested
ordinals. The model has no native heap, scheduling, or latency assumption. -/
namespace Ascent.BoundedExport

open ComponentClosure (EdgePath)
open OrderedExportGraph (CutIdentity)

structure IndexedRows (Row : Type) where
  size : Nat
  read : Fin size → Row

def logicalRows (cut : IndexedRows Row) : List Row := List.ofFn cut.read

def readPage (cut : IndexedRows Row) (start width : Nat) : List Row :=
  List.ofFn (n := min width (cut.size - start)) fun i =>
    cut.read ⟨start + i.val, by have := i.isLt; omega⟩

theorem read_page_exact (cut : IndexedRows Row) (start width : Nat) :
    readPage cut start width = ((logicalRows cut).drop start).take width := by
  apply List.ext_getElem
  · simp [readPage, logicalRows]
  · intro i left right
    simp [readPage, logicalRows]

theorem read_page_bounded (cut : IndexedRows Row) (start width : Nat) :
    (readPage cut start width).length = min width (cut.size - start) := by
  simp [readPage]

theorem read_page_and_suffix (cut : IndexedRows Row) (start width : Nat) :
    readPage cut start width ++ (logicalRows cut).drop (start + (readPage cut start width).length) =
      (logicalRows cut).drop start := by
  rw [read_page_bounded, read_page_exact, ← List.drop_drop]
  by_cases fits : width ≤ cut.size - start
  · rw [Nat.min_eq_left fits]
    simpa only [List.drop_drop] using List.take_append_drop width ((logicalRows cut).drop start)
  · have exhausted : ((logicalRows cut).drop start).length = cut.size - start := by
      simp [logicalRows]
    have all : cut.size - start ≤ width := by omega
    have takeAll : ((logicalRows cut).drop start).length ≤ width := exhausted ▸ all
    have dropAll : ((logicalRows cut).drop start).length ≤ cut.size - start :=
      exhausted ▸ Nat.le_refl _
    rw [Nat.min_eq_right all, List.take_of_length_le takeAll,
      List.drop_eq_nil_of_le dropAll, List.append_nil]

structure Publication (Row : Type) where
  identity : CutIdentity
  rows : IndexedRows Row

structure Cursor where
  cut : CutIdentity
  next : Nat
  remaining : Nat
  deriving DecidableEq

/-- Each accepted page commits one cursor advance and one debit. A native
caller must have exclusive access to the destination until the page commits. -/
def pull (cut : Publication Row) (cursor : Cursor)
    (width : Nat) (cancelled : Bool) : Option (List Row × Cursor) :=
  if cancelled || decide (cursor.cut ≠ cut.identity ∨ cut.rows.size ≤ cursor.next ∨ width = 0) then none
  else
    let count := min width (cut.rows.size - cursor.next)
    if count ≤ cursor.remaining then
      some (readPage cut.rows cursor.next width, { cursor with
        next := cursor.next + count
        remaining := cursor.remaining - count })
    else none

theorem cancelled_pull (cut : Publication Row) (cursor : Cursor)
    (width : Nat) : pull cut cursor width true = none := by simp [pull]

theorem stale_pull (cut : Publication Row) (cursor : Cursor)
    (width : Nat) (cancelled : Bool) (stale : cursor.cut ≠ cut.identity) :
    pull cut cursor width cancelled = none := by simp [pull, stale]

theorem exhausted_pull (cut : Publication Row) (cursor : Cursor)
    (width : Nat) (cancelled : Bool) (exhausted : cursor.remaining < min width (cut.rows.size - cursor.next)) :
    pull cut cursor width cancelled = none := by
  simp [pull, Nat.not_le_of_lt exhausted]

theorem accepted_pull (cut : Publication Row) (cursor : Cursor)
    (width : Nat) (cancelled : Bool) (page : List Row) (next : Cursor)
    (accepted : pull cut cursor width cancelled = some (page, next)) :
    next.cut = cursor.cut ∧ 0 < page.length ∧ page.length ≤ width ∧
      next.next = cursor.next + page.length ∧ next.remaining + page.length = cursor.remaining ∧
      page = ((logicalRows cut.rows).drop cursor.next).take width := by
  unfold pull at accepted
  split at accepted
  · contradiction
  · rename_i available
    simp only at accepted
    split at accepted
    · rename_i room
      obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj accepted)
      simp only [Bool.or_eq_true, decide_eq_true_eq, not_or] at available
      obtain ⟨_, _, inside, positive⟩ := available
      refine ⟨rfl, ?_, ?_, ?_, ?_, read_page_exact ..⟩
      · rw [read_page_bounded]; omega
      · rw [read_page_bounded]; omega
      · rw [read_page_bounded]
      · rw [read_page_bounded]
        exact Nat.sub_add_cancel room
    · contradiction

/-- Each binary row owns two destination cells. A page admitted against the
remaining row budget also fits in its independently supplied buffer. -/
theorem accepted_binary_page_fits (cut : Publication (Int × Int))
    (cursor : Cursor) (width capacity : Nat)
    (cancelled : Bool) (page : List (Int × Int)) (next : Cursor)
    (available : 2 * width ≤ capacity)
    (accepted : pull cut cursor width cancelled = some (page, next))
    (ordinal : Nat) (within : ordinal < page.length) :
    2 * ordinal < capacity ∧ 2 * ordinal + 1 < capacity := by
  have bound := (accepted_pull cut cursor width cancelled page next accepted).2.2.1
  omega

/-- Adjacent committed pages on one immutable publication. The trace models
one caller that uses only the returned next cursor. -/
inductive PullTrace (cut : Publication Row) : Cursor → Cursor → List Row → Prop where
  | done (cursor : Cursor) : PullTrace cut cursor cursor []
  | step {start middle finish : Cursor} {page rest : List Row} {width : Nat} :
      pull cut start width false = some (page, middle) → PullTrace cut middle finish rest →
      PullTrace cut start finish (page ++ rest)

theorem completed_pulls_equal_full_result (cut : Publication Row) {start finish : Cursor}
    {delivered : List Row} (trace : PullTrace cut start finish delivered)
    (complete : finish.next = cut.rows.size) : delivered = (logicalRows cut.rows).drop start.next := by
  induction trace with
  | done cursor => simp [complete, logicalRows]
  | @step start middle _ page _ width accepted _ ih =>
    obtain ⟨_, _, _, advance, _, exactPage⟩ := accepted_pull cut start width false page middle accepted
    rw [ih complete, advance, exactPage, ← read_page_exact]
    exact read_page_and_suffix cut.rows start.next width

/-- The final check runs before either externally visible write. The
state models the exclusive destination and the owner-serialized cursor. -/
def commitStaged (current : CutIdentity) (cancelled : Bool) (start : Nat)
    (before : Cursor × List Row) (staged : Option (List Row × Cursor)) : Cursor × List Row :=
  if cancelled || decide (before.1.cut ≠ current) then before else
    match staged with
    | none => before
    | some (page, next) =>
      (next, before.2.take start ++ page ++ before.2.drop (start + page.length))

theorem commit_refusal_preserves_buffer_and_cursor (current : CutIdentity) (cancelled : Bool)
    (start : Nat) (before : Cursor × List Row) (staged : Option (List Row × Cursor))
    (refused : cancelled = true ∨ before.1.cut ≠ current ∨ staged = none) :
    commitStaged current cancelled start before staged = before := by
  rcases refused with rejected | changed | absent
  · simp [commitStaged, rejected]
  · simp [commitStaged, changed]
  · simp [commitStaged, absent]

theorem commit_accepts_both (current : CutIdentity) (start : Nat) (before : Cursor × List Row)
    (page : List Row) (next : Cursor) (unchanged : before.1.cut = current) :
    commitStaged current false start before (some (page, next)) =
      (next, before.2.take start ++ page ++ before.2.drop (start + page.length)) := by
  simp [commitStaged, unchanged]

/-- Whole SCCs may interleave in the public vertex order. Visit each origin
in that order, then its ascending target axis, never the component blocks. -/
theorem interleaved_scc_target_order (origins : List Int) (targets : Int → List Int)
    (originOrder : origins.Pairwise (· < ·))
    (targetOrder : ∀ origin ∈ origins, (targets origin).Pairwise (· < ·)) :
    (origins.flatMap fun a => (targets a).map (a, ·)).Pairwise
      (fun a b => a.1 < b.1 ∨ a.1 = b.1 ∧ a.2 < b.2) := by
  apply List.pairwise_flatMap.2
  constructor
  · intro origin member
    apply List.pairwise_map.2
    exact (targetOrder origin member).imp (fun smaller => Or.inr ⟨rfl, smaller⟩)
  · apply originOrder.imp
    intro left right smaller a fromLeft b fromRight
    obtain ⟨_, _, rfl⟩ := List.mem_map.mp fromLeft
    obtain ⟨_, _, rfl⟩ := List.mem_map.mp fromRight
    exact Or.inl smaller

/-- A quotient-reachability rectangle can use two indexed axes. The rank
encodes the origin-major order and requires one read from each axis. -/
def rectangle (left : Array α) (right : Array β) : IndexedRows (α × β) where
  size := left.size * right.size
  read i :=
    have nonempty : 0 < right.size := by
      apply Nat.pos_of_ne_zero
      intro empty
      have inside := i.isLt
      simp [empty] at inside
    let a := i.val / right.size
    let b := i.val % right.size
    have input := i.isLt
    have aFits : a < left.size := (Nat.div_lt_iff_lt_mul nonempty).2 input
    have bFits : b < right.size := Nat.mod_lt _ nonempty
    (left[a], right[b])

theorem rectangle_rank_round_trip (leftWidth rightWidth rank : Nat)
    (inside : rank < leftWidth * rightWidth) :
    rank / rightWidth < leftWidth ∧ rank % rightWidth < rightWidth ∧
      rightWidth * (rank / rightWidth) + rank % rightWidth = rank := by
  have positive : 0 < rightWidth := by
    apply Nat.pos_of_ne_zero
    intro empty
    simp [empty] at inside
  exact ⟨(Nat.div_lt_iff_lt_mul positive).2 inside, Nat.mod_lt _ positive,
    by simpa [Nat.add_comm] using Nat.mod_add_div rank rightWidth⟩

theorem rectangle_rank_fits (left : Array α) (right : Array β)
    (a : Fin left.size) (b : Fin right.size) :
    right.size * a.val + b.val < (rectangle left right).size := by
  have remaining := b.isLt
  have width := Nat.mul_le_mul_left right.size (Nat.succ_le_of_lt a.isLt)
  rw [Nat.mul_succ] at width
  change right.size * a.val + b.val < left.size * right.size
  rw [Nat.mul_comm left.size right.size]
  omega

theorem rectangle_rank_reads_axes (left : Array α) (right : Array β)
    (a : Fin left.size) (b : Fin right.size) :
    (rectangle left right).read ⟨right.size * a.val + b.val, rectangle_rank_fits left right a b⟩ =
      (left[a.val], right[b.val]) := by
  have positive : 0 < right.size := by have := b.isLt; omega
  have quotient : (right.size * a.val + b.val) / right.size = a.val := by
    rw [Nat.mul_add_div positive, Nat.div_eq_of_lt b.isLt, Nat.add_zero]
  have remainder : (right.size * a.val + b.val) % right.size = b.val := by
    rw [Nat.mul_add_mod, Nat.mod_eq_of_lt b.isLt]
  simp [rectangle, quotient, remainder]

/-- The descriptor covers a whole cross-component product once the quotient
path and member axes have been certified for this publication. A same-SCC
reflexive row needs the existing nonempty-cycle check. -/
theorem rectangle_cross_component_sound {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    (owner : Vertex → Group)
    (connect : ∀ a b, owner a = owner b → a = b ∨ EdgePath edge a b)
    (left right : Array Vertex) {origin destination : Group}
    (quotientPath : EdgePath (ComponentClosure.CrossEdge edge owner) origin destination)
    (leftMembers : ∀ a (inside : a < left.size), owner left[a] = origin)
    (rightMembers : ∀ b (inside : b < right.size), owner right[b] = destination)
    (rank : Fin (rectangle left right).size) :
    EdgePath edge ((rectangle left right).read rank).1 ((rectangle left right).read rank).2 := by
  obtain ⟨aFits, bFits, _⟩ := rectangle_rank_round_trip left.size right.size rank.val rank.isLt
  apply ComponentClosure.lift_cross_component_path connect quotientPath
  · exact leftMembers _ aFits
  · exact rightMembers _ bFits

/-- The million-row projection has only disjoint one-step edges. The source
rule already gives the result, and even positive graph closure adds no pair. -/
def projectionEdge (count a b : Nat) : Prop := a % 2 = 0 ∧ b = a + 1 ∧ a / 2 < count

theorem projection_path_is_edge (count : Nat) {a b : Nat}
    (path : EdgePath (projectionEdge count) a b) : projectionEdge count a b := by
  induction path with
  | step edge => exact edge
  | append _ _ first last =>
    unfold projectionEdge at first last
    omega

theorem projection_scc_is_singleton (count : Nat) {a b : Nat}
    (forward : EdgePath (projectionEdge count) a b)
    (back : EdgePath (projectionEdge count) b a) : False := by
  have first := projection_path_is_edge count forward
  have last := projection_path_is_edge count back
  unfold projectionEdge at first last
  omega

def affineProjection (count offset : Nat) : IndexedRows (Nat × Nat) where
  size := count
  read i := (offset + 2 * i.val, offset + 2 * i.val + 1)

theorem affine_projection_yields_exact_edges (count a b : Nat) :
    (∃ i, (affineProjection count 0).read i = (a, b)) ↔ projectionEdge count a b := by
  constructor
  · rintro ⟨i, equality⟩
    have bounded : i.val < count := i.isLt
    simp [affineProjection, Prod.mk.injEq] at equality
    unfold projectionEdge
    omega
  · rintro ⟨even, adjacent, bounded⟩
    refine ⟨⟨a / 2, bounded⟩, ?_⟩
    change (0 + 2 * (a / 2), 0 + 2 * (a / 2) + 1) = (a, b)
    simp only [Nat.zero_add, Prod.mk.injEq]
    omega

/-- Interleaved 64-bit binary rows in one reusable destination. This counts
payload, and assumes no additional page is retained by the producer. -/
theorem example_page_payload : 2 * 8 * 8192 = 131072 ∧
    (1000000 + 8192 - 1) / 8192 = 123 ∧ (10000000 + 8192 - 1) / 8192 = 1221 := by decide

/-- The count comes from the measured projection cohort. Holding these
collector durations fixed, other work cannot bring P95 under 100 ms. -/
theorem measured_gc_floor (observations : List (Nat × Nat))
    (total : observations.length = 1000)
    (under : (observations.filter fun t => decide (t.1 < 100000000)).length = 936) :
    ¬ (19 * observations.length ≤
      20 * (observations.filter fun t => decide (t.1 + t.2 < 100000000)).length) := by
  apply RuntimeMeasurement.bounded_phase_misses_p95
  omega

/-- Request phases use clock endpoints in the same request. Count export
GC within the delivery interval. -/
theorem whole_list_phase_bounds (start replaced published delivered verified stopped exportGc : Nat)
    (replacement : start ≤ replaced) (publication : replaced ≤ published)
    (delivery : published ≤ delivered) (verification : delivered ≤ verified)
    (receipt : verified ≤ stopped) (gcInside : exportGc ≤ delivered - published) :
    (replaced - start) + (published - replaced) +
        ((delivered - published - exportGc) + exportGc) + (verified - delivered) ≤ stopped - start := by
  omega

/-- The release counter is accepted only within one accounting epoch,
and only if its endpoint is monotone. Other deltas are diagnostic. -/
def observedAllocation (before after : Nat) (rawBefore rawAfter : Int) : Option Nat :=
  if before = after ∧ rawBefore ≤ rawAfter then some (rawAfter - rawBefore).toNat else none

theorem observed_allocation_valid {before after : Nat} {rawBefore rawAfter : Int} {bytes : Nat}
    (valid : observedAllocation before after rawBefore rawAfter = some bytes) :
    before = after ∧ rawAfter = rawBefore + bytes := by
  unfold observedAllocation at valid
  split at valid
  next monotone =>
    have diff : 0 ≤ rawAfter - rawBefore := by omega
    have value := Option.some.inj valid
    exact ⟨monotone.1, by omega⟩
  next => contradiction

/-- Keep the collection interval and the separately timed oracle fixed.
The managed request phases can only add time to this lower bound. -/
theorem whole_list_preserved_phases_limit (observations : List (Nat × Nat × Nat)) (bound : Nat)
    (slow : 20 * (observations.filter fun t => decide (t.1 + t.2.1 < bound)).length <
      19 * observations.length) :
    ¬ (19 * observations.length ≤ 20 *
      (observations.filter fun t => decide (t.1 + t.2.1 + t.2.2 < bound)).length) := by
  let phases := observations.map fun t => (t.1 + t.2.1, t.2.2)
  have phasesSlow : 20 * (phases.filter fun t => decide (t.1 < bound)).length <
      19 * phases.length := by
    simpa [phases, List.filter_map, Function.comp_def] using slow
  simpa [phases, List.filter_map, Function.comp_def] using
    (RuntimeMeasurement.bounded_phase_misses_p95 bound phases phasesSlow)

/-- A successful nonempty page has one owner interval and two handoffs.
Oracle time is measured separately between returned pages. -/
structure PagePhaseTicks where
  send : Nat
  receive : Nat
  stageStart : Nat
  stageEnd : Nat
  copyStart : Nat
  copyEnd : Nat
  post : Nat
  resumed : Nat

theorem directly_measured_page_phases (t : PagePhaseTicks)
    (sent : t.send ≤ t.receive) (entered : t.receive ≤ t.stageStart)
    (staged : t.stageStart ≤ t.stageEnd) (beforeCopy : t.stageEnd ≤ t.copyStart)
    (copied : t.copyStart ≤ t.copyEnd) (beforePost : t.copyEnd ≤ t.post)
    (returned : t.post ≤ t.resumed) :
    (t.receive - t.send) + (t.stageEnd - t.stageStart) +
      (t.copyEnd - t.copyStart) + (t.resumed - t.post) ≤ t.resumed - t.send := by
  omega

/-- Pull clocks enclose the two Actor handoffs, staging and the commit
copy. The independent oracle has disjoint intervals between pulls. -/
theorem paged_request_phase_bounds
    (replace publish openCursor handoff stage copy pulls oracle elapsed gc : Nat)
    (insidePulls : handoff + stage + copy ≤ pulls)
    (insideRequest : replace + publish + openCursor + pulls + oracle ≤ elapsed)
    (gcInside : gc ≤ elapsed) :
    replace + publish + openCursor + handoff + stage + copy + oracle ≤ elapsed ∧
      gc ≤ elapsed := by
  omega

/-- Source replacement and publication precede opening the cursor. The first
pull's validation and writes occupy disjoint subintervals of staging. -/
theorem first_page_phase_bounds (started replaced published opened : Nat) (t : PagePhaseTicks)
    (checkStart checkEnd writeStart writeEnd : Nat)
    (replaceOrder : started ≤ replaced) (publishOrder : replaced ≤ published)
    (openOrder : published ≤ opened) (sent : opened ≤ t.send) (received : t.send ≤ t.receive)
    (entered : t.receive ≤ t.stageStart) (beforeCheck : t.stageStart ≤ checkStart)
    (checked : checkStart ≤ checkEnd) (beforeWrite : checkEnd ≤ writeStart)
    (written : writeStart ≤ writeEnd) (afterWrite : writeEnd ≤ t.stageEnd)
    (beforeCopy : t.stageEnd ≤ t.copyStart) (copied : t.copyStart ≤ t.copyEnd)
    (beforePost : t.copyEnd ≤ t.post) (returned : t.post ≤ t.resumed) :
    (replaced - started) + (published - replaced) + (opened - published) +
      (t.receive - t.send) + (checkEnd - checkStart) + (writeEnd - writeStart) +
      (t.copyEnd - t.copyStart) + (t.resumed - t.post) ≤ t.resumed - started := by
  omega

/-- Here none rejects ordinal runs and zero awaits the first nonterminal
successor. Other directions must agree with every observed step. -/
def observeOrdinalLink (direction : Option Int) (link : Nat × Int) : Option Int :=
  if link.2 < 0 then direction
  else direction.bind fun current =>
    let step := link.2 - (link.1 : Int)
    if (step = 1 ∨ step = -1) ∧ (current = 0 ∨ current = step)
    then some step else none

theorem ordinal_link_matches_scan (direction : Option Int) (origin : Nat) (target : Int)
    (nonterminal : 0 ≤ target) :
    observeOrdinalLink direction (origin, target) =
      direction.bind (fun previous =>
        if (target = (origin : Int) + 1 ∨ target = (origin : Int) - 1) ∧
          (previous = 0 ∨ target = (origin : Int) + previous)
        then some (target - (origin : Int)) else none) := by
  cases direction with
  | none => simp [observeOrdinalLink, show ¬ target < 0 by omega]
  | some previous =>
    simp only [observeOrdinalLink, show ¬ target < 0 by omega, ite_false, Option.bind_some]
    have admissible : (target - (origin : Int) = 1 ∨ target - (origin : Int) = -1) ∧
          (previous = 0 ∨ previous = target - (origin : Int)) ↔
        (target = (origin : Int) + 1 ∨ target = (origin : Int) - 1) ∧
          (previous = 0 ∨ target = (origin : Int) + previous) := by omega
    simp [admissible]

theorem ordinal_link_stream_matches_saved_scan {α : Type}
    (link : α → Nat × Int) (rows : List α) (direction : Option Int) :
    rows.foldl (fun current row => observeOrdinalLink current (link row)) direction =
      (rows.map link).foldl observeOrdinalLink direction := by
  induction rows generalizing direction with
  | nil => rfl
  | cons row rest ih =>
    simp only [List.foldl_cons, List.map_cons]
    exact ih _

/-- The release fixture traversed the chain groups in ascending order
and reversed the ascending edges within each group. -/
def releaseChainCut (ascending : Nat → List Row) (groups : Nat) : List Row :=
  (List.range groups).flatMap fun group => (ascending group).reverse

/-- Prepend ascending edges from the highest remaining group, then
continue with the lower groups. This mirrors the two fixture loops. -/
def prependChainGroups (ascending : Nat → List Row) : Nat → List Row → List Row
  | 0, tail => tail
  | groups + 1, tail =>
    prependChainGroups ascending groups ((ascending groups).foldl (fun acc row => row :: acc) tail)

theorem prepend_chain_groups_matches_release (ascending : Nat → List Row) (groups : Nat)
    (tail : List Row) :
    prependChainGroups ascending groups tail = releaseChainCut ascending groups ++ tail := by
  induction groups generalizing tail with
  | zero => rfl
  | succ groups ih =>
    simp [prependChainGroups, ih, releaseChainCut, List.range_succ, List.append_assoc]

/-- A packed source match compares the entire ordered occurrence stream.
An admitted functional view is a deterministic function of that stream.
The receiving run still checks its current output budget. -/
theorem packed_functional_cache_exact (build : List Row → List Row)
    (captured requested cached : List Row) (room : Nat)
    (matched : requested = captured) (computed : cached = build captured) :
    (if cached.length ≤ room then some cached else none) =
      (if (build requested).length ≤ room then some (build requested) else none) := by
  rw [matched, computed]

/-- The memo is written at the same acceptance point as the publication.
The previous memo survives a refused or stale publication. -/
def installFunctionalCache (accepted current : Bool) (before : Option View) (prepared : View) :
    Option View :=
  if accepted && current then some prepared else before

theorem rejected_run_preserves_functional_cache (accepted current : Bool)
    (before : Option View) (prepared : View) (refused : accepted = false ∨ current = false) :
    installFunctionalCache accepted current before prepared = before := by
  rcases refused with rejected | stale
  · simp [installFunctionalCache, rejected]
  · simp [installFunctionalCache, stale]

/-- The dense functional view retains two u64 lanes, one s32 successor
lane, an s32 origin lookup and the run boundary vector. Count payload in
the 64-bit layout, separately from closures and collector accounting. -/
def denseFunctionalPayload (edges extent runs : Nat) : Nat :=
  20 * edges + 4 * extent + 8 * (runs + 1)

theorem dense_functional_payload_bound (edges extent runs : Nat) (dense : extent ≤ 2 * edges) :
    denseFunctionalPayload edges extent runs ≤ 28 * edges + 8 * (runs + 1) := by
  unfold denseFunctionalPayload
  omega

theorem width_512_alternate_payload :
    16 * (77 * 511) + denseFunctionalPayload (77 * 511) (77 * 512 - 1) 77 = 1574808 := by
  decide

/-- An alternate cache edge contributes only objects that are unreachable
from the current publication and every other retained root. -/
theorem exclusive_alternate_roots {Object : Type} (retained alternate : Object → Prop)
    (object : Object) :
    ((retained object ∨ alternate object) ∧ ¬ retained object) ↔
      alternate object ∧ ¬ retained object := by
  constructor
  · rintro ⟨known | extra, absent⟩
    · exact False.elim (absent known)
    · exact ⟨extra, absent⟩
  · exact fun h => ⟨Or.inr h.1, h.2⟩

/-- A monotone collection counter sampled at phase boundaries counts each
collection once, including collections before the first page. -/
theorem paged_collection_phase_counts (before replaced published opened done : Nat)
    (replaceOrder : before ≤ replaced) (publishOrder : replaced ≤ published)
    (openOrder : published ≤ opened) (doneOrder : opened ≤ done) :
    (replaced - before) + (published - replaced) + (opened - published) +
      (done - opened) = done - before := by
  omega

/-- The producer clips the current window to the remaining page extent.
It can resume at the resulting ordinal or advance to the next window. -/
theorem clip_window_at_page_boundary (start stop room : Nat) (ordered : start ≤ stop) :
    let n := min (stop - start) room
    start + n ≤ stop ∧ n ≤ room ∧ (start + n = stop ∨ n = room) := by
  simp only
  omega

/-- The two cursor directions start the next batch at the field after the
last delivered row. The signed stride can be negative. -/
theorem clipped_window_resume_field (first stride : Int) (windowStart consumed relative : Nat) :
    first + (windowStart + consumed + relative : Nat) * stride =
      (first + (windowStart : Int) * stride + (consumed : Int) * stride) + (relative : Int) * stride := by
  simp [Int.add_mul, Int.add_assoc]

section FrozenRuntime

open RuleGraphClosure (Reachable)

/-- A process minimum is a resize hint. The frozen setter stores the
parameter and changes neither mapped space nor occupancy. -/
structure HeapSnapshot where
  minimumBytes : Nat
  mappedBytes : Nat
  occupiedBytes : Nat

def availableBytes (heap : HeapSnapshot) : Nat := heap.mappedBytes - heap.occupiedBytes

def changeMinimum (heap : HeapSnapshot) (minimumBytes : Nat) : HeapSnapshot :=
  { heap with minimumBytes := minimumBytes }

theorem minimum_setter_grants_no_capacity (heap : HeapSnapshot) (minimum : Nat) :
    availableBytes (changeMinimum heap minimum) = availableBytes heap := rfl

/-- Even a successful resize, followed by a free-space observation, is
only a shared-capacity observation until the allocator grants ownership. -/
theorem observed_capacity_can_be_consumed (heap : HeapSnapshot) (needed other : Nat)
    (fits : needed ≤ availableBytes heap)
    (otherFits : other ≤ availableBytes heap)
    (competition : availableBytes heap < needed + other) :
    needed ≤ availableBytes heap ∧
      availableBytes { heap with occupiedBytes := heap.occupiedBytes + other } < needed := by
  refine ⟨fits, ?_⟩
  unfold availableBytes at *
  simp only at *
  omega

inductive PairCell where
  | outer | inner | child
  deriving DecidableEq

/-- After the caller saves the inner pair, drops the outer head, and
writes a new pair-valued field, both the alias and its child are live.
A still header on the inner pair does not remove the field edge. -/
theorem saved_interior_pair_keeps_child :
    let root := fun cell : PairCell => cell = .inner
    let edge := fun (a b : PairCell) => a = .inner ∧ b = .child
    ¬ Reachable edge root .outer ∧ Reachable edge root .inner ∧ Reachable edge root .child := by
  dsimp
  refine ⟨?_, .seed rfl, .follow (.seed rfl) ⟨rfl, rfl⟩⟩
  intro reached
  cases reached with
  | seed root => cases root
  | follow _ links => cases links.2

end FrozenRuntime

def orderedRunTargets (targetAt : Nat → Int) (lo hi : Nat) (forward : Bool) : Prop :=
  ∀ i j, lo ≤ i → i < j → j < hi →
    if forward then targetAt i < targetAt j else targetAt j < targetAt i

/-- In a certified run the target is the adjacent edge's origin.
Forward edge inequalities therefore give strict order over the whole run. -/
theorem right_selection_targets_increase
    (targetAt : Nat → Int) (lo hi : Nat) (forward : Bool)
    (adjacent : ∀ i, lo ≤ i → i + 1 < hi →
      if forward then targetAt i < targetAt (i + 1)
      else targetAt (i + 1) < targetAt i) :
    orderedRunTargets targetAt lo hi forward := by
  intro i j low before high
  have span : ∀ d, i + d + 1 < hi →
      if forward then targetAt i < targetAt (i + d + 1)
      else targetAt (i + d + 1) < targetAt i := by
    intro d
    induction d with
    | zero =>
      intro inside
      simpa using adjacent i low (by omega)
    | succ d ih =>
      intro inside
      have left := ih (by omega)
      have right := adjacent (i + d + 1) (by omega) (by omega)
      have next : i + (d + 1) + 1 = i + d + 1 + 1 := by omega
      rw [next]
      cases forward <;> simp_all <;> omega
  have equal : i + (j - i - 1) + 1 = j := by omega
  simpa only [equal] using span (j - i - 1) (by omega)

/-- A match survives the same half-open interval update used by the Scheme
binary search. The comparison is flipped for descending storage. -/
theorem right_selection_search_keeps_match
    (targetAt : Nat → Int) (lo hi middle hit : Nat) (forward : Bool)
    (sorted : orderedRunTargets targetAt lo hi forward)
    (middleIn : lo ≤ middle ∧ middle < hi) (hitIn : lo ≤ hit ∧ hit < hi)
    (different : hit ≠ middle) :
    if (if forward then targetAt middle < targetAt hit else targetAt hit < targetAt middle)
      then middle + 1 ≤ hit ∧ hit < hi
      else lo ≤ hit ∧ hit < middle := by
  unfold orderedRunTargets at sorted
  by_cases before : hit < middle
  · have order := sorted hit middle hitIn.1 before middleIn.2
    cases forward <;> simp_all [Int.not_lt_of_ge (Int.le_of_lt order)]
  · have after : middle < hit := by omega
    have order := sorted middle hit middleIn.1 after hitIn.2
    cases forward <;> simp_all <;> omega

/-- At each depth a fixed target gives at most one origin per run.
The two formulas correspond to advancing opposite to the edge direction. -/
theorem right_selection_predecessor_ordinals (lo hi edge depth : Nat)
    (edgeIn : lo ≤ edge ∧ edge < hi) :
    (depth ≤ edge - lo ↔ lo ≤ edge - depth ∧ depth ≤ edge) ∧
    (depth < hi - edge ↔ lo ≤ edge + depth ∧ edge + depth < hi) := by
  omega

/-- Filtering the alternating complete result by target preserves each
depth group and its order, including the reversed groups. -/
theorem right_selection_filter_depth_order (groups : List (Bool × List α))
    (accept : α → Bool) :
    (groups.flatMap (fun g => if g.1 then g.2.reverse else g.2)).filter accept =
      groups.flatMap (fun g =>
        if g.1 then (g.2.filter accept).reverse else g.2.filter accept) := by
  induction groups with
  | nil => rfl
  | cons g rest ih =>
    rcases g with ⟨reverse, rows⟩
    cases reverse <;> simp [List.filter_append, List.filter_reverse, ih]

end Ascent.BoundedExport

#print axioms Ascent.BoundedExport.completed_pulls_equal_full_result
#print axioms Ascent.BoundedExport.accepted_pull
#print axioms Ascent.BoundedExport.rectangle_rank_reads_axes
#print axioms Ascent.BoundedExport.rectangle_cross_component_sound
#print axioms Ascent.BoundedExport.projection_path_is_edge
#print axioms Ascent.BoundedExport.measured_gc_floor
#print axioms Ascent.BoundedExport.whole_list_phase_bounds
#print axioms Ascent.BoundedExport.observed_allocation_valid
#print axioms Ascent.BoundedExport.whole_list_preserved_phases_limit
#print axioms Ascent.BoundedExport.saved_interior_pair_keeps_child
#print axioms Ascent.BoundedExport.observed_capacity_can_be_consumed
#print axioms Ascent.BoundedExport.commit_refusal_preserves_buffer_and_cursor
#print axioms Ascent.BoundedExport.interleaved_scc_target_order
#print axioms Ascent.BoundedExport.directly_measured_page_phases
#print axioms Ascent.BoundedExport.paged_request_phase_bounds
#print axioms Ascent.BoundedExport.first_page_phase_bounds
#print axioms Ascent.BoundedExport.ordinal_link_matches_scan
#print axioms Ascent.BoundedExport.ordinal_link_stream_matches_saved_scan
#print axioms Ascent.BoundedExport.prepend_chain_groups_matches_release
#print axioms Ascent.BoundedExport.packed_functional_cache_exact
#print axioms Ascent.BoundedExport.rejected_run_preserves_functional_cache
#print axioms Ascent.BoundedExport.dense_functional_payload_bound
#print axioms Ascent.BoundedExport.width_512_alternate_payload
#print axioms Ascent.BoundedExport.exclusive_alternate_roots
#print axioms Ascent.BoundedExport.paged_collection_phase_counts
#print axioms Ascent.BoundedExport.clip_window_at_page_boundary
#print axioms Ascent.BoundedExport.clipped_window_resume_field

#print axioms Ascent.BoundedExport.right_selection_search_keeps_match
#print axioms Ascent.BoundedExport.right_selection_predecessor_ordinals
#print axioms Ascent.BoundedExport.right_selection_filter_depth_order
#print axioms Ascent.BoundedExport.right_selection_targets_increase
