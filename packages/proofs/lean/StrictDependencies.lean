-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import RuleGraphClosure

/-! Weighted read-edge extraction for admitted lowered rules. Native vector
shape, relation-kind extraction and SCC ownership remain representation premises.
Strict cycles have no natural-number stratum assignment; positive cycles may. -/
namespace Ascent.StrictDependencies
open RuleGraphClosure
inductive RelationKind where
  | relation | lattice
  deriving DecidableEq

variable {Key : Type} [DecidableEq Key]

def strict (kinds : Key → RelationKind) (kind : ClauseKind) (source target : Key) : Bool :=
  kind == .negation || kind == .aggregate ||
    (kind == .atom && kinds source == .lattice && kinds target == .relation)

structure Edge (Key : Type) where
  source : Key
  target : Key
  kind : ClauseKind
  strict : Bool
  deriving DecidableEq

def edge (kinds : Key → RelationKind) (kind : ClauseKind) (source target : Key) : Edge Key :=
  ⟨source,target,kind,strict kinds kind source target⟩

def extract (kinds : Key → RelationKind) (plans : List (Rule Key)) : List (Edge Key) :=
  plans.flatMap fun rule => rule.heads.flatMap fun target =>
    rule.body.flatMap fun clause => clause.source.toList.flatMap fun source =>
      if clause.kind.reads then [edge kinds clause.kind source target] else []

omit [DecidableEq Key] in
theorem extraction_exact (kinds : Key → RelationKind) (plans : List (Rule Key)) (found : Edge Key) :
    found ∈ extract kinds plans ↔ ∃ rule ∈ plans, ∃ target ∈ rule.heads,
      ∃ clause ∈ rule.body, ∃ source, clause.source = some source ∧
        clause.kind.reads = true ∧ found = edge kinds clause.kind source target := by
  simp [extract,List.mem_flatMap]

omit [DecidableEq Key] in
theorem strict_exact (kinds : Key → RelationKind) (kind : ClauseKind) (source target : Key) :
    strict kinds kind source target = true ↔ kind = .negation ∨ kind = .aggregate ∨
      (kind = .atom ∧ kinds source = .lattice ∧ kinds target = .relation) := by
  cases kind <;> simp [strict]

-- The native global preflight can return true for an empty-head rule. Only
-- the false case is used to skip graph construction, so no edge is lost.
def needsStrict (kinds : Key → RelationKind) (plans : List (Rule Key)) : Bool :=
  plans.any (fun rule => rule.body.any (fun clause => clause.kind == .negation || clause.kind == .aggregate)) ||
  plans.any (fun rule => rule.heads.any (fun head => kinds head == .relation) &&
    rule.body.any (fun clause => clause.kind == .atom &&
      clause.source.any (fun source => kinds source == .lattice)))

omit [DecidableEq Key] in
theorem strict_preflight (kinds : Key → RelationKind) (plans : List (Rule Key))
    (found : Edge Key) (member : found ∈ extract kinds plans) (needed : found.strict = true) :
    needsStrict kinds plans = true := by
  obtain ⟨rule,hr,target,ht,clause,hc,source,hs,reads,rfl⟩ :=
    (extraction_exact kinds plans found).mp member
  have classification := (strict_exact kinds clause.kind source target).mp needed
  simp only [needsStrict,Bool.or_eq_true,List.any_eq_true,Bool.and_eq_true,beq_iff_eq]
  rcases classification with negative | aggregate | ⟨atom,sourceKind,targetKind⟩
  · exact Or.inl ⟨rule,hr,clause,hc,Or.inl negative⟩
  · exact Or.inl ⟨rule,hr,clause,hc,Or.inr aggregate⟩
  · exact Or.inr ⟨rule,hr,⟨target,ht,targetKind⟩,clause,hc,atom,by simp [hs,sourceKind]⟩

omit [DecidableEq Key] in
theorem skipped_edges_nonstrict (kinds : Key → RelationKind) (plans : List (Rule Key))
    (skip : needsStrict kinds plans = false) (found : Edge Key) (member : found ∈ extract kinds plans) :
    found.strict = false := by
  cases flag : found.strict
  · rfl
  · have contradiction := strict_preflight kinds plans found member flag
    simp [skip] at contradiction

def weight (found : Edge Key) : Nat := if found.strict then 1 else 0
def Valid (edges : List (Edge Key)) (levels : Key → Nat) : Prop :=
  ∀ found ∈ edges, levels found.source + weight found ≤ levels found.target

omit [DecidableEq Key] in
theorem skipped_zero_valid (kinds : Key → RelationKind) (plans : List (Rule Key))
    (skip : needsStrict kinds plans = false) : Valid (extract kinds plans) (fun _ => 0) := by
  intro found member
  have nonstrict := skipped_edges_nonstrict kinds plans skip found member
  simp [weight,nonstrict]

-- Paths retain the actual compiled edge's weight; no finite graph cutoff.
inductive Path (edges : List (Edge Key)) : Key → Key → Nat → Prop where
  | nil (key) : Path edges key key 0
  | next {start current : Key} {cost : Nat} (prior : Path edges start current cost)
      (found : Edge Key) (member : found ∈ edges) (source : found.source = current) :
      Path edges start found.target (cost + weight found)

omit [DecidableEq Key] in
theorem path_bound (edges : List (Edge Key)) (levels : Key → Nat) (valid : Valid edges levels)
    (source target : Key) (cost : Nat) (path : Path edges source target cost) :
    levels source + cost ≤ levels target := by
  induction path with
  | nil => omega
  | next prior found member source ih =>
      have step := valid found member
      rw [source] at step
      omega

omit [DecidableEq Key] in
theorem strict_cycle_impossible (edges : List (Edge Key)) (found : Edge Key)
    (member : found ∈ edges) (isStrict : found.strict = true) (cost : Nat)
    (back : Path edges found.target found.source cost) : ¬ ∃ levels, Valid edges levels := by
  rintro ⟨levels,valid⟩
  have forward := valid found member
  have backward := path_bound edges levels valid _ _ cost back
  simp [weight,isStrict] at forward
  omega

omit [DecidableEq Key] in
theorem projection_later (kinds : Key → RelationKind) (plans : List (Rule Key))
    (levels : Key → Nat) (valid : Valid (extract kinds plans) levels)
    (source target : Key) (member : edge kinds .atom source target ∈ extract kinds plans)
    (fromLattice : kinds source = .lattice) (toRelation : kinds target = .relation) :
    levels source < levels target := by
  have constraint := valid _ member
  simp [weight,edge,strict,fromLattice,toRelation] at constraint
  omega

-- Max propagation preserves the lower-bound relation to every valid labeling.
-- Together with validated condensation order this proves minimality, without
-- assuming that arbitrary native Tarjan output has already been extracted.
def relax (levels : Key → Nat) (found : Edge Key) : Key → Nat :=
  fun key => if key = found.target then max (levels key) (levels found.source + weight found) else levels key

theorem relax_below_valid (edges : List (Edge Key)) (bound current : Key → Nat)
    (valid : Valid edges bound) (below : ∀ key, current key ≤ bound key)
    (found : Edge Key) (member : found ∈ edges) : ∀ key, relax current found key ≤ bound key := by
  intro key
  by_cases same : key = found.target
  · subst key
    have h := valid found member
    have hs := below found.source
    have ht := below found.target
    simp only [relax,ite_true]
    omega
  · simpa [relax,same] using below key

def propagate (edges : List (Edge Key)) : (Key → Nat) → List (Edge Key) → Key → Nat
  | levels, [] => levels
  | levels, found :: rest => propagate edges (relax levels found) rest

theorem propagated_below_valid (edges replay : List (Edge Key)) (bound : Key → Nat)
    (valid : Valid edges bound) (included : ∀ found ∈ replay, found ∈ edges)
    (current : Key → Nat) (below : ∀ key, current key ≤ bound key) :
    ∀ key, propagate edges current replay key ≤ bound key := by
  induction replay generalizing current with
  | nil => exact below
  | cons found rest ih =>
    exact ih (fun e h => included e (by simp [h])) _
      (relax_below_valid edges bound current valid below found (included found (by simp)))

theorem completed_propagation_minimal (edges replay : List (Edge Key))
    (included : ∀ found ∈ replay, found ∈ edges)
    (complete : Valid edges (propagate edges (fun _ => 0) replay)) :
    Valid edges (propagate edges (fun _ => 0) replay) ∧
      ∀ bound, Valid edges bound → ∀ key, propagate edges (fun _ => 0) replay key ≤ bound key := by
  refine ⟨complete, ?_⟩
  intro bound valid
  exact propagated_below_valid edges replay bound valid included _ (fun _ => Nat.zero_le _)


-- Every valid labeling is constant on a strongly connected component, even
-- when its members have different temporary levels during propagation.
omit [DecidableEq Key] in
theorem mutual_paths_equal (edges : List (Edge Key)) (bound : Key → Nat)
    (valid : Valid edges bound) (left right : Key) (forwardCost backwardCost : Nat)
    (forward : Path edges left right forwardCost)
    (backward : Path edges right left backwardCost) : bound left = bound right := by
  have hf := path_bound edges bound valid left right forwardCost forward
  have hb := path_bound edges bound valid right left backwardCost backward
  omega

def componentMax (members : List Key) (current : Key → Nat) : Nat :=
  (members.map current).foldr max 0

def normalize (members : List Key) (current : Key → Nat) : Key → Nat :=
  fun key => if key ∈ members then componentMax members current else current key

omit [DecidableEq Key] in
theorem component_max_below (members : List Key) (current : Key → Nat) (ceiling : Nat)
    (below : ∀ key ∈ members, current key ≤ ceiling) : componentMax members current ≤ ceiling := by
  induction members with
  | nil => simp [componentMax]
  | cons key rest ih =>
    have first := below key (by simp)
    have remaining := ih (fun key h => below key (by simp [h]))
    simpa [componentMax] using Nat.max_le.mpr ⟨first,remaining⟩

theorem normalization_below_valid (edges : List (Edge Key)) (members : List Key)
    (bound current : Key → Nat) (valid : Valid edges bound)
    (below : ∀ key, current key ≤ bound key)
    (connected : ∀ left ∈ members, ∀ right ∈ members,
      ∃ fc bc, Path edges left right fc ∧ Path edges right left bc) :
    ∀ key, normalize members current key ≤ bound key := by
  intro key
  by_cases member : key ∈ members
  · simp only [normalize,ite_eq_left member]
    apply component_max_below
    intro other ho
    obtain ⟨fc,bc,hf,hb⟩ := connected other ho key member
    have same := mutual_paths_equal edges bound valid other key fc bc hf hb
    simpa [same] using below other
  · simpa [normalize,member] using below key

end Ascent.StrictDependencies
