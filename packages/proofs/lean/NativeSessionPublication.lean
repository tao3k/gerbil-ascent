/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Inductive safety proof for the synchronous transition fragment modeled by
NativeSessionPublication.tla. Cuts and generations are unbounded here. The
resultOf function is an assumption about a completed solve; correspondence
between these transitions and all Gerbil Session executions remains separate.
-/
import Std

namespace Ascent.NativePublication

inductive Phase where
  | clean | dirty | boundedWork
  deriving DecidableEq

inductive Outcome where
  | complete | provisional | bounded | rejected
  deriving DecidableEq

structure State (Cut Result : Type) where
  generation : Nat
  committed : Cut
  pending : Cut
  published : Result
  phase : Phase
  outcome : Outcome

def initial (resultOf : Cut → Result) (cut : Cut) : State Cut Result :=
  ⟨0, cut, cut, resultOf cut, .clean, .complete⟩

def Good (resultOf : Cut → Result) (s : State Cut Result) : Prop :=
  s.published = resultOf s.committed ∧
  (s.phase = .clean → s.pending = s.committed) ∧
  (s.phase = .boundedWork → s.outcome = .bounded)

def singleReplace (s : State Cut Result) (cut : Cut) : State Cut Result :=
  { s with pending := cut, phase := .dirty, outcome := .provisional }

def batchComplete (resultOf : Cut → Result) (s : State Cut Result)
    (cut : Cut) : State Cut Result :=
  { s with generation := s.generation + 1, committed := cut,
           pending := cut, published := resultOf cut,
           phase := .clean, outcome := .complete }

def batchReject (s : State Cut Result) : State Cut Result :=
  { s with outcome := .rejected }

def runComplete (resultOf : Cut → Result)
    (s : State Cut Result) : State Cut Result :=
  { s with generation := s.generation + 1, committed := s.pending,
           published := resultOf s.pending,
           phase := .clean, outcome := .complete }

def runBounded (s : State Cut Result) : State Cut Result :=
  { s with phase := .boundedWork, outcome := .bounded }

def runFailure (s : State Cut Result) : State Cut Result :=
  { s with pending := s.committed, phase := .clean, outcome := .rejected }

/-- The guards and public effects match the normal actions of the TLA model.
    `runComplete` here represents only a qualified completed solve. -/
inductive Step (resultOf : Cut → Result) :
    State Cut Result → State Cut Result → Prop where
  | single (s : State Cut Result) (cut : Cut)
      (allowed : s.phase ≠ .boundedWork) :
      Step resultOf s (singleReplace s cut)
  | batch (s : State Cut Result) (cut : Cut)
      (ready : s.phase = .clean) :
      Step resultOf s (batchComplete resultOf s cut)
  | reject (s : State Cut Result) (ready : s.phase = .clean) :
      Step resultOf s (batchReject s)
  | complete (s : State Cut Result)
      (ready : s.phase = .dirty ∨ s.phase = .boundedWork) :
      Step resultOf s (runComplete resultOf s)
  | bounded (s : State Cut Result)
      (ready : s.phase = .dirty ∨ s.phase = .boundedWork) :
      Step resultOf s (runBounded s)
  | failure (s : State Cut Result)
      (ready : s.phase = .dirty ∨ s.phase = .boundedWork) :
      Step resultOf s (runFailure s)

theorem initial_good (resultOf : Cut → Result) (cut : Cut) :
    Good resultOf (initial resultOf cut) := by
  simp [Good, initial]

theorem single_good (resultOf : Cut → Result) (s : State Cut Result)
    (cut : Cut) (good : Good resultOf s) :
    Good resultOf (singleReplace s cut) := by
  rcases good with ⟨published, _, _⟩
  simp [Good, singleReplace, published]

theorem batch_good (resultOf : Cut → Result) (s : State Cut Result)
    (cut : Cut) : Good resultOf (batchComplete resultOf s cut) := by
  simp [Good, batchComplete]

theorem reject_good (resultOf : Cut → Result) (s : State Cut Result)
    (ready : s.phase = .clean) (good : Good resultOf s) :
    Good resultOf (batchReject s) := by
  rcases good with ⟨published, aligned, _⟩
  simp [Good, batchReject, published, ready, aligned ready]

theorem complete_good (resultOf : Cut → Result) (s : State Cut Result) :
    Good resultOf (runComplete resultOf s) := by
  simp [Good, runComplete]

theorem bounded_good (resultOf : Cut → Result) (s : State Cut Result)
    (good : Good resultOf s) : Good resultOf (runBounded s) := by
  rcases good with ⟨published, _, _⟩
  simp [Good, runBounded, published]

theorem failure_good (resultOf : Cut → Result) (s : State Cut Result)
    (good : Good resultOf s) : Good resultOf (runFailure s) := by
  rcases good with ⟨published, _, _⟩
  simp [Good, runFailure, published]

theorem step_good (resultOf : Cut → Result) (s t : State Cut Result)
    (good : Good resultOf s) (step : Step resultOf s t) : Good resultOf t := by
  cases step with
  | single cut _ => exact single_good resultOf s cut good
  | batch cut _ => exact batch_good resultOf s cut
  | reject ready => exact reject_good resultOf s ready good
  | complete _ => exact complete_good resultOf s
  | bounded _ => exact bounded_good resultOf s good
  | failure _ => exact failure_good resultOf s good

inductive Reachable (resultOf : Cut → Result) (cut : Cut) :
    State Cut Result → Prop where
  | start : Reachable resultOf cut (initial resultOf cut)
  | next {s t : State Cut Result} :
      Reachable resultOf cut s → Step resultOf s t → Reachable resultOf cut t

/-- Safety holds after any finite execution, with no bound on generations,
    source cuts, or the number of replacement/timeout cycles. -/
theorem reachable_good (resultOf : Cut → Result) (cut : Cut)
    (s : State Cut Result) (reachable : Reachable resultOf cut s) :
    Good resultOf s := by
  induction reachable with
  | start => exact initial_good resultOf cut
  | next prior step ih => exact step_good resultOf _ _ ih step

def publicState (s : State Cut Result) : Nat × Cut × Result :=
  (s.generation, s.committed, s.published)

theorem provisional_keeps_public (s : State Cut Result) (cut : Cut) :
    publicState (singleReplace s cut) = publicState s := rfl

theorem bounded_keeps_public (s : State Cut Result) :
    publicState (runBounded s) = publicState s := rfl

theorem rejected_keeps_public (s : State Cut Result) :
    publicState (batchReject s) = publicState s := rfl

theorem failed_keeps_public (s : State Cut Result) :
    publicState (runFailure s) = publicState s := rfl

/-- Concrete negative controls: exposing a pending result early or publishing
    a bounded run violates the very first conjunct of `Good`. -/
structure SymbolicCut where
  direct : Bool
  via : Bool
  blocked : Bool
  deriving DecidableEq

def symbolicResult (cut : SymbolicCut) : Bool :=
  cut.direct || (cut.via && !cut.blocked)

def emptyCut : SymbolicCut := ⟨false, false, false⟩
def viaCut : SymbolicCut := ⟨false, true, false⟩

def earlyPublish (s : State SymbolicCut Bool) (cut : SymbolicCut) :
    State SymbolicCut Bool :=
  { singleReplace s cut with published := symbolicResult cut }

def partialPublish (s : State SymbolicCut Bool) :
    State SymbolicCut Bool :=
  { runBounded s with published := symbolicResult s.pending }

def sourceAlias (s : State SymbolicCut Bool) (cut : SymbolicCut) :
    State SymbolicCut Bool :=
  { s with committed := cut, pending := cut }

theorem early_publication_counterexample :
    ¬ Good symbolicResult (earlyPublish (initial symbolicResult emptyCut) viaCut) := by
  simp [Good, earlyPublish, singleReplace, initial, symbolicResult,
    emptyCut, viaCut]

theorem bounded_publication_counterexample :
    ¬ Good symbolicResult
      (partialPublish (singleReplace (initial symbolicResult emptyCut) viaCut)) := by
  simp [Good, partialPublish, runBounded, singleReplace, initial,
    symbolicResult, emptyCut, viaCut]

theorem mutable_source_counterexample :
    ¬ Good symbolicResult
      (sourceAlias (initial symbolicResult emptyCut) viaCut) := by
  simp [Good, sourceAlias, initial, symbolicResult, emptyCut, viaCut]

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

end Ascent.NativePublication
