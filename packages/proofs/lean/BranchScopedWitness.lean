-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import Std
namespace Ascent.BranchScopedWitness
variable {Scope Vertex : Type}

def Witness (start target blocked : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (scope : Scope) (s w t : Vertex) :=
  start scope s ∧ target scope t ∧ edge s w ∧ edge w t ∧ ¬ blocked scope w
def Answer (start target blocked : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (direct : Scope → Vertex → Vertex → Prop)
    (scope : Scope) (s t : Vertex) :=
  (∃ w, Witness start target blocked edge scope s w t) ∨
  (start scope s ∧ target scope t ∧ direct scope s t)
def UnionAnswer (start target blocked : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (direct : Scope → Vertex → Vertex → Prop) (s t : Vertex) :=
  ∃ scope, Answer start target blocked edge direct scope s t

theorem witness_mask_local (same : ∀ v, before scope v ↔ after scope v) :
    Witness start target before edge scope s w t ↔ Witness start target after edge scope s w t := by
  constructor
  · rintro ⟨hs,ht,sw,wt,clean⟩
    exact ⟨hs,ht,sw,wt,fun blocked => clean ((same w).mpr blocked)⟩
  · rintro ⟨hs,ht,sw,wt,clean⟩
    exact ⟨hs,ht,sw,wt,fun blocked => clean ((same w).mp blocked)⟩

theorem answer_mask_local (same : ∀ v, before scope v ↔ after scope v) :
    Answer start target before edge direct scope s t ↔ Answer start target after edge direct scope s t := by
  constructor
  · rintro (⟨w,h⟩ | h)
    · exact Or.inl ⟨w,(witness_mask_local same).mp h⟩
    · exact Or.inr h
  · rintro (⟨w,h⟩ | h)
    · exact Or.inl ⟨w,(witness_mask_local same).mpr h⟩
    · exact Or.inr h

-- A surviving branch supplies the union even if another branch loses all paths.
theorem surviving_branch_preserves_union (same : ∀ v, before scope v ↔ after scope v)
    (h : Answer start target before edge direct scope s t) :
    UnionAnswer start target after edge direct s t :=
  ⟨scope,(answer_mask_local same).mp h⟩

theorem direct_preserved (hs : start scope s) (ht : target scope t) (hd : direct scope s t) :
    Answer start target blocked edge direct scope s t := Or.inr ⟨hs,ht,hd⟩

def bit (id place : Nat) : Bool := (id / place) % 2 == 1
def allowed (id scope middle : Nat) : Bool :=
  (if middle == 0 then bit id 1 && bit id 2 else bit id 4 && bit id 8) &&
  !bit id (16 * 2 ^ (scope * 2 + middle))
def witnessMask (id : Nat) := (List.range 4).foldl
  (fun mask slot => mask + if allowed id (slot / 2) (slot % 2) then 2 ^ slot else 0) 0
def answer (id scope : Nat) : Bool := allowed id scope 0 || allowed id scope 1 || bit id (256 * 2 ^ scope)
def answerMask (id : Nat) := (if answer id 0 then 1 else 0) + (if answer id 1 then 2 else 0)
def grade (id : Nat) : List Nat := [id, witnessMask id, answerMask id, if answerMask id != 0 then 1 else 0]
def start (_ : Fin 2) (v : Fin 4) : Prop := v = 0
def target (_ : Fin 2) (v : Fin 4) : Prop := v = 3
def blocked (id : Nat) (scope : Fin 2) (v : Fin 4) : Prop :=
  (v = 1 ∧ bit id (16 * 2 ^ (scope.val * 2)) = true) ∨
  (v = 2 ∧ bit id (16 * 2 ^ (scope.val * 2 + 1)) = true)
def edge (id : Nat) (s t : Fin 4) : Prop :=
  (s = 0 ∧ t = 1 ∧ bit id 1 = true) ∨ (s = 1 ∧ t = 3 ∧ bit id 2 = true) ∨
  (s = 0 ∧ t = 2 ∧ bit id 4 = true) ∨ (s = 2 ∧ t = 3 ∧ bit id 8 = true)
def direct (id : Nat) (scope : Fin 2) (s t : Fin 4) : Prop :=
  s = 0 ∧ t = 3 ∧ bit id (256 * 2 ^ scope.val) = true
def middle (w : Fin 2) : Fin 4 := if w.val = 0 then 1 else 2

-- Keep finite decision procedures modular. Expanding all three relations at
-- once duplicates their decision tree and exceeds instance synthesis size.
instance (id : Nat) (scope : Fin 2) (s w t : Fin 4) :
    Decidable (Witness start target (blocked id) (edge id) scope s w t) := by
  unfold Witness start target blocked edge
  infer_instance
instance (id : Nat) (scope : Fin 2) (s t : Fin 4) :
    Decidable (Answer start target (blocked id) (edge id) (direct id) scope s t) := by
  haveI : Decidable (start scope s ∧ target scope t ∧ direct id scope s t) := by
    unfold start target direct
    infer_instance
  unfold Answer
  infer_instance
instance (id : Nat) (s t : Fin 4) :
    Decidable (UnionAnswer start target (blocked id) (edge id) (direct id) s t) := by
  unfold UnionAnswer
  infer_instance

set_option maxRecDepth 8192 in
theorem finite_witness : ∀ id : Fin 1024, ∀ scope w : Fin 2,
    bit (witnessMask id.val) (2 ^ (scope.val * 2 + w.val)) = true ↔
      Witness start target (blocked id.val) (edge id.val) scope 0 (middle w) 3 := by
  decide
set_option maxRecDepth 8192 in
theorem finite_answer : ∀ id : Fin 1024, ∀ scope : Fin 2,
    bit (answerMask id.val) (2 ^ scope.val) = true ↔
      Answer start target (blocked id.val) (edge id.val) (direct id.val) scope 0 3 := by
  decide
set_option maxRecDepth 8192 in
theorem finite_union : ∀ id : Fin 1024, (grade id.val)[3]? = some 1 ↔
    UnionAnswer start target (blocked id.val) (edge id.val) (direct id.val) 0 3 := by
  have projection : ∀ id : Fin 1024, (grade id.val)[3]? = some 1 ↔
      ∃ scope : Fin 2, bit (answerMask id.val) (2 ^ scope.val) = true := by decide
  intro id
  constructor
  · intro h
    rcases (projection id).mp h with ⟨scope, supported⟩
    exact ⟨scope,(finite_answer id scope).mp supported⟩
  · rintro ⟨scope, supported⟩
    exact (projection id).mpr ⟨scope,(finite_answer id scope).mpr supported⟩
def corpus := (List.range 1024).map grade
end Ascent.BranchScopedWitness

def Ascent.BranchScopedWitness.checkConformance (args : List String) : IO Unit := do
  unless args.length == 2 do throw (IO.userError "expected current Quint output and frozen corpus paths")
  let expected := Lean.toJson Ascent.BranchScopedWitness.corpus
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"invalid corpus {path}: {message}")
    unless parsed == expected do throw (IO.userError s!"branch scoped witness conformance differs: {path}")
  IO.println "BRANCH-SCOPED-WITNESS-CONFORMANCE-LEAN-OK cases=1024"
