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

def name : Field → String
  | .kind => "kind"
  | .key => "key"
  | .worker => "worker"
  | .task => "task"
  | .payload => "payload"

def source : String :=
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Generated by ActorEnvelope.lean; arbitrary payload/reference identities stay intact.\n" ++
  "(export gerbil-ascent-send-round! gerbil-ascent-match-round!)\n" ++
  ";; gerbil-ascent-send-round!\n;; : (-> Thread MessageKind RunKey Worker Task Payload Void)\n;; | doc m%\n;;     Send one five-field envelope; preserve payload identity.\n;;\n;;     # Examples\n;;\n;;     ```scheme\n;;     (gerbil-ascent-send-round! owner 'done key worker task payload)\n;;     ;; => one mailbox envelope\n;;     ```\n;;   %\n(defrule (gerbil-ascent-send-round! owner " ++ String.intercalate " " (fields.map name) ++ ")\n  (thread-send owner [" ++ String.intercalate " " (fields.map name) ++ "]))\n" ++
  ";; gerbil-ascent-match-round!\n;; : (-> Message MatchBranch MalformedBranch Result)\n;; | doc m%\n;;     Bind an exact five-field envelope or select the malformed branch.\n;;\n;;     # Examples\n;;\n;;     ```scheme\n;;     (gerbil-ascent-match-round! 'bad ([k r w t p] #t) (else #f))\n;;     ;; => #f\n;;     ```\n;;   %\n(defrule (gerbil-ascent-match-round! message ([" ++ String.intercalate " " (fields.map name) ++ "] matched) (else malformed))\n  (match message\n    ([" ++ String.intercalate " " (fields.map name) ++ "] matched)\n    (else malformed)))\n"

end Ascent.ActorEnvelope
