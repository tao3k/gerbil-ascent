-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import Std
namespace Ascent.ScopedWitness
variable {Vertex : Type}
def Witness (start target blocked : Vertex → Prop) (edge : Vertex → Vertex → Prop)
    (s w t : Vertex) := start s ∧ target t ∧ edge s w ∧ edge w t ∧ ¬ blocked w
def Answer (start target blocked : Vertex → Prop) (edge direct : Vertex → Vertex → Prop)
    (s t : Vertex) := (∃ w, Witness start target blocked edge s w t) ∨ (start s ∧ target t ∧ direct s t)

theorem witness_projects (h : Witness start target blocked edge s w t) :
    Answer start target blocked edge direct s t := Or.inl ⟨w,h⟩
theorem direct_preserved (hs : start s) (ht : target t) (hd : direct s t) :
    Answer start target blocked edge direct s t := Or.inr ⟨hs,ht,hd⟩
theorem blocked_antitone (grow : ∀ v, before v → after v)
    (h : Answer start target after edge direct s t) : Answer start target before edge direct s t := by
  rcases h with ⟨w,hs,ht,sw,wt,clean⟩ | direct
  · exact Or.inl ⟨w,hs,ht,sw,wt,fun hb => clean (grow w hb)⟩
  · exact Or.inr direct

def Project {AnswerVertex WitnessVertex : Type} (relation : AnswerVertex → WitnessVertex → Prop) :=
  fun answer => ∃ witness, relation answer witness
def MaskedProject {AnswerVertex WitnessVertex : Type} (blocked : WitnessVertex → Prop)
    (relation : AnswerVertex → WitnessVertex → Prop) :=
  fun answer => ∃ witness, relation answer witness ∧ ¬ blocked witness

-- A function receiving only the collapsed answer relation cannot distinguish
-- two equal projections whose correctly masked answers differ. It would need
-- additional witness/source information; that is an explicit hypothesis.
theorem no_answer_only_filter {AnswerVertex WitnessVertex : Type}
    (left right : AnswerVertex → WitnessVertex → Prop) (blocked : WitnessVertex → Prop)
    (same : Project left = Project right)
    (different : MaskedProject blocked left ≠ MaskedProject blocked right) :
    ¬ ∃ filter : (AnswerVertex → Prop) → (AnswerVertex → Prop),
      filter (Project left) = MaskedProject blocked left ∧
      filter (Project right) = MaskedProject blocked right := by
  rintro ⟨filter, hl, hr⟩
  apply different
  exact hl.symm.trans ((congrArg filter same).trans hr)

def bit (id place : Nat) : Bool := (id / place) % 2 == 1
def allowedPath (id w : Nat) : Bool :=
  if w == 1 then bit id 1 && bit id 2 && !bit id 16
  else bit id 4 && bit id 8 && !bit id 32
def witnessMask (id : Nat) := (if allowedPath id 1 then 1 else 0) + (if allowedPath id 2 then 2 else 0)
def grade (id : Nat) : List Nat := [id, witnessMask id, if witnessMask id != 0 || bit id 128 then 1 else 0]
def start (v : Fin 4) : Prop := v = 0
def target (v : Fin 4) : Prop := v = 3
def blocked (id : Nat) (v : Fin 4) : Prop :=
  (v = 1 ∧ bit id 16 = true) ∨ (v = 2 ∧ bit id 32 = true) ∨ (v = 3 ∧ bit id 64 = true)
def edge (id : Nat) (s t : Fin 4) : Prop :=
  (s = 0 ∧ t = 1 ∧ bit id 1 = true) ∨ (s = 1 ∧ t = 3 ∧ bit id 2 = true) ∨
  (s = 0 ∧ t = 2 ∧ bit id 4 = true) ∨ (s = 2 ∧ t = 3 ∧ bit id 8 = true)
def direct (id : Nat) (s t : Fin 4) : Prop := s = 0 ∧ t = 3 ∧ bit id 128 = true
def middle (w : Fin 2) : Fin 4 := if w.val = 0 then 1 else 2

set_option maxRecDepth 4096 in
theorem finite_witness : ∀ id : Fin 256, ∀ w : Fin 2,
    bit (witnessMask id.val) (w.val + 1) = true ↔
      Witness start target (blocked id.val) (edge id.val) 0 (middle w) 3 := by
  unfold Witness start target blocked edge
  decide
set_option maxRecDepth 4096 in
theorem finite_answer : ∀ id : Fin 256, (grade id.val)[2]? = some 1 ↔
    Answer start target (blocked id.val) (edge id.val) (direct id.val) 0 3 := by
  unfold Answer Witness start target blocked edge direct
  decide
def corpus := (List.range 256).map grade
end Ascent.ScopedWitness

def main (args : List String) : IO Unit := do
  unless args.length == 2 do throw (IO.userError "expected current Quint output and frozen corpus paths")
  let expected := Lean.toJson Ascent.ScopedWitness.corpus
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"invalid corpus {path}: {message}")
    unless parsed == expected do throw (IO.userError s!"scoped witness conformance differs: {path}")
  IO.println "SCOPED-WITNESS-CONFORMANCE-LEAN-OK cases=256"
