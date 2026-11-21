-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

namespace Ascent.ActorReply

/-- A private, fresh one-shot endpoint. Payload includes success/failure and
the original opaque outcome; the endpoint identity is not caller mailbox data. -/
inductive Endpoint (Payload : Type) where
  | pending : Endpoint Payload
  | posted : Payload → Endpoint Payload
  | consumed : Endpoint Payload
  deriving DecidableEq

def post (outcome : Payload) : Endpoint Payload → Option (Endpoint Payload)
  | .pending => some (.posted outcome)
  | _ => none

def take : Endpoint Payload → Option (Payload × Endpoint Payload)
  | .posted outcome => some (outcome, .consumed)
  | _ => none

theorem post_then_take_exact (outcome : Payload) :
    (post outcome .pending).bind take = some (outcome, .consumed) := rfl

theorem pending_cannot_return : take (Endpoint.pending : Endpoint Payload) = none := rfl

theorem consumed_cannot_return : take (Endpoint.consumed : Endpoint Payload) = none := rfl

theorem duplicate_post_refused (first second : Payload) :
    post second (.posted first) = none := rfl

/-- No reset/reuse transition exists; a late post cannot reopen a consumed endpoint. -/
theorem consumed_cannot_reopen (outcome : Payload) :
    post outcome .consumed = none := rfl

/-- Request identity and authority are arbitrary; no reconstruction changes them. -/
theorem request_authority_exact (request authority : Identity) (outcome : Payload) :
    (post (request, authority, outcome) .pending).bind take =
      some ((request, authority, outcome), .consumed) := rfl

/-- STD Completion remains ready after waiting. Consumption belongs to the
private request protocol, not to the standard library's mutable ready flag. -/
inductive CompletionState (Payload : Type) where
  | pending : CompletionState Payload
  | ready : Payload → CompletionState Payload

def completionPost (outcome : Payload) : CompletionState Payload → Option (CompletionState Payload)
  | .pending => some (.ready outcome)
  | .ready _ => none

def completionWait : CompletionState Payload → Option (Payload × CompletionState Payload)
  | .pending => none
  | .ready outcome => some (outcome, .ready outcome)

def Corresponds : Endpoint Payload → CompletionState Payload → Prop
  | .pending, .pending => True
  | .posted expected, .ready actual => expected = actual
  | .consumed, .ready _ => True
  | _, _ => False

theorem post_refinement (outcome : Payload) (logical : Endpoint Payload)
    (native : CompletionState Payload) (matched : Corresponds logical native) :
    match post outcome logical, completionPost outcome native with
    | some nextLogical, some nextNative => Corresponds nextLogical nextNative
    | none, none => True
    | _, _ => False := by
  cases logical <;> cases native <;> simp_all [post, completionPost, Corresponds]

theorem wait_refinement (logical : Endpoint Payload) (native : CompletionState Payload)
    (outcome : Payload) (next : Endpoint Payload) (matched : Corresponds logical native)
    (returned : take logical = some (outcome, next)) :
    completionWait native = some (outcome, native) ∧ Corresponds next native := by
  cases logical with
  | pending => simp [take] at returned
  | consumed => simp [take] at returned
  | posted value =>
    have exact : value = outcome ∧ (Endpoint.consumed : Endpoint Payload) = next := by
      simpa only [take, Option.some.injEq, Prod.mk.injEq] using returned
    rcases exact with ⟨rfl, rfl⟩
    cases native with
    | pending => simp [Corresponds] at matched
    | ready actual =>
      have same : value = actual := matched
      subst actual
      simp [completionWait, Corresponds]

end Ascent.ActorReply

#print axioms Ascent.ActorReply.post_then_take_exact
#print axioms Ascent.ActorReply.pending_cannot_return
#print axioms Ascent.ActorReply.consumed_cannot_return
#print axioms Ascent.ActorReply.duplicate_post_refused
#print axioms Ascent.ActorReply.consumed_cannot_reopen
#print axioms Ascent.ActorReply.request_authority_exact
#print axioms Ascent.ActorReply.post_refinement
#print axioms Ascent.ActorReply.wait_refinement
