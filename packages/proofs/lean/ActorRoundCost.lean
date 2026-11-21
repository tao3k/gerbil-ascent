-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Source work for the successful full-batch path of
`program/actor-round.ss`. Poll-only requests and task termination are
additional events. This model counts messages, not cycles or allocations. -/
namespace Ascent.ActorRoundCost

structure Window where
  flushed : Nat
  pending : Nat

def emit (window : Window) : Window :=
  if window.pending + 1 = 32 then ⟨window.flushed + 1, 0⟩
  else ⟨window.flushed, window.pending + 1⟩

def after : Nat → Window
  | 0 => ⟨0, 0⟩
  | count + 1 => emit (after count)

theorem conserved (count : Nat) :
    32 * (after count).flushed + (after count).pending = count ∧
      (after count).pending < 32 := by
  induction count with
  | zero => decide
  | succ count ih =>
      simp only [after, emit]
      split <;> simp_all <;> omega

theorem full_batches (count : Nat) : (after count).flushed = count / 32 := by
  have accounting := conserved count
  omega

def fullBatchMessages (count : Nat) : Nat := 2 * (after count).flushed

theorem million_full_batch_messages : fullBatchMessages 1000000 = 62500 := by
  rw [fullBatchMessages, full_batches]

theorem recursive_full_batch_messages : fullBatchMessages 1040384 = 65024 := by
  rw [fullBatchMessages, full_batches]

inductive CreditOutcome where
  | admitted | canceled | exhausted
  deriving DecidableEq

structure CreditState (Row : Type) where
  staged : List Row
  remaining : Nat
  deriving DecidableEq

/-- One credit observes cancellation before any row. Each subsequent merge
charges one row, where a failed charge preserves the prior private prefix. -/
def mergeOrdered (state : CreditState Row) : List Row → CreditOutcome × CreditState Row
  | [] => (.admitted, state)
  | row :: tail =>
    match state.remaining with
    | 0 => (.exhausted, state)
    | n + 1 => mergeOrdered ⟨state.staged ++ [row], n⟩ tail

def acceptCredit (state : CreditState Row) (canceled : Bool) (offered : List Row) :
    CreditOutcome × CreditState Row :=
  if canceled then (.canceled, state) else mergeOrdered state offered

def mergePrefix (state : CreditState Row) (offered : List Row) :
    CreditOutcome × CreditState Row :=
  (if offered.length ≤ state.remaining then .admitted else .exhausted,
   ⟨state.staged ++ offered.take state.remaining, state.remaining - offered.length⟩)

/-- The ordered fact checks can count a buffer once after its existing
cancellation decision. Refusal stages exactly the same private prefix. -/
theorem merge_prefix_exact (state : CreditState Row) (offered : List Row) :
    mergePrefix state offered = mergeOrdered state offered := by
  induction offered generalizing state with
  | nil => cases state <;> simp [mergePrefix, mergeOrdered]
  | cons row tail ih =>
    obtain ⟨staged, remaining⟩ := state
    cases remaining with
    | zero => simp [mergePrefix, mergeOrdered]
    | succ remaining =>
      simp [mergePrefix, mergeOrdered, ← ih, List.append_assoc]

/-- Native pending writes precede the limit test. A rejected row enters
the private pending lane before the coordinator stops the worker. -/
def stageBeforeLimit (remaining : Nat) (staged : List Row) : List Row → List Row
  | [] => staged
  | row :: tail =>
    match remaining with
    | 0 => staged ++ [row]
    | n + 1 => stageBeforeLimit n (staged ++ [row]) tail

theorem attempted_prefix_exact (remaining : Nat) (staged offered : List Row) :
    stageBeforeLimit remaining staged offered = staged ++ offered.take (remaining + 1) := by
  induction offered generalizing remaining staged with
  | nil => simp [stageBeforeLimit]
  | cons row tail ih =>
    cases remaining with
    | zero => simp [stageBeforeLimit]
    | succ n => simp [stageBeforeLimit, ih, List.append_assoc]

theorem same_credit_after_handoff (state : CreditState Row) (canceled : Bool)
    (offered : List Row) :
    acceptCredit state canceled (offered.reverse.reverseAux []) =
      acceptCredit state canceled offered := by
  simp

theorem cancellation_precedes_every_merge (state : CreditState Row) (offered : List Row) :
    acceptCredit state true offered = (.canceled, state) := rfl

theorem exhaustion_preserves_prior_prefix (staged : List Row) (row : Row) (tail : List Row) :
    mergeOrdered ⟨staged, 0⟩ (row :: tail) = (.exhausted, ⟨staged, 0⟩) := rfl

def publishCredit (old candidate : Cut) (ownerAccepted : Bool) (result : CreditOutcome) : Cut :=
  if ownerAccepted && result == .admitted then candidate else old

theorem rejected_credit_cannot_publish (old candidate : Cut)
    (decision : Bool) (result : CreditOutcome) (failed : result ≠ .admitted) :
    publishCredit old candidate decision result = old := by
  cases result <;> simp_all [publishCredit]

/-- The ordinary Set commit in `program/evaluate.ss` walks the pending
newest-first lane and prepends each row to the previous total lane. -/
def commitRows (pending old : List Row) : List Row :=
  pending.foldl (fun total row => row :: total) old

theorem commit_rows_in_order (pending old : List Row) :
    commitRows pending old = pending.reverseAux old := by
  induction pending generalizing old with
  | nil => rfl
  | cons row tail ih => exact ih (row :: old)

/-- A terminal component can build the total from the accepted emission
order. Historical input occurrences remain intact, including duplicates. -/
theorem commit_accepted_lane (accepted old : List Row) :
    commitRows accepted.reverse old = accepted ++ old := by
  rw [commit_rows_in_order]
  simp

theorem commit_accepted_lane_count (accepted old : List Row) :
    (commitRows accepted.reverse old).length = accepted.length + old.length := by
  rw [commit_accepted_lane, List.length_append]

/-- `admit-stored!` finishes its existing charge before a new lane can be
selected. The Session owner still accepts or refuses the candidate cut. -/
def publishTerminalRows (old : List Row) (charged : CreditOutcome × CreditState Row)
    (ownerAccepted : Bool) : List Row :=
  publishCredit old (commitRows charged.2.staged.reverse old) ownerAccepted charged.1

theorem terminal_rows_exact (old : List Row) (charged : CreditOutcome × CreditState Row)
    (decision : Bool) :
    publishTerminalRows old charged decision =
      (if decision && charged.1 == .admitted then charged.2.staged ++ old else old) := by
  simp only [publishTerminalRows, publishCredit, commit_accepted_lane]

theorem terminal_refusal_keeps_old (old : List Row) (charged : CreditOutcome × CreditState Row)
    (decision : Bool) (failed : charged.1 ≠ .admitted) :
    publishTerminalRows old charged decision = old := by
  exact rejected_credit_cannot_publish old _ decision charged.1 failed

/-- Decoding only the written extent of split batch lanes recovers the
same ordered pairs. Suffix slots can contain rows from a previous credit. -/
theorem decode_written_batch {Atom Row : Type} (batch : List (Atom × Row))
    (unusedAtoms : List Atom) (unusedRows : List Row) :
    ((batch.map Prod.fst ++ unusedAtoms).take batch.length).zip
      ((batch.map Prod.snd ++ unusedRows).take batch.length) = batch := by
  induction batch with
  | nil => rfl
  | cons entry rest ih =>
      simp at ih
      cases entry
      simp [ih]

theorem batch_credit_preserved {Atom Row : Type} (state : CreditState (Atom × Row))
    (canceled : Bool) (batch : List (Atom × Row))
    (unusedAtoms : List Atom) (unusedRows : List Row) :
    acceptCredit state canceled (((batch.map Prod.fst ++ unusedAtoms).take batch.length).zip
      ((batch.map Prod.snd ++ unusedRows).take batch.length)) = acceptCredit state canceled batch := by
  rw [decode_written_batch]

inductive FactAdmission where
  | admitted | derivedLimit | outputLimit
  deriving DecidableEq

def checkFactLimits (source derived pending derivedLimit outputLimit : Int) : FactAdmission :=
  if derived + pending > derivedLimit then .derivedLimit
  else if source + derived + pending > outputLimit then .outputLimit
  else .admitted

/-- A component merge changes only `pending`. The initial source and
derived counts and both declarations stay fixed until publication. -/
def factLimitBoundary (source derived derivedLimit outputLimit : Int) : Int × FactAdmission :=
  let derivedRoom := derivedLimit - derived
  let outputRoom := outputLimit - (source + derived)
  if derivedRoom ≤ outputRoom then (derivedRoom, .derivedLimit)
  else (outputRoom, .outputLimit)

def checkFactBoundary (boundary : Int × FactAdmission) (pending : Int) : FactAdmission :=
  if pending > boundary.1 then boundary.2 else .admitted

/-- Admission stops at the first refusal. The previous prefix passed both
limits, including the empty prefix after source and reuse admission. -/
theorem fact_boundary_exact (source derived pending derivedLimit outputLimit : Int)
    (previousOutput : source + derived + (pending - 1) ≤ outputLimit) :
    checkFactBoundary (factLimitBoundary source derived derivedLimit outputLimit) pending =
      checkFactLimits source derived pending derivedLimit outputLimit := by
  by_cases first : derivedLimit - derived ≤ outputLimit - (source + derived)
  · by_cases over : derived + pending > derivedLimit
    · have rejected : pending > derivedLimit - derived := by omega
      simp [checkFactBoundary, factLimitBoundary, checkFactLimits, first, over, rejected]
    · have admitted : ¬ pending > derivedLimit - derived := by omega
      have output : ¬ source + derived + pending > outputLimit := by omega
      simp [checkFactBoundary, factLimitBoundary, checkFactLimits, first, over, admitted, output]
  · by_cases over : source + derived + pending > outputLimit
    · have derivedSafe : ¬ derived + pending > derivedLimit := by omega
      have rejected : pending > outputLimit - (source + derived) := by omega
      simp [checkFactBoundary, factLimitBoundary, checkFactLimits, first, over, derivedSafe, rejected]
    · have admitted : ¬ pending > outputLimit - (source + derived) := by omega
      have derivedSafe : ¬ derived + pending > derivedLimit := by omega
      simp [checkFactBoundary, factLimitBoundary, checkFactLimits, first, over, admitted, derivedSafe]

end Ascent.ActorRoundCost

#print axioms Ascent.ActorRoundCost.full_batches
#print axioms Ascent.ActorRoundCost.million_full_batch_messages
#print axioms Ascent.ActorRoundCost.same_credit_after_handoff
#print axioms Ascent.ActorRoundCost.merge_prefix_exact
#print axioms Ascent.ActorRoundCost.attempted_prefix_exact
#print axioms Ascent.ActorRoundCost.rejected_credit_cannot_publish
#print axioms Ascent.ActorRoundCost.commit_accepted_lane
#print axioms Ascent.ActorRoundCost.terminal_rows_exact
#print axioms Ascent.ActorRoundCost.fact_boundary_exact
