-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
namespace Ascent.PipeCapture

inductive Event (Byte : Type) where
  | chunk (bytes : List Byte) | interrupted | eof | failed
structure State (Byte : Type) where
  bytes : List Byte
  closed : Bool
  failed : Bool

def initial : State Byte := ⟨[],false,false⟩
def terminal (state : State Byte) : Bool := state.closed || state.failed

def step (state : State Byte) (event : Event Byte) : State Byte :=
  if terminal state then state else
    match event with
    | .chunk bytes => ⟨state.bytes ++ bytes,false,false⟩
    | .interrupted => state
    | .eof => ⟨state.bytes,true,false⟩
    | .failed => ⟨state.bytes,false,true⟩

def replay : State Byte → List (Event Byte) → State Byte
  | state, [] => state
  | state, event :: rest => replay (step state event) rest

-- Expected data is computed from the event history, stopping at EOF/error.
def payload : List (Event Byte) → List Byte
  | [] => []
  | .chunk bytes :: rest => bytes ++ payload rest
  | .interrupted :: rest => payload rest
  | .eof :: _ | .failed :: _ => []

theorem interrupted_inert (state : State Byte) : step state .interrupted = state := by
  simp [step]

theorem terminal_replay (state : State Byte) (done : terminal state = true)
    (events : List (Event Byte)) : replay state events = state := by
  induction events with
  | nil => rfl
  | cons event rest ih => simpa [replay,step,done] using ih

theorem live_payload_exact (state : State Byte) (live : terminal state = false)
    (events : List (Event Byte)) : (replay state events).bytes = state.bytes ++ payload events := by
  induction events generalizing state with
  | nil => simp [replay,payload]
  | cons event rest ih =>
    cases event with
    | chunk bytes =>
      simpa only [replay,step,live,Bool.false_eq_true,ite_false,payload,List.append_assoc] using
        (ih (⟨state.bytes ++ bytes,false,false⟩ : State Byte) (by rfl))
    | interrupted => simpa [replay,interrupted_inert,payload] using ih state live
    | eof =>
      simp only [replay,step,live,Bool.false_eq_true,ite_false]
      rw [terminal_replay _ (by rfl) rest]
      simp [payload]
    | failed =>
      simp only [replay,step,live,Bool.false_eq_true,ite_false]
      rw [terminal_replay _ (by rfl) rest]
      simp [payload]

theorem capture_exact (events : List (Event Byte)) :
    (replay initial events).bytes = payload events := by
  simpa [initial] using live_payload_exact (initial : State Byte) (by rfl) events

theorem partial_bytes_retained (state : State Byte) (live : terminal state = false)
    (events : List (Event Byte)) : (replay (step state .failed) events).bytes = state.bytes := by
  simp only [step,live,Bool.false_eq_true,ite_false]
  rw [terminal_replay _ (by rfl) events]

def Admitted (state : State Byte) (processSuccess requestSuccess : Bool) : Prop :=
  state.closed = true ∧ state.failed = false ∧ processSuccess = true ∧ requestSuccess = true

theorem error_rejected (state : State Byte) (process request : Bool)
    (failure : state.failed = true) : ¬ Admitted state process request := by
  simp [Admitted,failure]

theorem missing_eof_rejected (state : State Byte) (process request : Bool)
    (openPipe : state.closed = false) : ¬ Admitted state process request := by
  simp [Admitted,openPipe]

theorem process_failure_rejected (state : State Byte) (request : Bool) :
    ¬ Admitted state false request := by simp [Admitted]

theorem request_failure_rejected (state : State Byte) (process : Bool) :
    ¬ Admitted state process false := by simp [Admitted]

end Ascent.PipeCapture
