/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Unbounded-generation atomic publication contract. The completed solver result
is a premise; this does not prove the Gerbil Session implements the protocol.
-/
import Std

namespace Ascent.Publication

structure Snapshot (Source Result : Type) where
  generation : Nat
  source : Source
  result : Result

structure Work (Source Result : Type) where
  base : Nat
  source : Source
  completed : Option Result

def publish {Source Result : Type} (old : Snapshot Source Result)
    (work : Work Source Result) : Snapshot Source Result :=
  if work.base = old.generation then
    match work.completed with
    | none => old
    | some result => ⟨old.generation + 1, work.source, result⟩
  else old

theorem stale_preserves_snapshot {Source Result : Type}
    (old : Snapshot Source Result) (work : Work Source Result)
    (stale : work.base ≠ old.generation) : publish old work = old := by
  simp [publish, stale]

theorem incomplete_preserves_snapshot {Source Result : Type}
    (old : Snapshot Source Result) (work : Work Source Result)
    (incomplete : work.completed = none) : publish old work = old := by
  simp [publish, incomplete]

theorem completed_publication {Source Result : Type}
    (old : Snapshot Source Result) (work : Work Source Result) (result : Result)
    (current : work.base = old.generation) (complete : work.completed = some result) :
    publish old work = ⟨old.generation + 1, work.source, result⟩ := by
  simp [publish, current, complete]

theorem publication_consistent {Source Result : Type}
    (solve : Source → Result) (old : Snapshot Source Result)
    (work : Work Source Result) (previous : old.result = solve old.source)
    (qualified : ∀ result, work.completed = some result → result = solve work.source) :
    (publish old work).result = solve (publish old work).source := by
  by_cases current : work.base = old.generation
  · cases complete : work.completed with
    | none => simpa [publish, current, complete] using previous
    | some result => simpa [publish, current, complete] using qualified result complete
  · simpa [publish, current] using previous

/-- A sequence of qualified work items preserves publication consistency at
    every length. There is no generation or trace-length cutoff in this proof. -/
theorem publications_consistent {Source Result : Type}
    (solve : Source → Result) (initial : Snapshot Source Result)
    (works : List (Work Source Result))
    (initial_consistent : initial.result = solve initial.source)
    (qualified : ∀ work ∈ works, ∀ result,
      work.completed = some result → result = solve work.source) :
    (works.foldl publish initial).result =
      solve (works.foldl publish initial).source := by
  induction works generalizing initial with
  | nil => simpa using initial_consistent
  | cons work rest ih =>
      simp only [List.foldl_cons]
      apply ih (initial := publish initial work)
      · apply publication_consistent solve initial work initial_consistent
        exact qualified work (by simp)
      · intro next hnext result hcomplete
        exact qualified next (by simp [hnext]) result hcomplete

end Ascent.Publication

/-! Native actor Session ownership fragment. `finish` is called only after the
monitor joins the evaluator; success is a completed-solve premise. No VM or
scheduler liveness refinement is asserted. Generation is an unbounded Nat. -/
namespace Ascent.ActorPublication
structure State (Cut Result : Type) where
  generation : Nat
  pending : Cut
  committed : Cut
  published : Option (Cut × Result)
  running : Option (Nat × Cut)

def start (state : State Cut Result) : State Cut Result :=
  { state with generation := state.generation + 1,
               running := some (state.generation + 1, state.pending) }

def cancel (state : State Cut Result) : State Cut Result :=
  match state.running with
  | none => state
  | some _ => { state with generation := state.generation + 1 }

def finish (state : State Cut Result) (epoch : Nat)
    (outcome : Option Result) : State Cut Result :=
  match state.running with
  | none => state
  | some (assigned, cut) =>
    if epoch = assigned then
      match outcome with
      | some result =>
        if epoch = state.generation then
          { state with running := none, committed := cut, published := some (cut, result) }
        else { state with running := none, pending := state.committed }
      | none => { state with running := none, pending := state.committed }
    else state

theorem cancel_preserves_publication (state : State Cut Result) :
    (cancel state).published = state.published := by
  simp only [cancel]; split <;> rfl

theorem idle_reply (state : State Cut Result) (epoch : Nat) (result : Option Result)
    (idle : state.running = none) : finish state epoch result = state := by
  simp [finish, idle]

theorem mismatched_assigned_reply (state : State Cut Result) (epoch assigned : Nat)
    (cut : Cut) (outcome : Option Result) (running : state.running = some (assigned, cut))
    (foreign : epoch ≠ assigned) : finish state epoch outcome = state := by
  simp [finish, running, foreign]

theorem failed_preserves_publication (state : State Cut Result) (epoch : Nat) :
    (finish state epoch none).published = state.published := by
  unfold finish; split
  · rfl
  · split <;> rfl

theorem canceled_completion_preserves_publication (state : State Cut Result)
    (cut : Cut) (result : Result) (running : state.running = some (state.generation, cut)) :
    (finish (cancel state) state.generation (some result)).published = state.published := by
  simp [finish, cancel, running]

theorem canceled_completion_drained (state : State Cut Result)
    (cut : Cut) (result : Result) (running : state.running = some (state.generation, cut)) :
    (finish (cancel state) state.generation (some result)).running = none := by
  simp [finish, cancel, running]
end Ascent.ActorPublication
