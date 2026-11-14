-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ScopedReachabilityMask
import ScopedQuerySpec
namespace Ascent.ScopedQuery
variable {Vertex Scope Group : Type}
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
