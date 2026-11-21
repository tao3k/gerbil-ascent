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

/-- The private state message represents precisely the no-authority,
argument-free request. Its Completion is still fresh and private. -/
inductive Request (Endpoint Authority Argument : Type) where
  | state (reply : Endpoint) (authority : Option Authority) (args : List Argument)
  | other (reply : Endpoint) (authority : Option Authority) (args : List Argument)
  deriving DecidableEq

inductive Message (Endpoint Authority Argument : Type) where
  | compactState (reply : Endpoint)
  | envelope (request : Request Endpoint Authority Argument)

def encode : Request Endpoint Authority Argument → Message Endpoint Authority Argument
  | .state reply none [] => .compactState reply
  | request => .envelope request

def decode : Message Endpoint Authority Argument → Request Endpoint Authority Argument
  | .compactState reply => .state reply none []
  | .envelope request => request

theorem decode_encode (request : Request Endpoint Authority Argument) :
    decode (encode request) = request := by
  cases request with
  | other => rfl
  | state reply authority args => cases authority <;> cases args <;> rfl

/-- The same decoded identity goes either through dispatch or close draining.
No reply identity, supplied authority or arguments may be substituted. -/
theorem dispatch_or_drain_exact (request : Request Endpoint Authority Argument)
    (closed : Bool) (serve reject : Request Endpoint Authority Argument → Result) :
    (if closed then reject (decode (encode request)) else serve (decode (encode request))) =
      (if closed then reject request else serve request) := by rw [decode_encode]

def messageConstructors : Message Endpoint Authority Argument → Nat × Nat
  | .compactState _ => (0, 1)
  | .envelope _ => (Ascent.ActorEnvelope.fields.length, 0)

theorem compact_constructors (reply : Endpoint) :
    messageConstructors (encode (.state reply none [] : Request Endpoint Authority Argument)) =
      (0, 1) := rfl

theorem removing_clock_probes_preserves_protocol (requests : Nat) :
    { window requests true with clockBuffers := 0 } = window requests false := rfl

theorem timed_million_clock_buffers : (window 1000000 true).clockBuffers = 2000000 := by
  decide

/-- Reuse a caller-local clock buffer while keeping both clock reads
per observation and the exact request/reply constructor budget. -/
def callerClockWindow (requests callers : Nat) : Constructors :=
  { window requests true with clockBuffers := callers }

theorem caller_clock_preserves_request_cost (requests callers : Nat) :
    { callerClockWindow requests callers with clockBuffers := (window requests true).clockBuffers } =
      window requests true := rfl

structure StateWindow where
  retainedFacts : Nat
  calls : Constructors

def stateWindow (requests retainedFacts : Nat) (timed : Bool) : StateWindow :=
  ⟨retainedFacts, window requests timed⟩

theorem state_constructor_work_does_not_depend_on_relation_size
    (requests oldFacts newFacts : Nat) (timed : Bool) :
    (stateWindow requests oldFacts timed).calls =
      (stateWindow requests newFacts timed).calls := rfl

inductive OwnerPhase where
  | idle | running | draining
  deriving DecidableEq

/-- The fields relevant to the native owner's state reply and the root
comparison. The original declaration and published cut have separate roles. -/
structure ResidentObservation (Row : Type) where
  generation : Nat
  runningEpoch : Option Nat
  committedCut : List Row
  declarationRows : List Row

def ownerReply (state : ResidentObservation Row) : Nat × OwnerPhase :=
  (state.generation, match state.runningEpoch with
    | none => .idle
    | some epoch => if epoch = state.generation then .running else .draining)

/-- Changing declaration roots cannot change the reply computed by read-state.
Receiver ownership in evaluation requests remains a separate obligation. -/
theorem state_read_ignores_declaration_roots (state : ResidentObservation Row)
    (roots : List Row) : ownerReply { state with declarationRows := roots } = ownerReply state := rfl

theorem committed_root_control (declaration cut : List Row) (generation : Nat) :
    ownerReply (⟨generation, none, cut, declaration⟩ : ResidentObservation Row) =
      ownerReply (⟨generation, none, cut, []⟩ : ResidentObservation Row) := rfl

inductive TerminalReply where
  | completed | declined | failed
  deriving DecidableEq

inductive TerminalDisposition where
  | ignore | rollback | commit | ordinary
  deriving DecidableEq

/-- The owner checks the private worker and admitted run before handling its
reply. A worker decline may enter ordinary evaluation for that run only. -/
def terminalDisposition (admitted completed worker sender generation : Nat)
    (reply : TerminalReply) : TerminalDisposition :=
  if completed ≠ admitted ∨ sender ≠ worker then .ignore
  else if generation ≠ admitted then .rollback
  else match reply with
    | .completed => .commit
    | .declined => .ordinary
    | .failed => .rollback

theorem terminal_stale_generation_rolls_back (epoch worker generation : Nat)
    (stale : generation ≠ epoch) (reply : TerminalReply) :
    terminalDisposition epoch epoch worker worker generation reply = .rollback := by
  simp [terminalDisposition, stale]

theorem terminal_retired_worker_is_ignored (epoch worker sender generation : Nat)
    (retired : sender ≠ worker) (reply : TerminalReply) :
    terminalDisposition epoch epoch worker sender generation reply = .ignore := by
  simp [terminalDisposition, retired]

theorem terminal_decline_keeps_admission (epoch worker : Nat) :
    terminalDisposition epoch epoch worker worker epoch .declined = .ordinary := by
  simp [terminalDisposition]

/-- Model the previous word returned by Gambit's compare-and-swap on the
run's private cancellation cell. A reader supplies false for both operands. -/
def cancelCellCas (cell next expected : Bool) : Bool × Bool :=
  (cell, if cell = expected then next else cell)

theorem cancel_cell_reader_preserves (cell : Bool) :
    cancelCellCas cell false false = (cell, cell) := by
  cases cell <;> rfl

theorem cancel_cell_owner_marks (cell : Bool) :
    cancelCellCas cell true false = (cell, true) := by
  cases cell <;> rfl

theorem cancel_cell_read_after_mark (cell : Bool) :
    (cancelCellCas (cancelCellCas cell true false).2 false false).1 = true := by
  rw [cancel_cell_owner_marks, cancel_cell_reader_preserves]

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

inductive StateLease where
  | spare | borrowed | ready | consumed | abandoned
  deriving DecidableEq

def recycleConsumed : StateLease → StateLease
  | .consumed => .spare
  | lease => lease

theorem recycle_requires_consumed (lease : StateLease)
    (inUse : lease ≠ .spare) (recycled : recycleConsumed lease = .spare) :
    lease = .consumed := by
  cases lease <;> simp_all [recycleConsumed]

theorem abandoned_completion_stays_private :
    recycleConsumed .abandoned = .abandoned := rfl

structure CompletionRead (Reply : Type) where
  ready : Bool
  reply : Option Reply

/-- The old poster may still broadcast after unlocking the Completion.
The broadcast changes neither readiness nor the saved answer. -/
def observeCompletion (state : CompletionRead Reply) : Option Reply :=
  if state.ready then state.reply else none

def signalCompletion (state : CompletionRead Reply) : CompletionRead Reply := state

theorem late_signal_preserves_observation (state : CompletionRead Reply) :
    observeCompletion (signalCompletion state) = observeCompletion state := rfl

theorem reset_with_late_signal_has_no_reply :
    observeCompletion (signalCompletion (⟨false, none⟩ : CompletionRead Reply)) = none := rfl

/-- The witness is the identity of the fresh public result list. The
identity comparison and clearing happen within one release step. -/
def releaseMatchingReply (returned : Nat) (stored : Option Nat) : Option Nat :=
  if stored = some returned then none else stored

theorem returned_reply_releases (reply : Nat) :
    releaseMatchingReply reply (some reply) = none := by
  simp [releaseMatchingReply]

theorem old_reply_cannot_release_later (old later : Nat) (distinct : old ≠ later) :
    releaseMatchingReply old (some later) = some later := by
  simp [releaseMatchingReply, Ne.symm distinct]

theorem duplicate_release_keeps_empty (reply : Nat) :
    releaseMatchingReply reply (releaseMatchingReply reply (some reply)) = none := by
  simp [releaseMatchingReply]

def bindReplyHandler (prior : Option Nat) (endpoint : Nat) : Nat :=
  prior.getD endpoint

/-- A handler stays attached to the private message whose endpoint it
captured. Recycling changes the wait lifetime and result, not the endpoint. -/
theorem bound_handler_targets_original (handler : Option Nat) (endpoint : Nat)
    (owned : ∀ target ∈ handler, target = endpoint) :
    bindReplyHandler handler endpoint = endpoint := by
  cases handler with
  | none => rfl
  | some target => exact owned target (by simp)

def retainIdleEndpoint (capacity : Nat) (idle : List Nat) (endpoint : Nat) : List Nat :=
  if idle.length < capacity then endpoint :: idle else idle

theorem idle_retention_bounded (capacity : Nat) (idle : List Nat) (endpoint : Nat)
    (within : idle.length ≤ capacity) :
    (retainIdleEndpoint capacity idle endpoint).length ≤ capacity := by
  unfold retainIdleEndpoint
  split <;> simp_all <;> omega

theorem idle_retention_unique (capacity : Nat) (idle : List Nat) (endpoint : Nat)
    (outside : endpoint ∉ idle) (unique : idle.Nodup) :
    (retainIdleEndpoint capacity idle endpoint).Nodup := by
  unfold retainIdleEndpoint
  split <;> simp_all

/-- The top entry no longer aliases the pool after take. Fresh allocation
when the prefix is empty belongs to the ordinary caller path. -/
theorem taken_endpoint_is_private (endpoint : Nat) (rest : List Nat)
    (unique : (endpoint :: rest).Nodup) : endpoint ∉ rest :=
  (List.nodup_cons.mp unique).1

/-- Each lifetime owns three consecutive transitions. Recycling uses the
retired stamp as the next lifetime's base. Unbounded stamps never wrap. -/
theorem retired_stamp_refuses_old_entry (base later : Nat)
    (after : base + 3 ≤ later) : base ≠ later := by omega

theorem retired_stamp_refuses_old_cleanup (base later : Nat)
    (after : base + 3 ≤ later) : base + 1 ≠ later ∧ base + 2 ≠ later := by omega

/-- The reusable request advances its stamp on entry. Return eligibility
is checked separately against the identity of the successful reply. -/
def enterStateRequest (captured available : Nat) : Option Nat :=
  if captured = available then some (available + 1) else none

theorem current_entry_advances (current : Nat) :
    enterStateRequest current current = some (current + 1) := by
  simp [enterStateRequest]

theorem advanced_entry_refuses_captured (captured available : Nat)
    (advanced : captured < available) : enterStateRequest captured available = none := by
  simp [enterStateRequest, Nat.ne_of_lt advanced]

end Ascent.ActorStateCost

#print axioms Ascent.ActorStateCost.five_envelope_pairs
#print axioms Ascent.ActorStateCost.dispatch_or_drain_exact
#print axioms Ascent.ActorStateCost.compact_constructors
#print axioms Ascent.ActorStateCost.removing_clock_probes_preserves_protocol
#print axioms Ascent.ActorStateCost.state_read_ignores_declaration_roots
#print axioms Ascent.ActorStateCost.committed_root_control
#print axioms Ascent.ActorStateCost.terminal_stale_generation_rolls_back
#print axioms Ascent.ActorStateCost.terminal_retired_worker_is_ignored
#print axioms Ascent.ActorStateCost.terminal_decline_keeps_admission
#print axioms Ascent.ActorStateCost.fewer_roots_do_not_increase_scan_work
#print axioms Ascent.ActorStateCost.cpu_and_gc_cannot_be_added_as_wall_partition
#print axioms Ascent.ActorStateCost.recycle_requires_consumed
#print axioms Ascent.ActorStateCost.reset_with_late_signal_has_no_reply
#print axioms Ascent.ActorStateCost.old_reply_cannot_release_later
#print axioms Ascent.ActorStateCost.duplicate_release_keeps_empty
#print axioms Ascent.ActorStateCost.bound_handler_targets_original
#print axioms Ascent.ActorStateCost.idle_retention_bounded
#print axioms Ascent.ActorStateCost.idle_retention_unique
#print axioms Ascent.ActorStateCost.taken_endpoint_is_private
#print axioms Ascent.ActorStateCost.retired_stamp_refuses_old_entry
#print axioms Ascent.ActorStateCost.retired_stamp_refuses_old_cleanup
#print axioms Ascent.ActorStateCost.advanced_entry_refuses_captured
