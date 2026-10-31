-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
namespace Ascent.MovieCastQuery
-- Film and Actor are different slot types; conjunction binds one shared actor.
variable {Film Actor : Type}
def Evidence (cast : Film → Actor → Prop) (selected : Bool → Film → Prop)
    (blocked : Actor → Prop) (global : Bool) (scope : Bool) (film : Film) (actor : Actor) :=
  cast film actor ∧ selected scope film ∧ ((scope = true ∧ global = false) ∨ ¬ blocked actor)
def AnyAnswer (evidence : Bool → Film → Actor → Prop) (actor : Actor) :=
  ∃ scope film, evidence scope film actor
def AllAnswer (evidence : Bool → Film → Actor → Prop) (actor : Actor) :=
  (∃ film, evidence false film actor) ∧ (∃ film, evidence true film actor)
def Trace (answer : Actor → Prop) (evidence : Bool → Film → Actor → Prop)
    (scope : Bool) (film : Film) (actor : Actor) := answer actor ∧ evidence scope film actor
theorem all_has_both_traces (h : AllAnswer evidence actor) :
    (∃ film, Trace (AllAnswer evidence) evidence false film actor) ∧
    (∃ film, Trace (AllAnswer evidence) evidence true film actor) := by
  rcases h with ⟨⟨l,hl⟩,⟨r,hr⟩⟩
  exact ⟨⟨l,⟨⟨l,hl⟩,⟨r,hr⟩⟩,hl⟩,⟨r,⟨⟨l,hl⟩,⟨r,hr⟩⟩,hr⟩⟩
theorem trace_preserves_evidence (h : Trace answer evidence scope film actor) :
    evidence scope film actor := h.2
theorem any_has_trace (h : AnyAnswer evidence actor) :
    ∃ scope film, Trace (AnyAnswer evidence) evidence scope film actor := by
  rcases h with ⟨scope,film,he⟩
  exact ⟨scope,film,⟨scope,film,he⟩,he⟩
-- A blocked actor may survive the unaffected right branch.
theorem scoped_union_counterexample : ((true && !true) || true) ≠ ((true || true) && !true) := by decide

def bit (id n : Nat) : Bool := id / 2^n % 2 == 1
def supportBase (bits : Nat) (global scope : Bool) (actor : Nat) : Bool :=
  bit bits ((if scope then 3 else 0)+actor) && (!bit bits (6+actor) || (scope && !global))
def support (id scope actor : Nat) : Bool := supportBase (id%512) (id/512 == 1) (scope == 1) actor
def FinCast (bits : Nat) (film : Bool) (actor : Fin 3) := bit bits ((if film then 3 else 0)+actor.val) = true
def FinSelected (scope film : Bool) := scope = film
def FinBlocked (bits : Nat) (actor : Fin 3) := bit bits (6+actor.val) = true
instance (bits : Nat) (global scope film : Bool) (actor : Fin 3) :
    Decidable (Evidence (FinCast bits) FinSelected (FinBlocked bits) global scope film actor) := by
  unfold Evidence FinCast FinSelected FinBlocked
  infer_instance
set_option maxRecDepth 4096 in
theorem finite_evidence : ∀ bits : Fin 512, ∀ global scope : Bool, ∀ actor : Fin 3,
    supportBase bits.val global scope actor.val = true ↔
      Evidence (FinCast bits.val) FinSelected (FinBlocked bits.val) global scope scope actor := by decide
def answer (id actor : Nat) : Bool := if id/512 == 2 then support id 0 actor && support id 1 actor
  else support id 0 actor || support id 1 actor
def mask (n : Nat) (p : Nat → Bool) := (List.range n).foldl (fun m slot => if p slot then m+2^slot else m) 0
def grade (id : Nat) := [id,mask 6 (fun p => support id (p/3) (p%3)), mask 3 (answer id),
  mask 6 (fun p => answer id (p%3) && support id (p/3) (p%3))]
def corpus := (List.range 1536).map grade
def check (args : List String) : IO Unit := do
  unless args.length == 2 do throw (IO.userError "expected current and frozen movie corpus")
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok value => pure value
      | .error reason => throw (IO.userError reason)
    unless parsed == Lean.toJson corpus do throw (IO.userError s!"movie corpus differs: {path}")
  IO.println "MOVIE-CAST-CONFORMANCE-LEAN-OK cases=1536"
end Ascent.MovieCastQuery
