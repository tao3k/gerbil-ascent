-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
import Std
import ScopedComposition
import UnsanitizedPaths
namespace Ascent.ScopedReachabilityMask
variable {Scope Vertex : Type}
def Witness (reach : Vertex → Vertex → Prop) (blocked : Scope → Vertex → Prop)
    (scope : Scope) (s z t : Vertex) := blocked scope z ∧ reach s z ∧ reach z t
def Admitted (reach : Vertex → Vertex → Prop) (blocked : Scope → Vertex → Prop)
    (scope : Scope) (s t : Vertex) := reach s t ∧ ¬ ∃ z, Witness reach blocked scope s z t

theorem blocked_antitone (grow : ∀ scope z, before scope z → after scope z)
    (h : Admitted reach after scope s t) : Admitted reach before scope s t := by
  refine ⟨h.1,?_⟩
  rintro ⟨z,hz,hs,ht⟩
  exact h.2 ⟨z,grow scope z hz,hs,ht⟩
theorem mask_local (same : ∀ z, before scope z ↔ after scope z) :
    Admitted reach before scope s t ↔ Admitted reach after scope s t := by
  constructor
  · rintro ⟨hr,hn⟩
    refine ⟨hr,?_⟩
    rintro ⟨z,hz,hs,ht⟩
    exact hn ⟨z,(same z).mpr hz,hs,ht⟩
  · rintro ⟨hr,hn⟩
    refine ⟨hr,?_⟩
    rintro ⟨z,hz,hs,ht⟩
    exact hn ⟨z,(same z).mp hz,hs,ht⟩

-- Composition consumes the actual admitted branch predicate, not an unrelated
-- formal answer relation. Only masks of required member scopes affect it.
theorem composed_local (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (reach : Vertex → Vertex → Prop)
    (before after : Scope → Vertex → Prop) (s t : Vertex)
    (same : ∀ g scope, required g → member g scope → ∀ z, before scope z ↔ after scope z) :
    ScopedComposition.Answer candidate required member (Admitted reach before) s t ↔
    ScopedComposition.Answer candidate required member (Admitted reach after) s t := by
  constructor
  · rintro ⟨selected,supported⟩
    refine ⟨selected,fun g hg => ?_⟩
    rcases supported g hg with ⟨scope,hm,hb⟩
    exact ⟨scope,hm,(mask_local (same g scope hg hm)).mp hb⟩
  · rintro ⟨selected,supported⟩
    refine ⟨selected,fun g hg => ?_⟩
    rcases supported g hg with ⟨scope,hm,hb⟩
    exact ⟨scope,hm,(mask_local (same g scope hg hm)).mpr hb⟩

def bit (id n : Nat) : Bool := (id / 2^n) % 2 == 1
def edge (id x y : Nat) : Bool := y == (x+1)%3 && bit id x
def reach (id x y : Nat) : Bool := x == y || edge id x y ||
    (List.range 3).any (fun z => edge id x z && edge id z y)
def banned (id scope z : Nat) := bit id (3+scope*3+z)
def witness (id scope z t : Nat) := banned id scope z && reach id 0 z && reach id z t
def branch (id scope t : Nat) := reach id 0 t && !(List.range 3).any (fun z => witness id scope z t)
def mask (n : Nat) (p : Nat → Bool) := (List.range n).foldl (fun m slot => m + if p slot then 2^slot else 0) 0
def grade (id : Nat) : List Nat := [id,
    mask 9 (fun slot => reach id (slot/3) (slot%3)),
    mask 18 (fun slot => witness id (slot/9) ((slot%9)/3) (slot%3)),
    mask 6 (fun slot => branch id (slot/3) (slot%3)),
    mask 3 (fun t => branch id 0 t && branch id 1 t)]

def FinReach (id : Nat) (s t : Fin 3) : Prop := reach id s.val t.val = true
def FinBlocked (id : Nat) (scope : Fin 2) (z : Fin 3) : Prop := banned id scope.val z.val = true
instance (id : Nat) (s t : Fin 3) : Decidable (FinReach id s t) := by unfold FinReach; infer_instance
instance (id : Nat) (scope : Fin 2) (z : Fin 3) : Decidable (FinBlocked id scope z) := by unfold FinBlocked; infer_instance
instance (id : Nat) (scope : Fin 2) (s z t : Fin 3) : Decidable (Witness (FinReach id) (FinBlocked id) scope s z t) := by unfold Witness; infer_instance
instance (id : Nat) (scope : Fin 2) (s t : Fin 3) : Decidable (Admitted (FinReach id) (FinBlocked id) scope s t) := by unfold Admitted; infer_instance
set_option maxRecDepth 4096 in
theorem finite_branch : ∀ id : Fin 512, ∀ scope : Fin 2, ∀ t : Fin 3,
    branch id.val scope.val t.val = true ↔ Admitted (FinReach id.val) (FinBlocked id.val) scope 0 t := by decide
-- The eight edge graphs include the directed cycle. Two edges suffice for
-- every distinct reachable pair on these three vertices; closure also has zero hops.
theorem finite_reflexive : ∀ id : Fin 8, ∀ s : Fin 3, reach id.val s.val s.val = true := by decide
theorem finite_step_closed : ∀ id : Fin 8, ∀ s x t : Fin 3,
    reach id.val s.val x.val = true → edge id.val x.val t.val = true → reach id.val s.val t.val = true := by decide

def FinEdge (id : Nat) (s t : Fin 3) : Prop := edge id s.val t.val = true
instance (id : Nat) (s t : Fin 3) : Decidable (FinEdge id s t) := by unfold FinEdge; infer_instance
theorem finite_generated : ∀ id : Fin 8, ∀ s t : Fin 3,
    FinReach id.val s t ↔ s = t ∨ FinEdge id.val s t ∨ ∃ z, FinEdge id.val s z ∧ FinEdge id.val z t := by decide
-- Connect the finite closure table to walks of arbitrary length, including cycles.
theorem finite_walk_iff (id : Fin 8) (s t : Fin 3) :
    FinReach id.val s t ↔ UnsanitizedPaths.Walk (FinEdge id.val) s t := by
  constructor
  · intro hr
    rcases (finite_generated id s t).mp hr with equal | link | ⟨z,left,right⟩
    · subst t; exact .refl s
    · exact .step (.refl s) link
    · exact .step (.step (.refl s) left) right
  · intro path
    induction path with
    | refl => exact finite_reflexive id _
    | step path link ih => exact finite_step_closed id _ _ _ ih link

theorem finite_group (id : Fin 512) (t : Fin 3) :
    (branch id.val 0 t.val && branch id.val 1 t.val) = true ↔
    Admitted (FinReach id.val) (FinBlocked id.val) (0 : Fin 2) 0 t ∧
    Admitted (FinReach id.val) (FinBlocked id.val) (1 : Fin 2) 0 t := by
  rw [Bool.and_eq_true]
  exact and_congr (finite_branch id (0 : Fin 2) t) (finite_branch id (1 : Fin 2) t)

-- A clean alternative survives while the pair is structurally excluded.
def diamond (x y : Fin 4) : Prop := (x = 0 ∧ y = 1) ∨ (x = 1 ∧ y = 3) ∨ (x = 0 ∧ y = 2) ∨ (x = 2 ∧ y = 3)
def allowed (x : Fin 4) : Prop := x ≠ 1
theorem clean_alternative : UnsanitizedPaths.CleanPath diamond allowed 0 3 := by
  have h0 : allowed 0 := by unfold allowed; decide
  have h2 : allowed 2 := by unfold allowed; decide
  have h3 : allowed 3 := by unfold allowed; decide
  have h02 : diamond 0 2 := by unfold diamond; decide
  have h23 : diamond 2 3 := by unfold diamond; decide
  exact .step (.step (.refl h0) h02 h2) h23 h3
theorem structural_reject : ¬ Admitted (UnsanitizedPaths.Walk diamond) (fun (_ : Unit) z => z = 1) () 0 3 := by
  intro h
  have h01 : diamond 0 1 := by unfold diamond; decide
  have h13 : diamond 1 3 := by unfold diamond; decide
  exact h.2 ⟨1,rfl,.step (.refl 0) h01,.step (.refl 1) h13⟩

def corpus := (List.range 512).map grade
def checkConformance (args : List String) : IO Unit := do
  unless args.length == 2 do throw (IO.userError "expected current Quint output and frozen corpus paths")
  let expected := Lean.toJson corpus
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"invalid corpus {path}: {message}")
    unless parsed == expected do throw (IO.userError s!"scoped reachability mask conformance differs: {path}")
  IO.println "SCOPED-REACHABILITY-MASK-CONFORMANCE-LEAN-OK cases=512"
end Ascent.ScopedReachabilityMask
