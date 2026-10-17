-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
/-! Trajectory observation semantics. Tokens are supplied by a trusted provider
adapter and correctness by an independent grader. These theorems neither prove
the grader nor reconstruct hidden model reasoning. -/
namespace Ascent.Trajectory
structure Ledger where
  generation : Nat := 0
  cost : Nat := 0
  first : Option Nat := none
  usageKnown : Bool := true
  referenceGeneration : Option Nat := none
  consumptionGeneration : Option Nat := none
  deriving DecidableEq, Repr

def call (s : Ledger) (tokens : Nat) : Ledger := { s with cost := s.cost + tokens }
def unknownCall (s : Ledger) : Ledger := { s with usageKnown := false }
def verify (s : Ledger) : Ledger :=
  { s with first := match s.first with | none => some s.cost | some n => some n }
def evidence (s : Ledger) : Ledger := { s with referenceGeneration := some s.generation }
def invalidate (s : Ledger) : Ledger := { generation := s.generation + 1 }
def reusable (s : Ledger) : Prop := s.referenceGeneration = some s.generation
def verifySubgoal (s : Ledger) : Ledger := s

-- accepted is the trusted closed-query kernel verdict, not model self-report.
def consume (s : Ledger) (accepted : Bool) : Ledger :=
  if accepted ∧ s.referenceGeneration = some s.generation then
    { s with consumptionGeneration := some s.generation }
  else s
def verifyConsumed (s : Ledger) : Ledger :=
  if s.consumptionGeneration = some s.generation then verify s else s

theorem rejected_intent_is_atomic (s : Ledger) : consume s false = s := by simp [consume]
theorem consumption_does_not_charge_tokens (s : Ledger) (accepted : Bool) :
    (consume s accepted).cost = s.cost := by simp [consume]; split <;> rfl
theorem unconsumed_path_cannot_freeze (s : Ledger)
    (h : s.consumptionGeneration ≠ some s.generation) :
    verifyConsumed s = s := by simp [verifyConsumed, h]
theorem invalidation_revokes_consumption (s : Ledger) :
    (invalidate s).consumptionGeneration = none := rfl
theorem admitted_consumption_keeps_entire_prefix (s : Ledger)
    (h : s.referenceGeneration = some s.generation) (first : s.first = none) :
    (verifyConsumed (consume s true)).first = some s.cost := by
  simp [consume, verifyConsumed, verify, h, first]

theorem subgoal_does_not_freeze_task (s : Ledger) :
    (verifySubgoal s).first = s.first := rfl

theorem missing_usage_is_unknown (s : Ledger) : (unknownCall s).usageKnown = false := rfl

theorem first_freezes (s : Ledger) (n tokens : Nat) (h : s.first = some n) :
    (call s tokens).first = some n := h

theorem failures_and_repairs_charged (s : Ledger) (failed repair : Nat) :
    (call (call s failed) repair).cost = s.cost + failed + repair := rfl

theorem first_captures_all_preceding_calls (s : Ledger) (h : s.first = none)
    (failed repair : Nat) :
    (verify (call (call s failed) repair)).first = some (s.cost + failed + repair) := by
  simp [verify, call, h]

theorem later_verdict_keeps_first (s : Ledger) (n : Nat) (h : s.first = some n) :
    (verify s).first = some n := by simp [verify, h]

theorem invalidation_revokes_reference (s : Ledger) : ¬ reusable (invalidate s) := by
  simp [reusable, invalidate]

theorem invalidation_starts_new_cost_epoch (s : Ledger) :
    (invalidate s).cost = 0 ∧ (invalidate s).first = none := by simp [invalidate]

theorem current_evidence_is_reusable (s : Ledger) : reusable (evidence s) := rfl

/- The observation API carries no preferred next operation. A known comparison
   and an idea absent from the packet are both choices made by the agent. -/
inductive Observation where
  | comparable | changedPremise | unknownPremise | historical | checkedResult
  deriving DecidableEq, Repr

inductive AgentChoice where
  | revisit (attempt : Nat)
  | novel (identity : String)
  deriving DecidableEq, Repr

structure ReasoningState where
  observations : List Observation := []
  agentChoice : Option AgentChoice := none
  deriving DecidableEq, Repr

def observe (s : ReasoningState) (fact : Observation) : ReasoningState :=
  { s with observations := fact :: s.observations }

def choose (s : ReasoningState) (choice : AgentChoice) : ReasoningState :=
  { s with agentChoice := some choice }

theorem observation_does_not_choose (s : ReasoningState) (fact : Observation) :
    (observe s fact).agentChoice = s.agentChoice := rfl

theorem any_choice_remains_available (s : ReasoningState)
    (fact : Observation) (choice : AgentChoice) :
    (choose (observe s fact) choice).agentChoice = some choice := rfl

theorem observation_cannot_override_choice (s : ReasoningState)
    (fact : Observation) (choice : AgentChoice) :
    (observe (choose s choice) fact).agentChoice = some choice := rfl

structure PrefixBinding where
  eventCount : Nat
  contentIdentity : String
  snapshotIdentity : String
  deriving DecidableEq, Repr

def prefixCurrent (packet : PrefixBinding) (count : Nat)
    (contentIdentity snapshotIdentity : String) : Bool :=
  packet.eventCount == count && packet.contentIdentity == contentIdentity &&
    packet.snapshotIdentity == snapshotIdentity

theorem current_prefix_requires_content_identity (packet : PrefixBinding)
    (count : Nat) (contentIdentity snapshotIdentity : String)
    (h : prefixCurrent packet count contentIdentity snapshotIdentity = true) :
    packet.contentIdentity = contentIdentity := by
  simp [prefixCurrent] at h
  exact h.1.2

theorem current_prefix_requires_snapshot_identity (packet : PrefixBinding)
    (count : Nat) (contentIdentity snapshotIdentity : String)
    (h : prefixCurrent packet count contentIdentity snapshotIdentity = true) :
    packet.snapshotIdentity = snapshotIdentity := by
  simp [prefixCurrent] at h
  exact h.2

example : prefixCurrent ⟨1, "old-content", "snapshot"⟩ 1 "new-content" "snapshot" = false := by decide
example : prefixCurrent ⟨1, "content", "old-snapshot"⟩ 1 "content" "new-snapshot" = false := by decide

/- A revised comparison rule has its own evidence lifecycle. An independent
   reviewer supplies `supported`; this type does not grade the rule itself. -/
structure Counterexample where
  id : Nat
  digest : String
  deriving DecidableEq, Repr

structure RuleRevision where
  source : Nat := 0
  counterexamples : List Counterexample := []
  draftSource : Option Nat := none
  ruleRevision : Nat := 0
  reviewedRevision : Option Nat := none
  reviewedExamples : Option (List Counterexample) := none
  supported : Bool := false
  published : Bool := false
  deriving DecidableEq, Repr

def recordCounterexample (s : RuleRevision) (item : Counterexample) : RuleRevision :=
  { s with counterexamples := s.counterexamples ++ [item], published := false }

def draftRule (s : RuleRevision) : RuleRevision :=
  { s with draftSource := some s.source, ruleRevision := s.ruleRevision + 1, reviewedRevision := none, reviewedExamples := none, supported := false, published := false }

def reviewRule (s : RuleRevision) (supported : Bool) : RuleRevision :=
  { s with reviewedRevision := some s.ruleRevision, reviewedExamples := some s.counterexamples, supported := supported, published := false }

def publishRule (s : RuleRevision) : RuleRevision :=
  if s.draftSource == some s.source ∧
     s.reviewedRevision == some s.ruleRevision ∧
     s.reviewedExamples == some s.counterexamples ∧ s.supported then
    { s with published := true }
  else { s with published := false }

def invalidateRule (s : RuleRevision) : RuleRevision :=
  { s with source := s.source + 1, published := false }

theorem counterexample_is_retained (s : RuleRevision) (item : Counterexample) :
    (recordCounterexample s item).counterexamples = s.counterexamples ++ [item] := rfl

theorem counterexample_revokes_publication (s : RuleRevision) (item : Counterexample) :
    (recordCounterexample s item).published = false := rfl

theorem invalidation_revokes_rule (s : RuleRevision) :
    (invalidateRule s).published = false := rfl

theorem publication_requires_current_review (s : RuleRevision)
    (h : (publishRule s).published = true) :
    s.draftSource = some s.source ∧
    s.reviewedRevision = some s.ruleRevision ∧
    s.reviewedExamples = some s.counterexamples ∧ s.supported = true := by
  unfold publishRule at h
  split at h <;> simp_all

example : (publishRule ({ source := 1, draftSource := some 1, ruleRevision := 1, reviewedRevision := some 1, counterexamples := [{ id := 7, digest := "new" }], reviewedExamples := some [{ id := 7, digest := "old" }], supported := true } : RuleRevision)).published = false := by decide

example : (verify (call (call {} 80) 30)).first = some 110 := by decide
example : (call (verify (call (call {} 80) 30)) 50).first = some 110 := by decide
end Ascent.Trajectory
