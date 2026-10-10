-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
namespace Ascent.MaterializedMovieQuery
variable {Film Actor Director Country : Type}
def Eligible (cast : Film → Actor → Prop) (directed : Film → Director → Prop)
    (citizen : Director → Country → Prop) (c : Country) (f : Film) (d : Director) (a : Actor) :=
  cast f a ∧ directed f d ∧ citizen d c
def Coactor (cast : Film → Actor → Prop) (anchor a : Actor) (f : Film) :=
  cast f anchor ∧ cast f a
def QualifiedCoactor (cast : Film → Actor → Prop) (directed : Film → Director → Prop)
    (citizen : Director → Country → Prop) (c : Country) (anchor a : Actor) (f : Film) :=
  Coactor cast anchor a f ∧ ∃ d, directed f d ∧ citizen d c
theorem qualified_view_rewrite (cast : Film → Actor → Prop) (directed : Film → Director → Prop)
    (citizen : Director → Country → Prop) :
    QualifiedCoactor cast directed citizen c anchor a f ↔
      ∃ d, Eligible cast directed citizen c f d a ∧ Coactor cast anchor a f := by
  constructor
  · rintro ⟨hc, d, hd, hcit⟩
    exact ⟨d, ⟨hc.2, hd, hcit⟩, hc⟩
  · rintro ⟨d, he, hc⟩
    exact ⟨hc, d, he.2⟩
def Answer (eligible : Country → Film → Director → Actor → Prop)
    (coactor : Actor → Actor → Film → Prop) (country : Country) (anchor : Actor)
    (omitted : Film → Prop) (blocked : Actor → Prop) (join maskLeft maskRight : Bool) (a : Actor) :=
  let l := ∃ f d, eligible country f d a ∧ ¬ omitted f ∧ (maskLeft = false ∨ ¬ blocked a)
  let r := ∃ f, coactor anchor a f ∧ (maskRight = false ∨ ¬ blocked a)
  if join then l ∧ r else l ∨ r
theorem union_preserves_right
    (h : ∃ f, coactor anchor a f ∧ (mr = false ∨ ¬ blocked a)) :
    Answer eligible coactor country anchor omitted blocked false ml mr a := by
  exact Or.inr h
theorem join_requires_both
    (h : Answer eligible coactor country anchor omitted blocked true ml mr a) :
    (∃ f d, eligible country f d a ∧ ¬ omitted f ∧ (ml = false ∨ ¬ blocked a)) ∧
    (∃ f, coactor anchor a f ∧ (mr = false ∨ ¬ blocked a)) := h
-- Substitution is sound only with current, extensionally equal materialized views.
theorem materialized_substitution
    (e e' : Country → Film → Director → Actor → Prop)
    (r r' : Actor → Actor → Film → Prop)
    (he : ∀ c f d a, e c f d a ↔ e' c f d a)
    (hr : ∀ x a f, r x a f ↔ r' x a f) :
    Answer e r country anchor omitted blocked join ml mr a ↔
      Answer e' r' country anchor omitted blocked join ml mr a := by
  have ee : e = e' := funext fun c => funext fun f => funext fun d => funext fun a => propext (he c f d a)
  have rr : r = r' := funext fun x => funext fun a => funext fun f => propext (hr x a f)
  rw [ee, rr]

def bit (id n : Nat) : Bool := id / 2^n % 2 == 1
def cast (id f a : Nat) : Bool := bit (id%256) (f*3+a) && !(id/256 == 1 && f == 1 && a == 1)
def eligible (id f a : Nat) := cast id f a && bit (id%256) (6+f)
def coactor (id f a : Nat) := cast id f 0 && cast id f a
def left (id mode a : Nat) := eligible id 1 a && (!(mode%3 != 2) || a != 0)
def right (id mode a : Nat) := (coactor id 0 a || coactor id 1 a) && (!(mode%3 == 1) || a != 0)
def answer (id mode a : Nat) := if mode/3 == 0 then left id mode a && right id mode a
  else left id mode a || right id mode a
def mask (n : Nat) (p : Nat → Bool) := (List.range n).foldl (fun m i => if p i then m+2^i else m) 0
def grade (n : Nat) := let id := n/6; let mode := n%6
  [n, mask 6 (fun p => eligible id (p/3) (p%3)), mask 6 (fun p => coactor id (p/3) (p%3)), mask 3 (answer id mode)]
def corpus := (List.range 3072).map grade
def check (args : List String) : IO Unit := do
  unless args.length > 0 do throw (IO.userError "expected Quint correspondence paths")
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok x => pure x
      | .error e => throw (IO.userError e)
    unless parsed == Lean.toJson corpus do throw (IO.userError s!"materialized movie correspondence differs: {path}")
  IO.println "MATERIALIZED-MOVIE-LEAN-OK observations=3072"
end Ascent.MaterializedMovieQuery
def main := Ascent.MaterializedMovieQuery.check
