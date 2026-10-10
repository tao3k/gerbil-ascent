-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ScopedReachabilityMask
namespace Ascent.ScopedQuery
variable {Vertex Scope Group : Type}
def Exact (edge : Vertex → Vertex → Prop) : Nat → Vertex → Vertex → Prop
  | 0, s, t => s = t
  | n+1, s, t => ∃ x, Exact edge n s x ∧ edge x t
def Bounded (edge : Vertex → Vertex → Prop) (k : Nat) (s t : Vertex) :=
  ∃ n, n ≤ k ∧ Exact edge n s t
def Shortest (edge : Vertex → Vertex → Prop) (n : Nat) (s t : Vertex) :=
  Exact edge n s t ∧ ∀ m, m < n → ¬ Exact edge m s t
def Predecessor (edge : Vertex → Vertex → Prop) (n : Nat) (s x t : Vertex) :=
  Shortest edge (n+1) s t ∧ Exact edge n s x ∧ edge x t

theorem predecessor_decreases (h : Predecessor edge n s x t) : Shortest edge n s x := by
  refine ⟨h.2.1, fun m hm path => ?_⟩
  exact h.1.2 (m+1) (by omega) ⟨x,path,h.2.2⟩
theorem shortest_has_predecessor (h : Shortest edge (n+1) s t) :
    ∃ x, Predecessor edge n s x t := by
  rcases h.1 with ⟨x,path,link⟩
  exact ⟨x,h,path,link⟩
theorem bounded_monotone (grow : k ≤ l) (h : Bounded edge k s t) : Bounded edge l s t := by
  rcases h with ⟨n,hn,path⟩
  exact ⟨n,Nat.le_trans hn grow,path⟩
theorem bounded_has_shortest (h : Bounded edge k s t) : ∃ n, n ≤ k ∧ Shortest edge n s t := by
  classical
  induction k with
  | zero =>
    rcases h with ⟨n,hn,path⟩
    have zero : n = 0 := by omega
    subst n
    exact ⟨0,by omega,path,fun m hm => False.elim (by omega)⟩
  | succ k ih =>
    by_cases lower : Bounded edge k s t
    · rcases ih lower with ⟨n,hn,path⟩
      exact ⟨n,by omega,path⟩
    · rcases h with ⟨n,hn,path⟩
      have last : n = k+1 := by
        apply Classical.byContradiction
        intro neq
        exact lower ⟨n,by omega,path⟩
      exact ⟨n,hn,path,fun m hm hp => lower ⟨m,by omega,hp⟩⟩
-- Total-length exclusion: every segment and its sum belong to one request.
def Via (edge : Vertex → Vertex → Prop) (k : Nat) (s z t : Vertex) :=
  ∃ p q, p + q ≤ k ∧ Exact edge p s z ∧ Exact edge q z t
theorem via_iff_shortest : Via edge k s z t ↔
    ∃ p q, p + q ≤ k ∧ Shortest edge p s z ∧ Shortest edge q z t := by
  constructor
  · rintro ⟨p,q,hk,hp,hq⟩
    rcases bounded_has_shortest (show Bounded edge p s z from ⟨p,by omega,hp⟩) with ⟨a,ha,pa⟩
    rcases bounded_has_shortest (show Bounded edge q z t from ⟨q,by omega,hq⟩) with ⟨b,hb,pb⟩
    exact ⟨a,b,by omega,pa,pb⟩
  · rintro ⟨p,q,hk,hp,hq⟩
    exact ⟨p,q,hk,hp.1,hq.1⟩
theorem exact_append (hp : Exact edge p s z) (hq : Exact edge q z t) :
    Exact edge (p+q) s t := by
  induction q generalizing t with
  | zero => cases hq; simpa using hp
  | succ q ih =>
    rcases hq with ⟨x,path,link⟩
    exact ⟨x,ih path,link⟩
theorem via_is_bounded (h : Via edge k s z t) : Bounded edge k s t := by
  rcases h with ⟨p,q,hk,hp,hq⟩
  exact ⟨p+q,hk,exact_append hp hq⟩
theorem via_implies_independent_sides (h : Via edge k s z t) :
    Bounded edge k s z ∧ Bounded edge k z t := by
  rcases h with ⟨p,q,hk,hp,hq⟩
  exact ⟨⟨p,by omega,hp⟩,⟨q,by omega,hq⟩⟩
def Admitted (edge : Vertex → Vertex → Prop) (blocked : Scope → Vertex → Prop)
    (k : Nat) (scope : Scope) (s t : Vertex) :=
  Bounded edge k s t ∧ ¬ ∃ z, blocked scope z ∧ Via edge k s z t
theorem mask_antitone (grow : ∀ z, blocked scope z → stronger scope z)
    (h : Admitted edge stronger k scope s t) : Admitted edge blocked k scope s t := by
  exact ⟨h.1,fun ⟨z,hb,hv⟩ => h.2 ⟨z,grow z hb,hv⟩⟩
theorem mask_local (same : ∀ z, blocked scope z ↔ other scope z) :
    Admitted edge blocked k scope s t ↔ Admitted edge other k scope s t := by
  constructor
  · exact mask_antitone (fun z hb => (same z).mpr hb)
  · exact mask_antitone (fun z hb => (same z).mp hb)
theorem zero_via : Via edge 0 s z t ↔ s = z ∧ z = t := by
  constructor
  · rintro ⟨p,q,hk,hp,hq⟩
    have hp0 : p = 0 := by omega
    have hq0 : q = 0 := by omega
    subst p; subst q; exact ⟨hp,hq⟩
  · rintro ⟨hp,hq⟩; exact ⟨0,0,by omega,hp,hq⟩

theorem exact_is_walk (h : Exact edge n s t) : UnsanitizedPaths.Walk edge s t := by
  induction n generalizing t with
  | zero => cases h; exact .refl s
  | succ n ih =>
    rcases h with ⟨x,path,link⟩
    exact .step (ih path) link
-- Enlarging K can both add coverage and add banned prefix/suffix witnesses.
-- Only fixed-reach mask antitonicity is inherited from ScopedReachabilityMask.
def Trace (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (g : Group) (scope : Scope) (s t : Vertex) (n : Nat) :=
  ScopedComposition.Answer candidate required member branch s t ∧
  ScopedComposition.Witness candidate required member branch g scope s t ∧ Shortest edge n s t
theorem trace_is_answer (h : Trace candidate required member branch edge g scope s t n) :
    ScopedComposition.Answer candidate required member branch s t := h.1
theorem trace_covers_required (h : ScopedComposition.Answer candidate required member branch s t)
    (hg : required g) (paths : ∀ scope, branch scope s t → ∃ n, Shortest edge n s t) :
    ∃ scope n, Trace candidate required member branch edge g scope s t n := by
  rcases h.2 g hg with ⟨scope,hm,hb⟩
  rcases paths scope hb with ⟨n,hn⟩
  exact ⟨scope,n,h,⟨h.1,hg,hm,hb⟩,hn⟩
def SelectedBranch (start target blocked : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (k : Nat) (scope : Scope) (s t : Vertex) :=
  start scope s ∧ target scope t ∧ Admitted edge blocked k scope s t
theorem query_trace_complete
    (h : ScopedComposition.NativeAnswer candidate required member (SelectedBranch start target blocked edge k) s t)
    (hg : required g) : ∃ scope n, n ≤ k ∧
      Trace candidate required member (SelectedBranch start target blocked edge k) edge g scope s t n := by
  have answer := ScopedComposition.no_missing_iff_answer.mp h
  rcases answer.2 g hg with ⟨scope,hm,hb⟩
  rcases bounded_has_shortest hb.2.2.1 with ⟨n,hn,path⟩
  exact ⟨scope,n,hn,answer,⟨answer.1,hg,hm,hb⟩,path⟩

def edge (id s t : Nat) : Bool := ScopedReachabilityMask.edge (id % 512) s t
def exact (id s t n : Nat) : Bool := if n = 0 then s == t else
  if n = 1 then edge id s t else (List.range 3).any (fun x => edge id s x && edge id x t)
def limit (id : Nat) := id / 512
def minimum (id s t n : Nat) := exact id s t n && (List.range n).all (fun m => !exact id s t m)
def first (id s t n : Nat) := n ≤ limit id && minimum id s t n
def reachAt (id cap s t : Nat) := (List.range (cap + 1)).any (fun n => exact id s t n)
def reach (id s t : Nat) := reachAt id (limit id) s t
def viaBool (id k s z t : Nat) := (List.range (k+1)).any
  (fun p => (List.range (k+1)).any (fun q => p+q ≤ k && exact id s z p && exact id z t q))
def witness (id scope z t : Nat) := ScopedReachabilityMask.banned (id % 512) scope z && viaBool id (limit id) 0 z t
def branch (id scope t : Nat) := reach id 0 t && !(List.range 3).any (fun z => witness id scope z t)
def answer (id t : Nat) := branch id 0 t && branch id 1 t
def predecessor (id s x t : Nat) := (List.range (limit id)).any
  (fun n => first id s t (n+1) && exact id s x n && edge id x t)
def trace (id scope t n : Nat) := answer id t && branch id scope t && first id 0 t n
def mask := ScopedReachabilityMask.mask
def grade (id : Nat) : List Nat := [id,limit id,
  mask 9 (fun p => reach id (p/3) (p%3)),
  mask 27 (fun p => p%3 ≤ limit id && exact id (p/9) ((p%9)/3) (p%3)),
  mask 27 (fun p => first id (p/9) ((p%9)/3) (p%3)),
  mask 27 (fun p => predecessor id (p/9) ((p%9)/3) (p%3)),
  mask 18 (fun p => witness id (p/9) ((p%9)/3) (p%3)),
  mask 6 (fun p => branch id (p/3) (p%3)),
  mask 3 (answer id),mask 18 (fun p => trace id (p/9) ((p%9)/3) (p%3))]

def FinEdge (id : Nat) (s t : Fin 3) := edge id s.val t.val = true
instance (id : Nat) (s t : Fin 3) : Decidable (FinEdge id s t) := by unfold FinEdge; infer_instance
instance (id n : Nat) (s t : Fin 3) : Decidable (Exact (FinEdge id) n s t) := by
  induction n generalizing s t with
  | zero => unfold Exact; infer_instance
  | succ n ih => unfold Exact; exact inferInstance
instance (id n : Nat) (s t : Fin 3) : Decidable (Shortest (FinEdge id) n s t) :=
  decidable_of_iff (Exact (FinEdge id) n s t ∧ ∀ m : Fin n, ¬ Exact (FinEdge id) m.val s t)
    (by
      constructor
      · rintro ⟨path,none⟩
        exact ⟨path,fun m hm => none ⟨m,hm⟩⟩
      · rintro ⟨path,none⟩
        exact ⟨path,fun m => none m.val m.isLt⟩)
instance (id k : Nat) (s t : Fin 3) : Decidable (Bounded (FinEdge id) k s t) :=
  decidable_of_iff (∃ n : Fin (k+1), Exact (FinEdge id) n.val s t)
    (by
      constructor
      · rintro ⟨n,path⟩; exact ⟨n.val,by omega,path⟩
      · rintro ⟨n,hn,path⟩; exact ⟨⟨n,by omega⟩,path⟩)
instance (id k : Nat) (s z t : Fin 3) : Decidable (Via (FinEdge id) k s z t) :=
  decidable_of_iff (∃ p q : Fin (k+1), p.val + q.val ≤ k ∧
      Exact (FinEdge id) p.val s z ∧ Exact (FinEdge id) q.val z t)
    (by
      constructor
      · rintro ⟨p,q,hk,hp,hq⟩; exact ⟨p.val,q.val,hk,hp,hq⟩
      · rintro ⟨p,q,hk,hp,hq⟩; exact ⟨⟨p,by omega⟩,⟨q,by omega⟩,hk,hp,hq⟩)
set_option maxRecDepth 4096 in
theorem finite_via : ∀ id : Fin 8, ∀ k : Fin 3, ∀ s z t : Fin 3,
    viaBool id.val k.val s.val z.val t.val = true ↔ Via (FinEdge id.val) k.val s z t := by decide

set_option maxRecDepth 4096 in
theorem finite_exact : ∀ id : Fin 8, ∀ n : Fin 3, ∀ s t : Fin 3,
    exact id.val s.val t.val n.val = true ↔ Exact (FinEdge id.val) n.val s t := by decide
set_option maxRecDepth 4096 in
theorem finite_shortest : ∀ id : Fin 8, ∀ n : Fin 3, ∀ s t : Fin 3,
    minimum id.val s.val t.val n.val = true ↔ Shortest (FinEdge id.val) n.val s t := by decide
set_option maxRecDepth 4096 in
theorem finite_bounded : ∀ id : Fin 8, ∀ k : Fin 3, ∀ s t : Fin 3,
    reachAt id.val k.val s.val t.val = true ↔ Bounded (FinEdge id.val) k.val s t := by decide
def corpus := (List.range 1536).map grade
def checkConformance (args : List String) : IO Unit := do
  unless args.length == 2 do throw (IO.userError "expected current Quint output and frozen corpus paths")
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok json => pure json
      | .error message => throw (IO.userError s!"invalid corpus {path}: {message}")
    unless parsed == Lean.toJson corpus do throw (IO.userError s!"scoped query conformance differs: {path}")
  IO.println "SCOPED-QUERY-CONFORMANCE-LEAN-OK cases=1536"
end Ascent.ScopedQuery
