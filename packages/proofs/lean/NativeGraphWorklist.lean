-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import RuleGraphClosure

/-!
A list model for `gerbil-ascent-graph-close!`. `selected` represents true
bits of the native bitmap; `pending` has the native LIFO order. The list
machine uses the same mark-before-enqueue branch as the Gerbil loop. The
proof relates one pop and its complete adjacency scan to the extensional
worklist transition. It does not extract or execute Gerbil source.
-/

namespace Ascent.NativeGraphWorklist

universe u
variable {Key : Type u} [DecidableEq Key]

structure Work (Key : Type u) where
  selected : List Key
  pending : List Key

def enqueue (work : Work Key) (target : Key) : Work Key :=
  if target ∈ work.selected then work else
    { selected := target :: work.selected
      pending := target :: work.pending }

def scan : List Key → Work Key → Work Key
  | [], work => work
  | target :: rest, work => scan rest (enqueue work target)

def pop (adj : Key → List Key) (work : Work Key) : Work Key :=
  match work.pending with
  | [] => work
  | source :: rest =>
      scan (adj source) { selected := work.selected, pending := rest }

def abstract (work : Work Key) : RuleGraphClosure.Work Key :=
  ⟨fun key => key ∈ work.selected, fun key => key ∈ work.pending⟩

theorem enqueue_selected (work : Work Key) (target key : Key) :
    key ∈ (enqueue work target).selected ↔
      key ∈ work.selected ∨ key = target := by
  unfold enqueue
  by_cases hit : target ∈ work.selected
  · simp [hit]
    intro same
    subst key
    exact hit
  · simp [hit, List.mem_cons, or_comm]

theorem enqueue_pending (work : Work Key) (target key : Key) :
    key ∈ (enqueue work target).pending ↔
      key ∈ work.pending ∨ (key = target ∧ target ∉ work.selected) := by
  unfold enqueue
  by_cases hit : target ∈ work.selected
  · simp [hit]
  · simp [hit, List.mem_cons, or_comm]

theorem scan_selected (targets : List Key) (work : Work Key) (key : Key) :
    key ∈ (scan targets work).selected ↔
      key ∈ work.selected ∨ key ∈ targets := by
  induction targets generalizing work with
  | nil => simp [scan]
  | cons target rest ih =>
      change key ∈ (scan rest (enqueue work target)).selected ↔ _
      rw [ih, enqueue_selected]
      simp [List.mem_cons, or_assoc, or_left_comm, or_comm]

theorem scan_pending (targets : List Key) (work : Work Key) (key : Key) :
    key ∈ (scan targets work).pending ↔
      key ∈ work.pending ∨ (key ∈ targets ∧ key ∉ work.selected) := by
  induction targets generalizing work with
  | nil => simp [scan]
  | cons target rest ih =>
      change key ∈ (scan rest (enqueue work target)).pending ↔ _
      rw [ih, enqueue_pending, enqueue_selected]
      simp only [List.mem_cons]
      by_cases fresh : target ∈ work.selected
      · by_cases same : key = target
        · subst key
          simp [fresh]
        · simp [fresh, same]
      · by_cases same : key = target
        · subst key
          simp [fresh]
        · simp [fresh, same, or_comm]

def edge (adj : Key → List Key) (source target : Key) : Prop :=
  target ∈ adj source

/-- One native list pop simulates exactly one abstract worklist visit.
Duplicates in the adjacency do not change the selected or pending sets. -/
theorem pop_simulates (adj : Key → List Key) (work : Work Key)
    (source : Key) (rest : List Key)
    (pending : work.pending = source :: rest) :
    ∀ key,
      (abstract (pop adj work)).selected key ↔
        (RuleGraphClosure.visit (edge adj) (abstract work) source).selected key := by
  intro key
  simp [pop, pending, abstract, RuleGraphClosure.visit,
    scan_selected, edge]

theorem pop_pending_simulates (adj : Key → List Key) (work : Work Key)
    (source : Key) (rest : List Key)
    (pending : work.pending = source :: rest)
    (noDup : work.pending.Nodup) :
    ∀ key,
      (abstract (pop adj work)).pending key ↔
        (RuleGraphClosure.visit (edge adj) (abstract work) source).pending key := by
  intro key
  have headFresh : source ∉ rest := by
    rw [pending] at noDup
    exact (List.nodup_cons.mp noDup).1
  simp only [pop, pending, abstract, RuleGraphClosure.visit,
    scan_pending, edge, List.mem_cons]
  by_cases same : key = source
  · subst key
    simp [headFresh]
  · simp [same]

/-- The pending list order is erased only after proving the exact one-step
selected and pending membership correspondence. -/
theorem pop_refines (adj : Key → List Key) (work : Work Key)
    (source : Key) (rest : List Key)
    (pending : work.pending = source :: rest)
    (noDup : work.pending.Nodup) :
    abstract (pop adj work) =
      RuleGraphClosure.visit (edge adj) (abstract work) source := by
  have selectedEqual : (abstract (pop adj work)).selected =
      (RuleGraphClosure.visit (edge adj) (abstract work) source).selected := by
    funext key
    exact propext (pop_simulates adj work source rest pending key)
  have pendingEqual : (abstract (pop adj work)).pending =
      (RuleGraphClosure.visit (edge adj) (abstract work) source).pending := by
    funext key
    exact propext (pop_pending_simulates adj work source rest pending noDup key)
  cases left : abstract (pop adj work) with
  | mk leftSelected leftPending =>
    cases right : RuleGraphClosure.visit (edge adj) (abstract work) source with
    | mk rightSelected rightPending =>
      rw [left, right] at selectedEqual pendingEqual
      cases selectedEqual
      cases pendingEqual
      rfl

def WellFormed (work : Work Key) : Prop :=
  work.selected.Nodup ∧ work.pending.Nodup ∧
    ∀ key, key ∈ work.pending → key ∈ work.selected

theorem enqueue_wellformed (work : Work Key) (target : Key)
    (valid : WellFormed work) : WellFormed (enqueue work target) := by
  rcases valid with ⟨selectedNoDup, pendingNoDup, pendingSelected⟩
  unfold enqueue
  by_cases hit : target ∈ work.selected
  · simpa [hit, WellFormed] using
      (show work.selected.Nodup ∧ work.pending.Nodup ∧
        (∀ key, key ∈ work.pending → key ∈ work.selected) from
        ⟨selectedNoDup, pendingNoDup, pendingSelected⟩)
  · have freshPending : target ∉ work.pending := by
      intro member
      exact hit (pendingSelected target member)
    simp only [hit, ↓reduceIte, WellFormed]
    constructor
    · exact List.nodup_cons.mpr ⟨hit, selectedNoDup⟩
    constructor
    · exact List.nodup_cons.mpr ⟨freshPending, pendingNoDup⟩
    · intro key member
      rcases List.mem_cons.mp member with same | old
      · exact List.mem_cons.mpr (Or.inl same)
      · exact List.mem_cons.mpr (Or.inr (pendingSelected key old))

theorem scan_wellformed (targets : List Key) (work : Work Key)
    (valid : WellFormed work) : WellFormed (scan targets work) := by
  induction targets generalizing work with
  | nil => exact valid
  | cons target rest ih =>
      exact ih (enqueue work target) (enqueue_wellformed work target valid)

theorem pop_wellformed (adj : Key → List Key) (work : Work Key)
    (valid : WellFormed work) : WellFormed (pop adj work) := by
  cases pending : work.pending with
  | nil => simpa [pop, pending] using valid
  | cons source rest =>
      rcases valid with ⟨selectedNoDup, pendingNoDup, pendingSelected⟩
      have tailNoDup : rest.Nodup := by
        rw [pending] at pendingNoDup
        exact (List.nodup_cons.mp pendingNoDup).2
      have tailSelected : ∀ key, key ∈ rest → key ∈ work.selected := by
        intro key member
        apply pendingSelected
        rw [pending]
        exact List.mem_cons.mpr (Or.inr member)
      simpa [pop, pending] using
        scan_wellformed (adj source) { selected := work.selected, pending := rest }
          ⟨selectedNoDup, tailNoDup, tailSelected⟩

def Processed (work : Work Key) (key : Key) : Prop :=
  key ∈ work.selected ∧ key ∉ work.pending

/-- Once a selected key is no longer pending, later scans cannot enqueue it. -/
theorem pop_processed_preserved (adj : Key → List Key) (work : Work Key)
    (source key : Key) (rest : List Key)
    (head : work.pending = source :: rest)
    (processed : Processed work key) :
    Processed (pop adj work) key := by
  rcases processed with ⟨selected, notPending⟩
  constructor
  · have member := (scan_selected (adj source)
        { selected := work.selected, pending := rest } key).mpr (Or.inl selected)
    simpa [pop, head] using member
  · intro pendingAfter
    have member : key ∈
        (scan (adj source) { selected := work.selected, pending := rest }).pending := by
      simpa [pop, head] using pendingAfter
    rcases (scan_pending (adj source)
      { selected := work.selected, pending := rest } key).mp member with
      inRest | fresh
    · apply notPending
      rw [head]
      simp [inRest]
    · exact fresh.2 selected

/-- Mark-before-enqueue also prevents the popped key's self-loop from
returning to pending. -/
theorem pop_source_processed (adj : Key → List Key) (work : Work Key)
    (source : Key) (rest : List Key)
    (head : work.pending = source :: rest)
    (valid : WellFormed work) :
    Processed (pop adj work) source := by
  have sourcePending : source ∈ work.pending := by rw [head]; simp
  have sourceSelected := valid.2.2 source sourcePending
  have sourceNotRest : source ∉ rest := by
    have noDup := valid.2.1
    rw [head] at noDup
    exact (List.nodup_cons.mp noDup).1
  constructor
  · have member := (scan_selected (adj source)
        { selected := work.selected, pending := rest } source).mpr
          (Or.inl sourceSelected)
    simpa [pop, head] using member
  · intro pendingAfter
    have member : source ∈
        (scan (adj source) { selected := work.selected, pending := rest }).pending := by
      simpa [pop, head] using pendingAfter
    rcases (scan_pending (adj source)
      { selected := work.selected, pending := rest } source).mp member with
      inRest | fresh
    · exact sourceNotRest inRest
    · exact fresh.2 sourceSelected

def initial (seeds : List Key) : Work Key := ⟨seeds, seeds⟩

omit [DecidableEq Key] in
theorem initial_wellformed (seeds : List Key) (noDup : seeds.Nodup) :
    WellFormed (initial seeds) :=
  ⟨noDup, noDup, fun _ member => member⟩

inductive Run (adj : Key → List Key) : Work Key → Work Key → Type u where
  | refl (work) : Run adj work work
  | next {before after : Work Key} {rest : List Key}
      (source : Key) (head : before.pending = source :: rest) :
      Run adj (pop adj before) after → Run adj before after

def Run.trace {adj : Key → List Key} {before after : Work Key} :
    Run adj before after → List Key
  | .refl _ => []
  | .next source _ tail => source :: tail.trace

/-- Every finite native-shaped run refines the abstract worklist run. The
native initial bitmap contributes one pending entry per selected key. -/
theorem run_refines (adj : Key → List Key)
    {before after : Work Key} (run : Run adj before after)
    (valid : WellFormed before) :
    RuleGraphClosure.Run (edge adj) (abstract before) (abstract after) := by
  induction run with
  | refl => exact RuleGraphClosure.Run.refl _
  | next source head _ ih =>
      have nextValid := pop_wellformed adj _ valid
      have headNoDup := valid.2.1
      have refined := pop_refines adj _ source _ head headNoDup
      apply RuleGraphClosure.Run.next source
      · simp [abstract, head]
      · simpa [refined] using ih nextValid

theorem run_processed_preserved (adj : Key → List Key)
    {before after : Work Key} (run : Run adj before after)
    (valid : WellFormed before) (key : Key)
    (processed : Processed before key) : Processed after key := by
  induction run with
  | refl => exact processed
  | next source head _ ih =>
      exact ih (pop_wellformed adj _ valid)
        (pop_processed_preserved adj _ source key _ head processed)

/-- After a pop, no later visit can put that source back on the worklist. -/
theorem popped_never_pending (adj : Key → List Key)
    (before after : Work Key) (source : Key) (rest : List Key)
    (head : before.pending = source :: rest)
    (valid : WellFormed before)
    (tail : Run adj (pop adj before) after) : source ∉ after.pending := by
  exact (run_processed_preserved adj tail (pop_wellformed adj before valid)
    source (pop_source_processed adj before source rest head valid)).2

theorem trace_avoids_processed (adj : Key → List Key)
    {before after : Work Key} (run : Run adj before after)
    (valid : WellFormed before) (key : Key)
    (processed : Processed before key) : key ∉ run.trace := by
  induction run with
  | refl => simp [Run.trace]
  | next source head _ ih =>
      intro member
      rcases List.mem_cons.mp member with same | later
      · subst key
        exact processed.2 (by rw [head]; simp)
      · exact ih (pop_wellformed adj _ valid)
          (pop_processed_preserved adj _ source key _ head processed) later

theorem trace_nodup (adj : Key → List Key)
    {before after : Work Key} (run : Run adj before after)
    (valid : WellFormed before) : run.trace.Nodup := by
  induction run with
  | refl => simp [Run.trace]
  | next source head tail ih =>
      have nextValid := pop_wellformed adj _ valid
      apply List.nodup_cons.mpr
      constructor
      · exact trace_avoids_processed adj tail nextValid source
          (pop_source_processed adj _ source _ head valid)
      · exact ih nextValid

/-- Dense native vertex IDs bound every finite execution trace by the
vector length, regardless of cycles or duplicate adjacency entries. -/
theorem trace_length_le_count (count : Nat)
    (adj : Fin count → List (Fin count))
    {before after : Work (Fin count)}
    (run : Run adj before after) (valid : WellFormed before) :
    run.trace.length ≤ count := by
  have unique := trace_nodup adj run valid
  have subset : run.trace ⊆ List.finRange count := by
    intro vertex _
    exact List.mem_finRange vertex
  simpa using unique.length_le_of_subset subset

/-- An executable bounded driver for the native-shaped list machine.
`fuel` bounds pops, not logical recursion depth or model reasoning. -/
def runFuel (adj : Key → List Key) : Nat → Work Key → Work Key
  | 0, work => work
  | _ + 1, ⟨selected, []⟩ => ⟨selected, []⟩
  | fuel + 1, ⟨selected, source :: rest⟩ =>
      runFuel adj fuel (pop adj ⟨selected, source :: rest⟩)

def runFuel_run (adj : Key → List Key) :
    (fuel : Nat) → (work : Work Key) →
      Run adj work (runFuel adj fuel work)
  | 0, work => Run.refl work
  | _ + 1, ⟨selected, []⟩ => Run.refl ⟨selected, []⟩
  | fuel + 1, ⟨selected, source :: rest⟩ =>
      Run.next source rfl
        (runFuel_run adj fuel (pop adj ⟨selected, source :: rest⟩))

/-- If pending survives a fuel budget, every budgeted pop occurred. -/
theorem runFuel_trace_length_if_pending (adj : Key → List Key)
    (fuel : Nat) (work : Work Key)
    (pending : (runFuel adj fuel work).pending ≠ []) :
    (runFuel_run adj fuel work).trace.length = fuel := by
  induction fuel generalizing work with
  | zero => simp [runFuel_run, Run.trace]
  | succ fuel ih =>
      cases work with
      | mk selected entries =>
          cases entries with
          | nil => simp [runFuel] at pending
          | cons source rest =>
              let current : Work Key := ⟨selected, source :: rest⟩
              have tailPending : (runFuel adj fuel (pop adj current)).pending ≠ [] := by
                simpa [runFuel, current] using pending
              have lengthTail := ih (pop adj current) tailPending
              simp [runFuel_run, runFuel, current, Run.trace, lengthTail]

/-- A dense vector of `count` vertices needs at most `count` actual pops.
With one extra fuel slot, a nonempty pending list would force too many
distinct popped IDs. -/
theorem runFuel_complete (count : Nat)
    (adj : Fin count → List (Fin count))
    (work : Work (Fin count)) (valid : WellFormed work) :
    (runFuel adj (count + 1) work).pending = [] := by
  cases pending : (runFuel adj (count + 1) work).pending with
  | nil => rfl
  | cons source rest =>
      have nonempty : (runFuel adj (count + 1) work).pending ≠ [] := by
        rw [pending]
        simp
      have used := runFuel_trace_length_if_pending adj (count + 1) work nonempty
      have bound := trace_length_le_count count adj
        (runFuel_run adj (count + 1) work) valid
      omega

/-- The list machine's terminal selection is the least reachability closure.
There is no assumption about list order or the number of adjacency duplicates. -/
theorem completed_exact (adj : Key → List Key)
    (seeds : List Key) (noDup : seeds.Nodup)
    (after : Work Key)
    (run : Run adj (initial seeds) after)
    (done : after.pending = []) (key : Key) :
    key ∈ after.selected ↔
      RuleGraphClosure.Reachable (edge adj) (fun k => k ∈ seeds) key := by
  have abstractRun := run_refines adj run (initial_wellformed seeds noDup)
  have invariant := RuleGraphClosure.run_invariant (edge adj)
    (fun k => k ∈ seeds) abstractRun
    (RuleGraphClosure.initial_invariant (edge adj) (fun k => k ∈ seeds))
  exact RuleGraphClosure.completed_exact (edge adj) (fun k => k ∈ seeds)
    (abstract after) invariant
    (by intro candidate; change candidate ∉ after.pending; simp [done]) key

/-- The native-shaped list machine and the abstract rule compiler compose:
terminal selection has no missing or extra rule-read successors. -/
theorem completed_compiled_exact
    (plans : List (RuleGraphClosure.Rule Key))
    (seeds : List Key) (noDup : seeds.Nodup)
    (after : Work Key)
    (run : Run (RuleGraphClosure.ruleSuccessors plans) (initial seeds) after)
    (done : after.pending = []) (key : Key) :
    key ∈ after.selected ↔
      RuleGraphClosure.Reachable (RuleGraphClosure.ReadsInto plans)
        (fun k => k ∈ seeds) key := by
  exact (completed_exact (RuleGraphClosure.ruleSuccessors plans)
    seeds noDup after run done key).trans
    (RuleGraphClosure.reachable_congr
      (edge (RuleGraphClosure.ruleSuccessors plans))
      (RuleGraphClosure.ReadsInto plans) (fun k => k ∈ seeds)
      (fun source target => RuleGraphClosure.mem_ruleSuccessors_iff plans source target)
      key)

theorem completed_compiled_closed
    (plans : List (RuleGraphClosure.Rule Key))
    (seeds : List Key) (noDup : seeds.Nodup)
    (after : Work Key)
    (run : Run (RuleGraphClosure.ruleSuccessors plans) (initial seeds) after)
    (done : after.pending = []) :
    DependencyInvalidation.Closed (RuleGraphClosure.ReadsInto plans)
      (fun key => key ∈ after.selected) := by
  intro source target read selected
  have reached := (completed_compiled_exact plans seeds noDup after run done source).mp selected
  exact (completed_compiled_exact plans seeds noDup after run done target).mpr
    (RuleGraphClosure.Reachable.follow reached read)

/-- The executable dense-key model terminates and computes exact closure
without a `done` premise. This is a proof about the Lean list machine. -/
theorem runFuel_exact (count : Nat)
    (adj : Fin count → List (Fin count))
    (seeds : List (Fin count)) (noDup : seeds.Nodup)
    (key : Fin count) :
    key ∈ (runFuel adj (count + 1) (initial seeds)).selected ↔
      RuleGraphClosure.Reachable (edge adj) (fun k => k ∈ seeds) key := by
  exact completed_exact adj seeds noDup _
    (runFuel_run adj (count + 1) (initial seeds))
    (runFuel_complete count adj (initial seeds)
      (initial_wellformed seeds noDup)) key

theorem runFuel_compiled_exact (count : Nat)
    (plans : List (RuleGraphClosure.Rule (Fin count)))
    (seeds : List (Fin count)) (noDup : seeds.Nodup)
    (key : Fin count) :
    key ∈ (runFuel (RuleGraphClosure.ruleSuccessors plans)
        (count + 1) (initial seeds)).selected ↔
      RuleGraphClosure.Reachable (RuleGraphClosure.ReadsInto plans)
        (fun k => k ∈ seeds) key := by
  exact completed_compiled_exact plans seeds noDup _
    (runFuel_run (RuleGraphClosure.ruleSuccessors plans)
      (count + 1) (initial seeds))
    (runFuel_complete count (RuleGraphClosure.ruleSuccessors plans)
      (initial seeds) (initial_wellformed seeds noDup)) key

/-- The executable dense-key closure supplies the frame theorem's affected
set premise without an externally assumed worklist completion. -/
theorem runFuel_compiled_closed (count : Nat)
    (plans : List (RuleGraphClosure.Rule (Fin count)))
    (seeds : List (Fin count)) (noDup : seeds.Nodup) :
    DependencyInvalidation.Closed (RuleGraphClosure.ReadsInto plans)
      (fun key => key ∈ (runFuel (RuleGraphClosure.ruleSuccessors plans)
        (count + 1) (initial seeds)).selected) := by
  exact completed_compiled_closed plans seeds noDup _
    (runFuel_run (RuleGraphClosure.ruleSuccessors plans)
      (count + 1) (initial seeds))
    (runFuel_complete count (RuleGraphClosure.ruleSuccessors plans)
      (initial seeds) (initial_wellformed seeds noDup))

end Ascent.NativeGraphWorklist
