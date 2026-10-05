-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DependencyInvalidation

/-!
An abstract contract for the native invalidation graph. `ruleSuccessors`
mirrors `gerbil-ascent-rule-successors`: each reading clause contributes an
edge from its source relation to every head of its rule. The worklist model
uses extensional membership predicates, so its proof concerns membership
and completion, not native list order, vector bounds, termination or mutable
representation.
-/

namespace Ascent.RuleGraphClosure

universe u v

inductive ClauseKind where
  | atom | negation | aggregate | guard | generator | binding
  deriving DecidableEq

def ClauseKind.reads : ClauseKind → Bool
  | .atom | .negation | .aggregate => true
  | .guard | .generator | .binding => false

structure Clause (Key : Type u) where
  kind : ClauseKind
  source : Option Key

structure Rule (Key : Type u) where
  heads : List Key
  body : List (Clause Key)

variable {Key : Type u}

section Compiler

variable [DecidableEq Key]

def ruleSuccessors (plans : List (Rule Key)) (source : Key) : List Key :=
  plans.flatMap fun rule =>
    rule.body.flatMap fun clause =>
      if clause.kind.reads && decide (clause.source = some source) then rule.heads else []

def ReadsInto (plans : List (Rule Key)) (source target : Key) : Prop :=
  ∃ rule ∈ plans, ∃ clause ∈ rule.body,
    clause.kind.reads = true ∧ clause.source = some source ∧ target ∈ rule.heads

/-- The compiled adjacency is exactly the set of source-to-head read edges,
including negative and aggregate reads and all heads of a multi-head rule. -/
theorem mem_ruleSuccessors_iff (plans : List (Rule Key)) (source target : Key) :
    target ∈ ruleSuccessors plans source ↔ ReadsInto plans source target := by
  simp [ruleSuccessors, ReadsInto, List.mem_flatMap, and_assoc]

end Compiler

inductive Reachable (adj : Key → Key → Prop) (seeds : Key → Prop) : Key → Prop where
  | seed {key} : seeds key → Reachable adj seeds key
  | follow {source target} : Reachable adj seeds source →
      adj source target → Reachable adj seeds target

structure Work (Key : Type u) where
  selected : Key → Prop
  pending : Key → Prop

def initial (seeds : Key → Prop) : Work Key := ⟨seeds, seeds⟩

/-- One mark-before-enqueue transition, abstracting pending list order. -/
def visit (adj : Key → Key → Prop) (work : Work Key) (source : Key) : Work Key :=
  { selected := fun key => work.selected key ∨ adj source key
    pending := fun key =>
      (work.pending key ∧ key ≠ source) ∨
      (adj source key ∧ ¬ work.selected key) }

def Invariant (adj : Key → Key → Prop) (seeds : Key → Prop)
    (work : Work Key) : Prop :=
  (∀ key, work.selected key → Reachable adj seeds key) ∧
  (∀ key, seeds key → work.selected key) ∧
  (∀ key, work.pending key → work.selected key) ∧
  (∀ source, work.selected source → ¬ work.pending source →
    ∀ target, adj source target → work.selected target)

theorem initial_invariant (adj : Key → Key → Prop) (seeds : Key → Prop) :
    Invariant adj seeds (initial seeds) := by
  constructor
  · intro key selected
    exact Reachable.seed selected
  constructor
  · intro key selected
    exact selected
  constructor
  · intro key pending
    exact pending
  · intro source selected notPending
    exact False.elim (notPending selected)

theorem visit_invariant (adj : Key → Key → Prop) (seeds : Key → Prop)
    (work : Work Key) (source : Key)
    (inv : Invariant adj seeds work)
    (pending : work.pending source) :
    Invariant adj seeds (visit adj work source) := by
  rcases inv with ⟨selectedReachable, seedsSelected, pendingSelected, processedClosed⟩
  have sourceSelected := pendingSelected source pending
  constructor
  · intro key selected
    rcases selected with old | new
    · exact selectedReachable key old
    · exact Reachable.follow (selectedReachable source sourceSelected) new
  constructor
  · intro key seed
    exact Or.inl (seedsSelected key seed)
  constructor
  · intro key stillPending
    rcases stillPending with old | new
    · exact Or.inl (pendingSelected key old.1)
    · exact Or.inr new.1
  · intro node selected notPending target edge
    by_cases oldSelected : work.selected node
    · by_cases isSource : node = source
      · subst node
        exact Or.inr edge
      · have oldNotPending : ¬ work.pending node := by
          intro wasPending
          apply notPending
          exact Or.inl ⟨wasPending, isSource⟩
        exact Or.inl
          (processedClosed node oldSelected oldNotPending target edge)
    · have newNode : adj source node := by
        rcases selected with old | new
        · exact False.elim (oldSelected old)
        · exact new
      have newlyPending : (visit adj work source).pending node :=
        Or.inr ⟨newNode, oldSelected⟩
      exact False.elim (notPending newlyPending)

inductive Run (adj : Key → Key → Prop) : Work Key → Work Key → Prop where
  | refl (work) : Run adj work work
  | next {before after} (source : Key) : before.pending source →
      Run adj (visit adj before source) after → Run adj before after

theorem run_invariant (adj : Key → Key → Prop) (seeds : Key → Prop)
    {before after : Work Key} (run : Run adj before after)
    (inv : Invariant adj seeds before) : Invariant adj seeds after := by
  induction run with
  | refl => exact inv
  | next source pending _ ih =>
      exact ih (visit_invariant adj seeds _ source inv pending)

/-- Every completed worklist computes exactly the least reachability closure.
The theorem is independent of worklist order and number of visits. -/
theorem completed_exact (adj : Key → Key → Prop) (seeds : Key → Prop)
    (work : Work Key) (inv : Invariant adj seeds work)
    (done : ∀ key, ¬ work.pending key) (key : Key) :
    work.selected key ↔ Reachable adj seeds key := by
  rcases inv with ⟨selectedReachable, seedsSelected, _, processedClosed⟩
  constructor
  · exact selectedReachable key
  · intro reachable
    induction reachable with
    | seed inSeeds => exact seedsSelected _ inSeeds
    | follow reached edge ih =>
        apply processedClosed _ ih
        · exact done _
        · exact edge

theorem reachable_congr (adjA adjB : Key → Key → Prop)
    (seeds : Key → Prop)
    (same : ∀ source target, adjA source target ↔ adjB source target)
    (key : Key) :
    Reachable adjA seeds key ↔ Reachable adjB seeds key := by
  constructor
  · intro reached
    induction reached with
    | seed member => exact Reachable.seed member
    | follow _ edge ih => exact Reachable.follow ih ((same _ _).mp edge)
  · intro reached
    induction reached with
    | seed member => exact Reachable.seed member
    | follow _ edge ih => exact Reachable.follow ih ((same _ _).mpr edge)

def compiledAdj [DecidableEq Key] (plans : List (Rule Key))
    (source target : Key) : Prop :=
  target ∈ ruleSuccessors plans source

/-- A completed mark-before-enqueue run on the compiled graph selects exactly
the relations reachable from changed seeds through admitted rule reads. -/
theorem completed_compiled_exact [DecidableEq Key]
    (plans : List (Rule Key)) (seeds : Key → Prop)
    (work : Work Key)
    (run : Run (compiledAdj plans) (initial seeds) work)
    (done : ∀ key, ¬ work.pending key) (key : Key) :
    work.selected key ↔ Reachable (ReadsInto plans) seeds key := by
  have inv := run_invariant (compiledAdj plans) seeds run
    (initial_invariant (compiledAdj plans) seeds)
  exact (completed_exact (compiledAdj plans) seeds work inv done key).trans
    (reachable_congr (compiledAdj plans) (ReadsInto plans) seeds
      (fun source target => mem_ruleSuccessors_iff plans source target) key)

/-- A completed graph traversal supplies the closure premise of the
dependency-invalidation frame theorem. -/
theorem completed_compiled_closed [DecidableEq Key]
    (plans : List (Rule Key)) (seeds : Key → Prop)
    (work : Work Key)
    (run : Run (compiledAdj plans) (initial seeds) work)
    (done : ∀ key, ¬ work.pending key) :
    DependencyInvalidation.Closed (ReadsInto plans) work.selected := by
  intro source target read selected
  have sourceReach := (completed_compiled_exact plans seeds work run done source).mp selected
  exact (completed_compiled_exact plans seeds work run done target).mpr
    (Reachable.follow sourceReach read)

/-- With a local evaluator and completed fixed points, the graph compiler
and completed traversal jointly justify reuse outside the selected set. -/
theorem completed_reuse_frame [DecidableEq Key]
    {Value : Key → Type v}
    (plans : List (Rule Key)) (seeds : Key → Prop)
    (work : Work Key)
    (run : Run (compiledAdj plans) (initial seeds) work)
    (done : ∀ key, ¬ work.pending key)
    (step : DependencyInvalidation.State Key Value →
      DependencyInvalidation.State Key Value)
    (locality : DependencyInvalidation.Local (ReadsInto plans) step)
    {before after : DependencyInvalidation.State Key Value}
    (agree : DependencyInvalidation.AgreeOutside work.selected before after)
    (oldRounds newRounds : Nat)
    (oldStable : step (DependencyInvalidation.iterate step oldRounds before) =
      DependencyInvalidation.iterate step oldRounds before)
    (newStable : step (DependencyInvalidation.iterate step newRounds after) =
      DependencyInvalidation.iterate step newRounds after) :
    DependencyInvalidation.AgreeOutside work.selected
      (DependencyInvalidation.iterate step oldRounds before)
      (DependencyInvalidation.iterate step newRounds after) :=
  DependencyInvalidation.completed_frame (ReadsInto plans) work.selected
    step (completed_compiled_closed plans seeds work run done)
    locality agree oldRounds newRounds oldStable newStable

end Ascent.RuleGraphClosure
