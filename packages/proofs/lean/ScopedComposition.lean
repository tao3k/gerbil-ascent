-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import Std
import BranchScopedWitness
namespace Ascent.ScopedComposition
variable {Group Scope Vertex : Type}
def Witness (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (g : Group) (scope : Scope) (s t : Vertex) :=
  candidate s t ∧ required g ∧ member g scope ∧ branch scope s t
def Covered (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (g : Group) (s t : Vertex) :=
  ∃ scope, Witness candidate required member branch g scope s t
def Missing (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (g : Group) (s t : Vertex) :=
  candidate s t ∧ required g ∧ ¬ Covered candidate required member branch g s t
def NativeAnswer (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (s t : Vertex) :=
  candidate s t ∧ ¬ ∃ g, Missing candidate required member branch g s t
def Answer (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (s t : Vertex) :=
  candidate s t ∧ ∀ g, required g → ∃ scope, member g scope ∧ branch scope s t

-- Stratified relational division is AND over required groups, OR over members.
theorem no_missing_iff_answer : NativeAnswer candidate required member branch s t ↔
    Answer candidate required member branch s t := by
  classical
  constructor
  · rintro ⟨selected, noMissing⟩
    refine ⟨selected, fun g hg => ?_⟩
    apply Classical.byContradiction
    intro unsupported
    apply noMissing
    refine ⟨g,selected,hg,?_⟩
    rintro ⟨scope,_,_,hm,hb⟩
    exact unsupported ⟨scope,hm,hb⟩
  · rintro ⟨selected, supported⟩
    refine ⟨selected,?_⟩
    rintro ⟨g,_,hg,missing⟩
    rcases supported g hg with ⟨scope,hm,hb⟩
    exact missing ⟨scope,selected,hg,hm,hb⟩

theorem empty_group_reject (hg : required g) (empty : ∀ scope, ¬ member g scope) :
    ¬ Answer candidate required member branch s t := by
  rintro ⟨_,supported⟩
  rcases supported g hg with ⟨scope,hm,_⟩
  exact empty scope hm
theorem no_required_groups (none : ∀ g, ¬ required g) :
    Answer candidate required member branch s t ↔ candidate s t := by
  constructor
  · exact fun h => h.1
  · exact fun selected => ⟨selected,fun g hg => False.elim (none g hg)⟩
theorem branches_monotone (grow : ∀ scope s t, before scope s t → after scope s t)
    (h : Answer candidate required member before s t) : Answer candidate required member after s t := by
  refine ⟨h.1,fun g hg => ?_⟩
  rcases h.2 g hg with ⟨scope,hm,hb⟩
  exact ⟨scope,hm,grow scope s t hb⟩

-- Connect composition to the lower-stage scope law: masks outside required
-- member scopes may change without changing the composed answer.
theorem scope_masks_local (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (start target before after : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (direct : Scope → Vertex → Vertex → Prop) (s t : Vertex)
    (same : ∀ g scope, required g → member g scope → ∀ v, before scope v ↔ after scope v) :
    Answer candidate required member (BranchScopedWitness.Answer start target before edge direct) s t ↔
    Answer candidate required member (BranchScopedWitness.Answer start target after edge direct) s t := by
  constructor
  · rintro ⟨selected,supported⟩
    refine ⟨selected,fun g hg => ?_⟩
    rcases supported g hg with ⟨scope,hm,hb⟩
    exact ⟨scope,hm,(BranchScopedWitness.answer_mask_local (same g scope hg hm)).mp hb⟩
  · rintro ⟨selected,supported⟩
    refine ⟨selected,fun g hg => ?_⟩
    rcases supported g hg with ⟨scope,hm,hb⟩
    exact ⟨scope,hm,(BranchScopedWitness.answer_mask_local (same g scope hg hm)).mpr hb⟩

def bit (id place : Nat) : Bool := (id / place) % 2 == 1
def candidate (id : Nat) (s t : Fin 4) : Prop := s = 0 ∧ t = 3 ∧ bit id 256 = true
def required (id : Nat) (g : Fin 2) : Prop := bit id (64 * 2 ^ g.val) = true
def member (id : Nat) (g scope : Fin 2) : Prop := bit id (4 * 2 ^ (g.val * 2 + scope.val)) = true
def branch (id : Nat) (scope : Fin 2) (s t : Fin 4) : Prop := s = 0 ∧ t = 3 ∧ bit id (2 ^ scope.val) = true
def allowed (id g scope : Nat) : Bool :=
  bit id 256 && bit id (64 * 2 ^ g) && bit id (4 * 2 ^ (g * 2 + scope)) && bit id (2 ^ scope)
def covered (id g : Nat) : Bool := allowed id g 0 || allowed id g 1
def missing (id g : Nat) : Bool := bit id 256 && bit id (64 * 2 ^ g) && !covered id g
def witnessMask (id : Nat) := (List.range 4).foldl
  (fun mask slot => mask + if allowed id (slot / 2) (slot % 2) then 2 ^ slot else 0) 0
def coverageMask (id : Nat) := (if covered id 0 then 1 else 0) + (if covered id 1 then 2 else 0)
def missingMask (id : Nat) := (if missing id 0 then 1 else 0) + (if missing id 1 then 2 else 0)
def grade (id : Nat) : List Nat :=
  [id,witnessMask id,coverageMask id,missingMask id,if bit id 256 && !missing id 0 && !missing id 1 then 1 else 0]

instance (id : Nat) (s t : Fin 4) : Decidable (candidate id s t) := by unfold candidate; infer_instance
instance (id : Nat) (g : Fin 2) : Decidable (required id g) := by unfold required; infer_instance
instance (id : Nat) (g scope : Fin 2) : Decidable (member id g scope) := by unfold member; infer_instance
instance (id : Nat) (scope : Fin 2) (s t : Fin 4) : Decidable (branch id scope s t) := by unfold branch; infer_instance
instance (id : Nat) (g scope : Fin 2) (s t : Fin 4) :
    Decidable (Witness (candidate id) (required id) (member id) (branch id) g scope s t) := by
  unfold Witness; infer_instance
instance (id : Nat) (g : Fin 2) (s t : Fin 4) :
    Decidable (Covered (candidate id) (required id) (member id) (branch id) g s t) := by
  unfold Covered; infer_instance
instance (id : Nat) (g : Fin 2) (s t : Fin 4) :
    Decidable (Missing (candidate id) (required id) (member id) (branch id) g s t) := by
  unfold Missing; infer_instance
instance (id : Nat) (s t : Fin 4) :
    Decidable (NativeAnswer (candidate id) (required id) (member id) (branch id) s t) := by
  unfold NativeAnswer; infer_instance

set_option maxRecDepth 4096 in
theorem finite_witness : ∀ id : Fin 512, ∀ g scope : Fin 2,
    bit (witnessMask id.val) (2 ^ (g.val * 2 + scope.val)) = true ↔
    Witness (candidate id.val) (required id.val) (member id.val) (branch id.val) g scope 0 3 := by decide
set_option maxRecDepth 4096 in
theorem finite_coverage : ∀ id : Fin 512, ∀ g : Fin 2,
    bit (coverageMask id.val) (2 ^ g.val) = true ↔
    Covered (candidate id.val) (required id.val) (member id.val) (branch id.val) g 0 3 := by decide
set_option maxRecDepth 4096 in
theorem finite_missing : ∀ id : Fin 512, ∀ g : Fin 2,
    bit (missingMask id.val) (2 ^ g.val) = true ↔
    Missing (candidate id.val) (required id.val) (member id.val) (branch id.val) g 0 3 := by decide
set_option maxRecDepth 4096 in
theorem finite_native_answer : ∀ id : Fin 512, (grade id.val)[4]? = some 1 ↔
    NativeAnswer (candidate id.val) (required id.val) (member id.val) (branch id.val) 0 3 := by decide
theorem finite_answer (id : Fin 512) : (grade id.val)[4]? = some 1 ↔
    Answer (candidate id.val) (required id.val) (member id.val) (branch id.val) 0 3 :=
  (finite_native_answer id).trans no_missing_iff_answer
def corpus := (List.range 512).map grade
def checkConformance (args : List String) : IO Unit := do
  unless args.length == 2 do throw (IO.userError "expected current Quint output and frozen corpus paths")
  let expected := Lean.toJson corpus
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"invalid corpus {path}: {message}")
    unless parsed == expected do throw (IO.userError s!"scoped composition conformance differs: {path}")
  IO.println "SCOPED-COMPOSITION-CONFORMANCE-LEAN-OK cases=512"
end Ascent.ScopedComposition
