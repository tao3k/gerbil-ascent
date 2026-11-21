-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Actual Actor wire fields, not an abstract completion counter. The codec
preserves arbitrary values and reference identities; it never serializes a
payload or rebuilds a candidate spine. Shape mismatch is distinct from a
successfully decoded stopped/failed task. -/
namespace Ascent.ActorEnvelope
inductive Field where
  | kind | key | worker | task | payload
  deriving Repr, DecidableEq

def fields : List Field := [.kind, .key, .worker, .task, .payload]

structure Envelope (Value : Type) where
  kind : Value
  key : Value
  worker : Value
  task : Value
  payload : Value
  deriving DecidableEq

def get (message : Envelope Value) : Field → Value
  | .kind => message.kind
  | .key => message.key
  | .worker => message.worker
  | .task => message.task
  | .payload => message.payload

def encode (message : Envelope Value) : List Value := fields.map (get message)

def decode : List Value → Option (Envelope Value)
  | [kind, key, worker, task, payload] => some ⟨kind, key, worker, task, payload⟩
  | _ => none

theorem decode_encode (message : Envelope Value) : decode (encode message) = some message := by
  cases message; rfl

theorem decode_exact (wire : List Value) (message : Envelope Value) :
    decode wire = some message ↔ wire = encode message := by
  constructor
  · intro success
    cases wire with
    | nil => simp [decode] at success
    | cons a rest =>
      cases rest with
      | nil => simp [decode] at success
      | cons b rest =>
        cases rest with
        | nil => simp [decode] at success
        | cons c rest =>
          cases rest with
          | nil => simp [decode] at success
          | cons d rest =>
            cases rest with
            | nil => simp [decode] at success
            | cons e rest =>
              cases rest with
              | cons => simp [decode] at success
              | nil => cases success; rfl
  · intro same; rw [same, decode_encode]

theorem malformed_rejected (wire : List Value) (wrong : wire.length ≠ fields.length) :
    decode wire = none := by
  cases decoded : decode wire with
  | none => rfl
  | some message =>
      have encoded := (decode_exact wire message).mp decoded
      have := congrArg List.length encoded
      simp only [encode, List.length_map] at this
      exact False.elim (wrong this)

theorem payload_identity (message : Envelope Value) :
    (decode (encode message)).map Envelope.payload = some message.payload := by
  rw [decode_encode]; rfl

/-! The same exact codec serves a Session request. Its positions are request
tag, private reply endpoint, caller authority, operation and arguments. Values may
be Scheme references/procedures; the codec does not evaluate or reconstruct them. -/
theorem session_authority_identity (tag reply authority operation arguments : Value) :
    (decode (encode ⟨tag, reply, authority, operation, arguments⟩)).map Envelope.worker =
      some authority := by
  rw [decode_encode]
  rfl

def sessionPublication (kernelSucceeded epochCurrent requestAllowed finalAllowed : Bool) : Bool :=
  kernelSucceeded && epochCurrent && requestAllowed && finalAllowed

theorem refused_request_cannot_publish (success current final : Bool) :
    sessionPublication success current false final = false := by
  simp [sessionPublication]

theorem refused_final_cannot_publish (success current request : Bool) :
    sessionPublication success current request false = false := by
  simp [sessionPublication]

/-! A completed private engine can serve an unchanged cut only while the
declarations and nested values remain eligible. Public Result objects and row
spines are never the retained capability. Failure retires that capability.
These obligations are conditional on the native eligibility/ownership checks;
they do not certify those Scheme predicates or the heap implementation. -/
structure SessionReuse where
  sameCut : Bool
  canonical : Bool
  scalar : Bool
  stableRules : Bool
  completed : Bool

def reusable (r : SessionReuse) : Bool :=
  r.sameCut && r.canonical && r.scalar && r.stableRules && r.completed

theorem reuse_requires_same_cut (r : SessionReuse) (ok : reusable r = true) :
    r.sameCut = true := by
  cases h : r.sameCut <;> simp_all [reusable]

theorem changed_or_mutable_rejected (r : SessionReuse)
    (ineligible : r.sameCut = false ∨ r.scalar = false) : reusable r = false := by
  rcases ineligible with changed | mutable
  · simp [reusable, changed]
  · simp [reusable, mutable]

theorem same_cut_same_closure (derive : Cut → Result) (old current : Cut)
    (same : current = old) : derive current = derive old := by rw [same]

def retainedAfter (eligible accepted : Bool) : Bool := eligible && accepted

theorem refused_run_retires_reuse (eligible : Bool) : retainedAfter eligible false = false := by
  simp [retainedAfter]

/-! Source cost partition, not a wall-clock prediction: eligibility still
checks canonical declarations and scalar rows; publication still allocates
fresh outward row spines. Only seeding, index construction and rule traversal
are removed from a completed unchanged run. -/
structure ReuseWork where
  eligibility : Nat
  seed : Nat
  index : Nat
  traversal : Nat
  publication : Nat

def freshWork (w : ReuseWork) : Nat :=
  w.eligibility + w.seed + w.index + w.traversal + w.publication

def reusedWork (w : ReuseWork) : Nat := w.eligibility + w.publication

theorem retained_work_partition (w : ReuseWork) :
    freshWork w = reusedWork w + w.seed + w.index + w.traversal := by
  simp only [freshWork, reusedWork]
  omega

theorem retained_work_bounded (w : ReuseWork) : reusedWork w ≤ freshWork w := by
  rw [retained_work_partition]
  omega

/-! The worker conses each candidate onto a fresh outer pair. The payload
contains these cells in production order after the in-place reverse. The
naturals here name outer pair identities. The worker drops its reference before
sending the envelope, and candidates themselves are unchanged. -/
def takeBatch (pending : List (Nat × Value)) : List (Nat × Value) :=
  pending.reverseAux []

theorem takeBatch_preserves_order_and_cells (emitted : List (Nat × Value)) :
    takeBatch emitted.reverse = emitted := by
  simp [takeBatch]

-- New outer pairs allocated for a completed batch, including the already
-- allocated pending spine. Candidate payload pairs are common to both paths.
def copiedBatchPairs (rows : Nat) : Nat := rows + rows
def transferredBatchPairs (rows : Nat) : Nat := rows

theorem transfer_saves_one_pair_per_row (emitted : List (Nat × Value)) :
    copiedBatchPairs emitted.length - transferredBatchPairs emitted.length =
      emitted.length := by
  simp [copiedBatchPairs, transferredBatchPairs]

namespace FrozenIndex

/-! `program/positive-components.ss` only lends keyed total reads of
source-only slots. Its merge callback writes rule-owned relation slots.
Assignment-local indexes continue to handle other totals and both frontier
lanes in `program/component-worker.ss`. -/
structure Entry (Row : Type) where
  version : Nat
  bucket : List Row

def read {Row : Type} (matchesRow : Row → Bool) (frozen : List Row) (version : Nat)
    (cached : Entry Row) : List Row :=
  if cached.version = version then cached.bucket else frozen.filter matchesRow

theorem frozen_read_exact {Row : Type} (matchesRow : Row → Bool)
    (frozen : List Row) (version : Nat) (entry : Entry Row)
    (valid : entry.version = version → entry.bucket = frozen.filter matchesRow) :
    read matchesRow frozen version entry = frozen.filter matchesRow := by
  by_cases same : entry.version = version
  · simp [read, same, valid same]
  · simp [read, same]

def merge {Row : Type} (roots : Nat → List Row) (output : Nat × Row) (slot : Nat) : List Row :=
  if slot = output.1 then output.2 :: roots slot else roots slot

theorem source_root_stable {Row : Type} (roots : Nat → List Row) (sourceSlot : Nat)
    (outputs : List (Nat × Row)) (notWritten : ∀ output ∈ outputs, sourceSlot ≠ output.1) :
    (outputs.foldl merge roots) sourceSlot = roots sourceSlot := by
  induction outputs generalizing roots with
  | nil => rfl
  | cons output rest ih =>
      change (rest.foldl merge (merge roots output)) sourceSlot = roots sourceSlot
      rw [ih (merge roots output) (fun other member => notWritten other (by simp [member]))]
      simp [merge, notWritten output (by simp)]

theorem shared_source_matches_assignment {Row : Type} (roots : Nat → List Row)
    (sourceSlot : Nat) (outputs : List (Nat × Row))
    (notWritten : ∀ output ∈ outputs, sourceSlot ≠ output.1) (matchesRow : Row → Bool) :
    read matchesRow (roots sourceSlot) 0 ⟨0, (roots sourceSlot).filter matchesRow⟩ =
      ((outputs.foldl merge roots) sourceSlot).filter matchesRow := by
  rw [source_root_stable roots sourceSlot outputs notWritten]
  simp [read]

/-- For nonempty consumers of the same bucket family and cut, count only
the input occurrences offered to physical builds. Probes and checkpoints
still belong to each task. -/
theorem same_cut_builds_saved (rows otherConsumers : Nat) :
    (otherConsumers + 1) * rows - rows = otherConsumers * rows := by
  simp [Nat.add_mul]

end FrozenIndex

namespace ScalarComponentMerge

/-! One assigned component owns all producers for its output slots. Its private
membership starts with the output-slot snapshot and adds each candidate before
sending it. The coordinator receives that worker's batches in order. The frozen
index theorem above supplies snapshot stability against disjoint output slots.

The theorem here starts at the worker's novelty obligation. It does not prove
the mutable Scheme membership table, delivery order or the transport guard. -/
def novelFrom {Row : Type} (seen : List Row) : List Row → Prop
  | [] => True
  | row :: rest => row ∉ seen ∧ novelFrom (row :: seen) rest

def checkedInsert {Row : Type} [DecidableEq Row] (seen : List Row) (row : Row) : List Row :=
  if row ∈ seen then seen else row :: seen

/-- A private scalar table records the old membership bit while writing the
candidate. An update may replace the representative of an equal key. Only
the prior bit controls which row is emitted. -/
def scalarTableUpdate {Row : Type} [DecidableEq Row] (seen : List Row) (row : Row) :
    Bool × List Row :=
  (decide (row ∈ seen), row :: seen.filter (· ≠ row))

theorem scalar_update_preserves_membership {Row : Type} [DecidableEq Row]
    (seen : List Row) (row query : Row) :
    query ∈ (scalarTableUpdate seen row).2 ↔ query ∈ checkedInsert seen row := by
  have present : query ∈ (scalarTableUpdate seen row).2 ↔ query = row ∨ query ∈ seen := by
    by_cases same : query = row <;> simp [scalarTableUpdate, same]
  rw [present]
  by_cases member : row ∈ seen
  · simp [checkedInsert, member]
    exact fun equal => equal.symm ▸ member
  · simp [checkedInsert, member]

def scalarNovelty {Row : Type} [DecidableEq Row]
    (update : List Row → Row → Bool × List Row) (seen : List Row) : List Row → List Row
  | [] => []
  | row :: rest =>
    let (present, next) := update seen row
    if present then scalarNovelty update next rest else row :: scalarNovelty update next rest

theorem scalar_update_emits_the_same_rows {Row : Type} [DecidableEq Row]
    (rows updateSeen splitSeen : List Row)
    (same : ∀ row, row ∈ updateSeen ↔ row ∈ splitSeen) :
    scalarNovelty scalarTableUpdate updateSeen rows =
      scalarNovelty (fun seen row => (decide (row ∈ seen), checkedInsert seen row)) splitSeen rows := by
  induction rows generalizing updateSeen splitSeen with
  | nil => rfl
  | cons row rest ih =>
    have next : ∀ query, query ∈ (scalarTableUpdate updateSeen row).2 ↔
        query ∈ checkedInsert splitSeen row := by
      intro query
      rw [scalar_update_preserves_membership]
      by_cases present : row ∈ splitSeen
      · simp [checkedInsert, present, (same row).2 present, same query]
      · have absent : row ∉ updateSeen := fun old => present ((same row).1 old)
        simp [checkedInsert, present, absent, same query]
    have steps := ih _ _ next
    by_cases present : row ∈ splitSeen
    · have retained := (same row).2 present
      simpa [scalarNovelty, scalarTableUpdate, retained, present] using steps
    · have absent : row ∉ updateSeen := fun old => present ((same row).1 old)
      simpa [scalarNovelty, scalarTableUpdate, absent, present] using
        congrArg (List.cons row) steps

theorem unique_worker_merge {Row : Type} [DecidableEq Row] (seed outputs : List Row)
    (novel : novelFrom seed outputs) :
    outputs.foldl checkedInsert seed = outputs.foldl (fun seen row => row :: seen) seed := by
  induction outputs generalizing seed with
  | nil => rfl
  | cons row rest ih =>
    obtain ⟨fresh, tail⟩ := novel
    simpa [List.foldl_cons, checkedInsert, fresh] using ih (row :: seed) tail

/-- The evaluator checks both committed rows and the rows staged during the
same run. Its accumulator counts exactly the rows that need publication. -/
def stageChecked {Row : Type} [DecidableEq Row]
    (committed pending : List Row) (row : Row) : List Row :=
  if row ∈ committed ∨ row ∈ pending then pending else row :: pending

theorem unique_worker_staging {Row : Type} [DecidableEq Row]
    (committed pending outputs : List Row)
    (novel : novelFrom (pending ++ committed) outputs) :
    outputs.foldl (stageChecked committed) pending =
      outputs.foldl (fun staged row => row :: staged) pending := by
  induction outputs generalizing pending with
  | nil => rfl
  | cons row rest ih =>
    obtain ⟨fresh, tail⟩ := novel
    have distinct : ¬ (row ∈ committed ∨ row ∈ pending) := by
      simpa [List.mem_append, or_comm] using fresh
    simpa [List.foldl_cons, stageChecked, distinct] using ih (row :: pending) tail

theorem original_staging_drops_repeats :
    [1, 1].foldl (stageChecked ([] : List Nat)) [] = [1] := by decide

/-- Each value records the pending-row charge after one owner merge.
The work checkpoint preceding each merge receives the same row stream. -/
def stagingCharges {Row : Type}
    (insert : List Row → Row → List Row) (pending : List Row) : List Row → List Nat
  | [] => []
  | row :: rest =>
    let next := insert pending row
    next.length :: stagingCharges insert next rest

theorem unique_worker_charge_prefix {Row : Type} [DecidableEq Row]
    (committed pending outputs : List Row)
    (novel : novelFrom (pending ++ committed) outputs) (stop : Nat) :
    (stagingCharges (stageChecked committed) pending outputs).take stop =
      (stagingCharges (fun staged row => row :: staged) pending outputs).take stop := by
  induction outputs generalizing pending stop with
  | nil => rfl
  | cons row rest ih =>
    obtain ⟨fresh, tail⟩ := novel
    have distinct : ¬ (row ∈ committed ∨ row ∈ pending) := by
      simpa [List.mem_append, or_comm] using fresh
    cases stop with
    | zero => rfl
    | succ stop =>
      simp [stagingCharges, stageChecked, distinct, ih (row :: pending) tail stop]

theorem repeating_worker_breaks_charge_prefix :
    stagingCharges (stageChecked ([] : List Nat)) [] [1, 1] ≠
      stagingCharges (fun staged row => row :: staged) [] [1, 1] := by decide

end ScalarComponentMerge

namespace TimedSession

/-- The owner distinguishes delivery of unfinished rows from publication of
a completed cut. Only a current and authorized worker can deliver either. -/
inductive Delivery where
  | refused
  | incomplete
  | complete
  deriving DecidableEq

def decideReturn (current authorized complete : Bool) : Delivery :=
  if current && authorized then
    if complete then .complete else .incomplete
  else .refused

def committedCut {Cut : Type} (previous candidate : Cut) : Delivery → Cut
  | .complete => candidate
  | _ => previous

theorem unfinished_keeps_committed_cut {Cut : Type} (old candidate : Cut)
    (current authorized : Bool) :
    committedCut old candidate (decideReturn current authorized false) = old := by
  cases current <;> cases authorized <;> rfl

theorem stale_worker_does_not_deliver (authorized complete : Bool) :
    decideReturn false authorized complete = .refused := by rfl

theorem denied_worker_does_not_deliver (current complete : Bool) :
    decideReturn current false complete = .refused := by
  cases current <;> rfl

/-- Eager replacement starts from an idle committed cut. The prospective
cut is worker-owned until completion and the owner's acceptance check. -/
def replaceCut {Cut : Type} (prior proposed : Cut) (delivery : Delivery) : Cut × Cut :=
  let published := committedCut prior proposed delivery
  (published, published)

theorem replacement_publishes_atomically {Cut : Type} (prior proposed : Cut)
    (current accepted finished : Bool) :
    replaceCut prior proposed (decideReturn current accepted finished) =
      if current && accepted && finished then (proposed, proposed) else (prior, prior) := by
  cases current <;> cases accepted <;> cases finished <;> rfl

/-- A suspended evaluator is eligible only on the same owned source cut.
Resume selects the new request's authorization independently of the old run. -/
def resumable {Cut : Type} [DecidableEq Cut] (saved pending : Cut)
    (owned : Bool) : Bool := owned && decide (saved = pending)

theorem resume_requires_same_owned_cut {Cut : Type} [DecidableEq Cut]
    (saved pending : Cut) (owned : Bool)
    (resume : resumable saved pending owned = true) :
    saved = pending ∧ owned = true := by
  simp [resumable, and_comm] at resume
  exact resume

end TimedSession

namespace WireScope

/-- The handle lookup first selects the owner and exact generation. Its
ordinary row export can then differ from complete-result proof admission. -/
def proofScope (ownerMatches exported finished : Bool) (current entry : Nat) : Bool :=
  ownerMatches && (decide (entry = current) && (exported && finished))

theorem partial_has_no_proof_scope (ownerMatches exported : Bool) (current entry : Nat) :
    proofScope ownerMatches exported false current entry = false := by
  simp [proofScope]

theorem accepted_replacement_revokes_prior_proof_scope
    (ownerMatches exported finished : Bool) (generation : Nat) :
    proofScope ownerMatches exported finished (generation + 1) generation = false := by
  simp [proofScope]

end WireScope

namespace ResidentTransport

inductive Transfer where
  | bytes (chunk : List UInt8)
  | wouldBlock
  | interrupted
  | eof
  | fault

inductive Failure where
  | eof | fault

/-- Both the header/body decoder and the reply writer retain their offset
while waiting. A wakeup adds no bytes, and EOF/fault terminates the stream. -/
def transferred : List Transfer → List UInt8 × Option Failure
  | [] => ([], none)
  | .bytes head :: tail => let (bytes, fault) := transferred tail; (head ++ bytes, fault)
  | .wouldBlock :: tail | .interrupted :: tail => transferred tail
  | .eof :: _ => ([], some .eof)
  | .fault :: _ => ([], some .fault)

def removeRetries : List Transfer → List Transfer
  | [] => []
  | .wouldBlock :: tail | .interrupted :: tail => removeRetries tail
  | event :: tail => event :: removeRetries tail

theorem retries_preserve_bytes_and_failure (events : List Transfer) :
    transferred (removeRetries events) = transferred events := by
  induction events with
  | nil => rfl
  | cons event tail ih => cases event <;> simp [transferred, removeRetries, ih]

inductive Phase where
  | receive | entered | invoke | reply
  deriving DecidableEq

def hasRequestAuthority (phase : Phase) : Prop := phase = .invoke

/-- On WouldBlock the transport can enter the Scheme scheduler only outside
the active ABI call. Checkpoint decisions keep the original caller's exchange. -/
def nativeWait (phase : Phase) (event : Transfer) : Prop :=
  match event with
  | .wouldBlock => phase ≠ .invoke
  | _ => False

theorem native_wait_cannot_inherit_authority (phase : Phase) (event : Transfer)
    (waiting : nativeWait phase event) : ¬ hasRequestAuthority phase := by
  cases event <;> simp_all [nativeWait, hasRequestAuthority]

end ResidentTransport

def name : Field → String
  | .kind => "kind"
  | .key => "key"
  | .worker => "worker"
  | .task => "task"
  | .payload => "payload"

def source : String :=
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Generated by ActorEnvelope.lean; arbitrary payload/reference identities stay intact.\n" ++
  "(export gerbil-ascent-send-envelope! gerbil-ascent-match-envelope!)\n" ++
  ";; gerbil-ascent-send-envelope!\n;; : (-> Thread MessageKind RunKey Worker Task Payload Void)\n;; | doc m%\n;;     Send one five-field envelope; preserve payload identity.\n;;\n;;     # Examples\n;;\n;;     ```scheme\n;;     (gerbil-ascent-send-envelope! owner 'done key worker task payload)\n;;     ;; => one mailbox envelope\n;;     ```\n;;   %\n(defrule (gerbil-ascent-send-envelope! owner " ++ String.intercalate " " (fields.map name) ++ ")\n  (thread-send owner [" ++ String.intercalate " " (fields.map name) ++ "]))\n" ++
  ";; gerbil-ascent-match-envelope!\n;; : (-> Message MatchBranch MalformedBranch Result)\n;; | doc m%\n;;     Bind an exact five-field envelope or select the malformed branch.\n;;\n;;     # Examples\n;;\n;;     ```scheme\n;;     (gerbil-ascent-match-envelope! 'bad ([k r w t p] #t) (else #f))\n;;     ;; => #f\n;;     ```\n;;   %\n(defrule (gerbil-ascent-match-envelope! message ([" ++ String.intercalate " " (fields.map name) ++ "] matched) (else malformed))\n  (match message\n    ([" ++ String.intercalate " " (fields.map name) ++ "] matched)\n    (else malformed)))\n"

end Ascent.ActorEnvelope
