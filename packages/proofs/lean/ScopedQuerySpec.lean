-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ScopedCompositionSpec
import UnsanitizedPaths

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
    (h : ScopedComposition.ScopedAnswer candidate required member (SelectedBranch start target blocked edge k) s t)
    (hg : required g) : ∃ scope n, n ≤ k ∧
      Trace candidate required member (SelectedBranch start target blocked edge k) edge g scope s t n := by
  have answer := ScopedComposition.no_missing_iff_answer.mp h
  rcases answer.2 g hg with ⟨scope,hm,hb⟩
  rcases bounded_has_shortest hb.2.2.1 with ⟨n,hn,path⟩
  exact ⟨scope,n,hn,answer,⟨answer.1,hg,hm,hb⟩,path⟩

/-- The generated shortest-distance columns are naturals. This is the
arithmetic side condition for expressing the native bound through the
existing closed integer addition and strict comparison operators. -/
theorem hop_guard_closed_equiv (prefixHops suffixHops limit : Nat) :
    prefixHops + suffixHops ≤ limit ↔
      (prefixHops : Int) + (suffixHops : Int) < (limit : Int) + 1 := by
  omega

/-- In a complete directed graph with self edges, each positive layer
contains every ordered pair. Endpoint selection does not occur in Exact. -/
theorem complete_graph_positive_layer
    {edge : Vertex → Vertex → Prop} (complete : ∀ s t, edge s t)
    (s t : Vertex) (n : Nat) : Exact edge (n + 1) s t := by
  induction n generalizing t with
  | zero => exact ⟨s, rfl, complete s t⟩
  | succ n ih => exact ⟨s, ih s, complete s t⟩

/-- A receipt with one row for each exact-hop tuple contains at least
the dense output below, regardless of the algorithm that produced it.
The vertex parameters refer to the admitted domain. -/
theorem complete_graph_hop_output_lower_bound {vertices hops : Nat}
    {edge : Fin vertices → Fin vertices → Prop}
    (complete : ∀ s t, edge s t)
    (rows : List (Nat × Fin vertices × Fin vertices))
    (covers : ∀ n s t, n ≤ hops → Exact edge n s t → (n, s, t) ∈ rows) :
    vertices + hops * (vertices * vertices) ≤ rows.length := by
  let domain := List.finRange vertices
  let layer := fun (i : Fin hops) =>
    domain.flatMap fun s => domain.map fun t => (i.val + 1, s, t)
  let dense := domain.map (fun s => (0, s, s)) ++ (List.finRange hops).flatMap layer
  have domainUnique : domain.Nodup := List.nodup_finRange vertices
  have layerUnique (i : Fin hops) : (layer i).Nodup := by
    apply List.pairwise_flatMap.mpr
    constructor
    · intro s _
      exact domainUnique.map _ (fun _ _ different equal => different (congrArg (fun row => row.2.2) equal))
    · exact domainUnique.imp (fun {s t} different x hx y hy equal => by
        obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
        obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
        exact different (congrArg (fun row => row.2.1) equal))
  have positiveUnique : ((List.finRange hops).flatMap layer).Nodup := by
    apply List.pairwise_flatMap.mpr
    constructor
    · intro i _
      exact layerUnique i
    · exact (List.nodup_finRange hops).imp (fun {i j} different x hx y hy equal => by
        obtain ⟨_, _, hx⟩ := List.mem_flatMap.mp hx
        obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
        obtain ⟨_, _, hy⟩ := List.mem_flatMap.mp hy
        obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
        apply different
        apply Fin.ext
        have levels := congrArg Prod.fst equal
        omega)
  have denseUnique : dense.Nodup := by
    apply List.pairwise_append.mpr
    refine ⟨domainUnique.map _ (fun _ _ different equal =>
      different (congrArg (fun row => row.2.1) equal)), positiveUnique, ?_⟩
    intro x hx y hy equal
    obtain ⟨_, _, rfl⟩ := List.mem_map.mp hx
    obtain ⟨_, _, hy⟩ := List.mem_flatMap.mp hy
    obtain ⟨_, _, hy⟩ := List.mem_flatMap.mp hy
    obtain ⟨_, _, rfl⟩ := List.mem_map.mp hy
    exact Nat.succ_ne_zero _ (congrArg Prod.fst equal).symm
  have layerLength (i : Fin hops) : (layer i).length = vertices * vertices := by
    simp [layer, domain, List.length_flatMap, List.map_const', List.sum_replicate_nat]
  have denseLength : dense.length = vertices + hops * (vertices * vertices) := by
    simp [dense, domain, List.length_flatMap, layerLength, List.map_const', List.sum_replicate_nat]
  rw [← denseLength]
  apply denseUnique.length_le_of_subset
  intro row present
  rcases List.mem_append.mp present with zero | positive
  · obtain ⟨s, _, rfl⟩ := List.mem_map.mp zero
    exact covers 0 s s (Nat.zero_le _) rfl
  · obtain ⟨i, _, present⟩ := List.mem_flatMap.mp positive
    obtain ⟨s, _, present⟩ := List.mem_flatMap.mp present
    obtain ⟨t, _, rfl⟩ := List.mem_map.mp present
    exact covers (i.val + 1) s t i.isLt (complete_graph_positive_layer complete s t i.val)

/-- For one fixed graph, hop limit and pair, a mask edit only matters to
this branch at vertices with a bounded walk through them. -/
theorem selected_branch_mask_frame
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k : Nat} {scope : Scope} {s t : Vertex}
    (same : ∀ z, Via edge k s z t → (before scope z ↔ after scope z)) :
    SelectedBranch start target before edge k scope s t ↔
      SelectedBranch start target after edge k scope s t := by
  constructor
  · rintro ⟨hs, ht, hr, none⟩
    exact ⟨hs, ht, hr, fun ⟨z, blocked, via⟩ => none ⟨z, (same z via).mpr blocked, via⟩⟩
  · rintro ⟨hs, ht, hr, none⟩
    exact ⟨hs, ht, hr, fun ⟨z, blocked, via⟩ => none ⟨z, (same z via).mp blocked, via⟩⟩

/-- Reusing one answer across a mask edit requires agreement only at
bounded witnesses in scopes of required groups. The graph, selection,
candidate pair and group declarations are fixed by the theorem. -/
theorem query_answer_mask_frame
    {candidate : Vertex → Vertex → Prop} {required : Group → Prop}
    {member : Group → Scope → Prop}
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k : Nat} {s t : Vertex}
    (same : ∀ g scope, required g → member g scope →
      ∀ z, Via edge k s z t → (before scope z ↔ after scope z)) :
    ScopedComposition.Answer candidate required member
        (SelectedBranch start target before edge k) s t ↔
      ScopedComposition.Answer candidate required member
        (SelectedBranch start target after edge k) s t := by
  constructor
  · rintro ⟨selected, supports⟩
    refine ⟨selected, fun g needed => ?_⟩
    rcases supports g needed with ⟨scope, belongs, branch⟩
    exact ⟨scope, belongs, (selected_branch_mask_frame (same g scope needed belongs)).mp branch⟩
  · rintro ⟨selected, supports⟩
    refine ⟨selected, fun g needed => ?_⟩
    rcases supports g needed with ⟨scope, belongs, branch⟩
    exact ⟨scope, belongs, (selected_branch_mask_frame (same g scope needed belongs)).mpr branch⟩

/-- The same frame preserves every final trace row, including alternative
group supports and its distance. This statement concerns final answer
traces for this pair. It does not cover arbitrary intermediate branches. -/
theorem query_trace_mask_frame
    {candidate : Vertex → Vertex → Prop} {required : Group → Prop}
    {member : Group → Scope → Prop}
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k n : Nat} {s t : Vertex} {g : Group} {scope : Scope}
    (same : ∀ group branchScope, required group → member group branchScope →
      ∀ z, Via edge k s z t → (before branchScope z ↔ after branchScope z)) :
    Trace candidate required member (SelectedBranch start target before edge k) edge g scope s t n ↔
      Trace candidate required member (SelectedBranch start target after edge k) edge g scope s t n := by
  have keepAnswer :=
    query_answer_mask_frame (candidate := candidate) (start := start) (target := target) same
  have keepBranch (needed : required g) (belongs : member g scope) :
      SelectedBranch start target before edge k scope s t ↔
        SelectedBranch start target after edge k scope s t :=
    selected_branch_mask_frame (same g scope needed belongs)
  constructor
  · rintro ⟨answer, ⟨selected, needed, belongs, branch⟩, shortest⟩
    exact ⟨keepAnswer.mp answer, ⟨selected, needed, belongs, (keepBranch needed belongs).mp branch⟩, shortest⟩
  · rintro ⟨answer, ⟨selected, needed, belongs, branch⟩, shortest⟩
    exact ⟨keepAnswer.mpr answer, ⟨selected, needed, belongs, (keepBranch needed belongs).mpr branch⟩, shortest⟩

/-- A change-list entry can affect the pair only through a required
member scope and two shortest segments within the original total bound. -/
def AffectedByMaskEdit (required : Group → Prop) (member : Group → Scope → Prop)
    (edge : Vertex → Vertex → Prop) (k : Nat) (edits : List (Scope × Vertex))
    (s t : Vertex) : Prop :=
  ∃ g scope z p q, required g ∧ member g scope ∧ (scope, z) ∈ edits ∧
    p + q ≤ k ∧ Shortest edge p s z ∧ Shortest edge q z t

/-- An affected-pair index may overapproximate the joins over the edited
scope/vertex keys. Missing one of these joins can invalidate reuse.
The edit roster must cover every changed mask membership. -/
theorem unchanged_outside_affected_mask_pairs
    {candidate : Vertex → Vertex → Prop} {required : Group → Prop}
    {member : Group → Scope → Prop}
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k : Nat} {s t : Vertex}
    (edits : List (Scope × Vertex))
    (covered : ∀ scope z, (scope, z) ∉ edits → (before scope z ↔ after scope z))
    (unaffected : ¬ AffectedByMaskEdit required member edge k edits s t) :
    (ScopedComposition.Answer candidate required member
        (SelectedBranch start target before edge k) s t ↔
      ScopedComposition.Answer candidate required member
        (SelectedBranch start target after edge k) s t) ∧
    (∀ g scope n,
      Trace candidate required member (SelectedBranch start target before edge k) edge g scope s t n ↔
        Trace candidate required member (SelectedBranch start target after edge k) edge g scope s t n) := by
  have frame (g : Group) (scope : Scope) (needed : required g) (belongs : member g scope)
      (z : Vertex) (via : Via edge k s z t) : before scope z ↔ after scope z := by
    apply covered scope z
    intro changed
    rcases via_iff_shortest.mp via with ⟨p, q, within, firstPath, secondPath⟩
    exact unaffected ⟨g, scope, z, p, q, needed, belongs, changed, within, firstPath, secondPath⟩
  exact ⟨query_answer_mask_frame frame, fun _ _ _ => query_trace_mask_frame frame⟩

/-- Losing a supporting scope deletes a trace row even when other scopes
keep the pair accepted. An answer-only cache cannot detect this change. -/
theorem lost_scope_changes_trace
    {candidate : Vertex → Vertex → Prop} {required : Group → Prop}
    {member : Group → Scope → Prop}
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k : Nat} {s t : Vertex} {g : Group} {scope : Scope}
    (accepted : ScopedComposition.Answer candidate required member
      (SelectedBranch start target before edge k) s t)
    (needed : required g) (belongs : member g scope)
    (supported : SelectedBranch start target before edge k scope s t)
    (lost : ¬ SelectedBranch start target after edge k scope s t) :
    ∃ n, n ≤ k ∧
      Trace candidate required member (SelectedBranch start target before edge k) edge g scope s t n ∧
      ¬ Trace candidate required member (SelectedBranch start target after edge k) edge g scope s t n := by
  rcases bounded_has_shortest supported.2.2.1 with ⟨n, within, shortest⟩
  refine ⟨n, within, ⟨accepted, ⟨accepted.1, needed, belongs, supported⟩, shortest⟩, ?_⟩
  intro retained
  exact lost retained.2.1.2.2.2

/-- The bounded producer publishes a witness for each selected pair and
blocked vertex whose two shortest segments fit the total hop limit. -/
def MaskWitness (start target blocked : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (k : Nat) (scope : Scope) (s z t : Vertex) : Prop :=
  start scope s ∧ target scope t ∧ blocked scope z ∧ Via edge k s z t

/-- The exact delta of the public witness relation for a mask-only edit.
The join must include every selected pair, even if the pair is absent
from the final candidate relation or its scope belongs to no group. -/
theorem mask_witness_changes_iff
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k : Nat} {scope : Scope} {s z t : Vertex} :
    (¬ (MaskWitness start target before edge k scope s z t ↔
        MaskWitness start target after edge k scope s z t)) ↔
      start scope s ∧ target scope t ∧ (¬ (before scope z ↔ after scope z)) ∧
      ∃ p q, p + q ≤ k ∧ Shortest edge p s z ∧ Shortest edge q z t := by
  classical
  constructor
  · intro changed
    have left : start scope s := Classical.byContradiction fun absent =>
      changed ⟨fun h => (absent h.1).elim, fun h => (absent h.1).elim⟩
    have right : target scope t := Classical.byContradiction fun absent =>
      changed ⟨fun h => (absent h.2.1).elim, fun h => (absent h.2.1).elim⟩
    have through : Via edge k s z t := Classical.byContradiction fun absent =>
      changed ⟨fun h => (absent h.2.2.2).elim, fun h => (absent h.2.2.2).elim⟩
    refine ⟨left, right, ?_, via_iff_shortest.mp through⟩
    intro unchanged
    exact changed
      ⟨fun h => ⟨left, right, unchanged.mp h.2.2.1, through⟩,
       fun h => ⟨left, right, unchanged.mpr h.2.2.1, through⟩⟩
  · rintro ⟨left, right, changed, distances⟩ unchanged
    have through := via_iff_shortest.mpr distances
    exact changed
      ⟨fun h => (unchanged.mp ⟨left, right, h, through⟩).2.2.1,
       fun h => (unchanged.mpr ⟨left, right, h, through⟩).2.2.1⟩

/-- Incoming and outgoing distance buckets for a single edited vertex
and scope. Each bucket contains an endpoint and its shortest distance.
Filter before publishing the endpoint pair. -/
def witnessPairs (k : Nat) (incoming outgoing : List (Vertex × Nat)) :
    List (Vertex × Vertex) :=
  incoming.flatMap fun left =>
    (outgoing.filter fun right => decide (left.2 + right.2 ≤ k)).map
      fun right => (left.1, right.1)

theorem witness_pairs_exact
    {start target before after : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {k : Nat} {scope : Scope} {s z t : Vertex}
    (incoming outgoing : List (Vertex × Nat))
    (incomingExact : ∀ v n, (v, n) ∈ incoming ↔ start scope v ∧ Shortest edge n v z)
    (outgoingExact : ∀ v n, (v, n) ∈ outgoing ↔ target scope v ∧ Shortest edge n z v)
    (changed : ¬ (before scope z ↔ after scope z)) :
    (s, t) ∈ witnessPairs k incoming outgoing ↔
      ¬ (MaskWitness start target before edge k scope s z t ↔
         MaskWitness start target after edge k scope s z t) := by
  rw [mask_witness_changes_iff]
  simp only [witnessPairs, List.mem_flatMap, List.mem_map, List.mem_filter,
    decide_eq_true_eq, Prod.mk.injEq]
  constructor
  · rintro ⟨⟨source, p⟩, first, ⟨destination, q⟩, ⟨second, within⟩, rfl, rfl⟩
    obtain ⟨left, firstPath⟩ := (incomingExact source p).mp first
    obtain ⟨right, secondPath⟩ := (outgoingExact destination q).mp second
    exact ⟨left, right, changed, p, q, within, firstPath, secondPath⟩
  · rintro ⟨left, right, _, p, q, within, firstPath, secondPath⟩
    exact ⟨(s, p), (incomingExact s p).mpr ⟨left, firstPath⟩,
      (t, q), ⟨(outgoingExact t q).mpr ⟨right, secondPath⟩, within⟩, rfl, rfl⟩

/-- Repair the public witness membership by reusing the previous row
whenever it is outside the join for an edited key. For a row inside
that join, the post-edit mask determines insertion or withdrawal. -/
def repairedMaskWitness [DecidableEq Vertex]
    (start target before after : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (k : Nat) (edited : Scope → Vertex → Bool)
    (incoming outgoing : Scope → Vertex → List (Vertex × Nat))
    (scope : Scope) (s z t : Vertex) : Prop :=
  if edited scope z = true then
    if (s, t) ∈ witnessPairs k (incoming scope z) (outgoing scope z) then after scope z
    else MaskWitness start target before edge k scope s z t
  else MaskWitness start target before edge k scope s z t

/-- The candidate repair and complete recomputation agree on every
public witness row, regardless of final candidate or group membership.
The source must establish the edited key inventory and exact distance
buckets on the same fixed graph cut. This theorem concerns membership. -/
theorem repaired_mask_witness_eq_recompute [DecidableEq Vertex]
    (start target before after : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (k : Nat) (edited : Scope → Vertex → Bool)
    (incoming outgoing : Scope → Vertex → List (Vertex × Nat))
    (editExact : ∀ scope z, edited scope z = true ↔ ¬ (before scope z ↔ after scope z))
    (incomingExact : ∀ scope z v n,
      (v, n) ∈ incoming scope z ↔ start scope v ∧ Shortest edge n v z)
    (outgoingExact : ∀ scope z v n,
      (v, n) ∈ outgoing scope z ↔ target scope v ∧ Shortest edge n z v)
    (scope : Scope) (s z t : Vertex) :
    repairedMaskWitness start target before after edge k edited incoming outgoing scope s z t ↔
      MaskWitness start target after edge k scope s z t := by
  classical
  unfold repairedMaskWitness
  split
  · next changed =>
    have exactPairs := witness_pairs_exact (s := s) (t := t) (k := k)
      (incoming scope z) (outgoing scope z) (incomingExact scope z) (outgoingExact scope z)
      ((editExact scope z).mp changed)
    split
    · next present =>
      obtain ⟨left, right, _, distances⟩ := mask_witness_changes_iff.mp (exactPairs.mp present)
      exact ⟨fun h => ⟨left, right, h, via_iff_shortest.mpr distances⟩, fun h => h.2.2.1⟩
    · next absent =>
      exact Classical.byContradiction fun diff => absent (exactPairs.mpr diff)
  · next unchanged =>
    have same : before scope z ↔ after scope z :=
      Classical.byContradiction fun diff => unchanged ((editExact scope z).mpr diff)
    exact ⟨fun h => ⟨h.1, h.2.1, same.mp h.2.2.1, h.2.2.2⟩,
      fun h => ⟨h.1, h.2.1, same.mpr h.2.2.1, h.2.2.2⟩⟩

/-- Set interpretation of the exposed relations downstream of `mask_witness`.
The complete graph-derived relations are inputs to this suffix. -/
structure MaskSuffix (Group Scope Vertex : Type) where
  maskWitness : Scope → Vertex → Vertex → Vertex → Prop
  maskRejected : Scope → Vertex → Vertex → Prop
  branchAnswer : Scope → Vertex → Vertex → Prop
  groupWitness : Group → Scope → Vertex → Vertex → Prop
  groupSupport : Group → Vertex → Vertex → Prop
  groupMissing : Group → Vertex → Vertex → Prop
  groupFailure : Vertex → Vertex → Prop
  groupAnswer : Vertex → Vertex → Prop
  answerTrace : Group → Scope → Vertex → Vertex → Nat → Prop

def maskSuffix (start target : Scope → Vertex → Prop) (edge : Vertex → Vertex → Prop)
    (k : Nat) (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (witness : Scope → Vertex → Vertex → Vertex → Prop) :
    MaskSuffix Group Scope Vertex :=
  let rejected scope s t := ∃ z, witness scope s z t
  let branch scope s t := start scope s ∧ target scope t ∧ Bounded edge k s t ∧
    ¬ rejected scope s t
  let groupWitness := ScopedComposition.Witness candidate required member branch
  let support := ScopedComposition.Covered candidate required member branch
  let missing := ScopedComposition.Missing candidate required member branch
  let failure s t := ∃ g, missing g s t
  let answer := ScopedComposition.ScopedAnswer candidate required member branch
  ⟨witness, rejected, branch, groupWitness, support, missing, failure, answer,
    fun g scope s t n => answer s t ∧ groupWitness g scope s t ∧ Shortest edge n s t⟩

/-- Recomputing the stratified suffix from a repaired witness relation agrees
with recomputing it from the new mask. This covers every supporting scope,
including changes that leave the final Boolean answer intact. -/
theorem repaired_mask_suffix_eq_recompute [DecidableEq Vertex]
    (start target before after : Scope → Vertex → Prop)
    (edge : Vertex → Vertex → Prop) (k : Nat)
    (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (edited : Scope → Vertex → Bool)
    (incoming outgoing : Scope → Vertex → List (Vertex × Nat))
    (editExact : ∀ scope z, edited scope z = true ↔ ¬ (before scope z ↔ after scope z))
    (incomingExact : ∀ scope z v n,
      (v, n) ∈ incoming scope z ↔ start scope v ∧ Shortest edge n v z)
    (outgoingExact : ∀ scope z v n,
      (v, n) ∈ outgoing scope z ↔ target scope v ∧ Shortest edge n z v) :
    maskSuffix start target edge k candidate required member
        (repairedMaskWitness start target before after edge k edited incoming outgoing) =
      maskSuffix start target edge k candidate required member
        (MaskWitness start target after edge k) := by
  have sameWitness : repairedMaskWitness start target before after edge k edited incoming outgoing =
      MaskWitness start target after edge k := by
    funext scope s z t
    exact propext (repaired_mask_witness_eq_recompute start target before after edge k edited
      incoming outgoing editExact incomingExact outgoingExact scope s z t)
  rw [sameWitness]

theorem mask_suffix_branch_eq_selected
    (start target blocked : Scope → Vertex → Prop) (edge : Vertex → Vertex → Prop) (k : Nat)
    (candidate : Vertex → Vertex → Prop) (required : Group → Prop) (member : Group → Scope → Prop)
    (scope : Scope) (s t : Vertex) :
    (maskSuffix start target edge k candidate required member
      (MaskWitness start target blocked edge k)).branchAnswer scope s t ↔
      SelectedBranch start target blocked edge k scope s t := by
  constructor
  · rintro ⟨source, target, reachable, noWitness⟩
    exact ⟨source, target, reachable, fun ⟨z, banned, via⟩ =>
      noWitness ⟨z, source, target, banned, via⟩⟩
  · rintro ⟨source, target, reachable, noVia⟩
    exact ⟨source, target, reachable, fun ⟨z, _, _, banned, via⟩ => noVia ⟨z, banned, via⟩⟩

/-- A direct nested scan makes exactly this many hop-bound checks before
filtering. Bucket construction and lookups are separate source costs. -/
theorem witness_pair_checks (incoming outgoing : List (Vertex × Nat)) :
    (incoming.flatMap fun left => outgoing.map fun right => (left, right)).length =
      incoming.length * outgoing.length := by
  induction incoming with
  | nil => simp
  | cons left rest ih => simp [List.flatMap_cons, ih, Nat.add_mul, Nat.add_comm]

/-- Stop on the first distance above the total-hop limit. Return the
accepted prefix and count the comparisons actually made. -/
def witnessPrefix (k leftHops : Nat) : List (Vertex × Nat) → List (Vertex × Nat) × Nat
  | [] => ([], 0)
  | right :: rest =>
    if leftHops + right.2 ≤ k then
      let (rows, checks) := witnessPrefix k leftHops rest
      (right :: rows, checks + 1)
    else ([], 1)

theorem witness_prefix_exact (k leftHops : Nat) (outgoing : List (Vertex × Nat))
    (ordered : outgoing.Pairwise (fun a b => a.2 ≤ b.2)) :
    (witnessPrefix k leftHops outgoing).1 =
      outgoing.filter (fun right => decide (leftHops + right.2 ≤ k)) := by
  induction outgoing with
  | nil => rfl
  | cons right rest ih =>
    obtain ⟨headOrder, tailOrder⟩ := List.pairwise_cons.mp ordered
    by_cases within : leftHops + right.2 ≤ k
    · simp [witnessPrefix, within, ih tailOrder]
    · have noneWithin : ∀ entry ∈ rest, ¬ decide (leftHops + entry.2 ≤ k) = true := by
        intro entry present
        have later := headOrder entry present
        simp only [decide_eq_true_eq]
        omega
      have empty : rest.filter (fun entry => decide (leftHops + entry.2 ≤ k)) = [] :=
        List.filter_eq_nil_iff.mpr noneWithin
      simp [witnessPrefix, within, empty]

theorem witness_prefix_checks (k leftHops : Nat) (outgoing : List (Vertex × Nat)) :
    let (rows, checks) := witnessPrefix k leftHops outgoing
    checks = rows.length + if rows.length < outgoing.length then 1 else 0 := by
  induction outgoing with
  | nil => simp [witnessPrefix]
  | cons right rest ih =>
    by_cases within : leftHops + right.2 ≤ k
    · cases scan : witnessPrefix k leftHops rest with
      | mk rows checks =>
        rw [scan] at ih
        simpa [witnessPrefix, within, scan, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]
          using congrArg Nat.succ ih
    · simp [witnessPrefix, within]

def witnessPrefixChecks (k : Nat) (incoming outgoing : List (Vertex × Nat)) : Nat :=
  (incoming.map fun left => (witnessPrefix k left.2 outgoing).2).sum

/-- Per incoming endpoint the scan charges each accepted pair and at
most one failed comparison. This excludes building the distance order
and restoring the observable order of the existing relation. -/
theorem witness_prefix_join_checks (k : Nat) (incoming outgoing : List (Vertex × Nat))
    (ordered : outgoing.Pairwise (fun a b => a.2 ≤ b.2)) :
    witnessPrefixChecks k incoming outgoing ≤ (witnessPairs k incoming outgoing).length +
      incoming.length := by
  induction incoming with
  | nil => simp [witnessPrefixChecks, witnessPairs]
  | cons left rest ih =>
    have head := witness_prefix_checks k left.2 outgoing
    have rows := witness_prefix_exact k left.2 outgoing ordered
    simp only [witnessPrefixChecks, witnessPairs, List.map_cons, List.sum_cons,
      List.flatMap_cons, List.length_append, List.length_map, List.length_cons] at ih ⊢
    dsimp at head
    rw [rows] at head
    split at head <;> omega

theorem sparse_prefix_checks_save (k : Nat) (incoming outgoing : List (Vertex × Nat))
    (ordered : outgoing.Pairwise (fun a b => a.2 ≤ b.2))
    (sparse : (witnessPairs k incoming outgoing).length + incoming.length <
      incoming.length * outgoing.length) :
    witnessPrefixChecks k incoming outgoing < incoming.length * outgoing.length :=
  Nat.lt_of_le_of_lt (witness_prefix_join_checks k incoming outgoing ordered) sparse

/-- Each incoming occurrence whose original bucket has a rejected suffix
costs one unsuccessful test in distance order. Count occurrences rather
than distinct endpoints, since the join visits each occurrence. -/
def witnessPrefixStops (k : Nat) (incoming outgoing : List (Vertex × Nat)) : Nat :=
  incoming.countP fun left => decide
    ((outgoing.filter fun right => decide (left.2 + right.2 ≤ k)).length < outgoing.length)

/-- For a distance index over the original bucket occurrences, the exact
guard count is the number of output occurrences plus the first failures.
Restoring publication order and retaining evidence are separate costs. -/
theorem witness_prefix_join_checks_exact (k : Nat)
    (incoming original indexed : List (Vertex × Nat))
    (sameEntries : indexed.Perm original)
    (ordered : indexed.Pairwise (fun a b => a.2 ≤ b.2)) :
    witnessPrefixChecks k incoming indexed =
      (witnessPairs k incoming original).length + witnessPrefixStops k incoming original := by
  induction incoming with
  | nil => simp [witnessPrefixChecks, witnessPrefixStops, witnessPairs]
  | cons left rest ih =>
    have checks := witness_prefix_checks k left.2 indexed
    have accepted := witness_prefix_exact k left.2 indexed ordered
    have sameFits := (sameEntries.filter fun right => decide (left.2 + right.2 ≤ k)).length_eq
    dsimp at checks
    rw [accepted, sameFits, sameEntries.length_eq] at checks
    simp only [witnessPrefixChecks, witnessPrefixStops, witnessPairs, List.map_cons, List.sum_cons,
      List.flatMap_cons, List.length_append, List.length_map, List.countP_cons] at ih ⊢
    rw [checks, ih]
    simp only [decide_eq_true_eq]
    omega

/-- Headroom for a single affected bucket, within one additive work unit.
The caller supplies a common price for an equivalent guard test and
the nonnegative additional work of the prefix route in that same unit.
The model makes no claim that a native guard has a constant wall cost. -/
theorem witness_prefix_budget_iff (k guardPrice extra : Nat)
    (incoming original indexed : List (Vertex × Nat))
    (sameEntries : indexed.Perm original)
    (ordered : indexed.Pairwise (fun a b => a.2 ≤ b.2)) :
    guardPrice * witnessPrefixChecks k incoming indexed + extra <
      guardPrice * (incoming.length * original.length) ↔
    extra < guardPrice * (incoming.length * original.length -
      ((witnessPairs k incoming original).length + witnessPrefixStops k incoming original)) := by
  rw [witness_prefix_join_checks_exact k incoming original indexed sameEntries ordered,
    Nat.mul_sub_left_distrib]
  omega

/-- Equal bucket sizes and the same hop limit can give different usable
headroom. With two incoming and two outgoing entries, the dense case
can repay no extra guard-equivalent work, while the sparse case repays
one unit but no strict gain remains if it costs two. -/
theorem equal_bucket_sizes_do_not_select_prefix :
    let incoming := [(0, 1), (1, 1)]
    let dense := [(2, 0), (3, 1)]
    let sparse := [(2, 2), (3, 3)]
    dense.length = sparse.length ∧
      witnessPrefixChecks 2 incoming dense = incoming.length * dense.length ∧
      witnessPrefixChecks 2 incoming sparse + 1 < incoming.length * sparse.length ∧
      witnessPrefixChecks 2 incoming sparse + 2 = incoming.length * sparse.length := by
  decide

/-- Distance order is an internal index. Scanning the original order
against the accepted set recovers the same list, including repeats.
This reference restoration scans the full original bucket. -/
theorem restore_witness_bucket_order [DecidableEq Vertex] (k leftHops : Nat)
    (original sorted : List (Vertex × Nat))
    (sameEntries : sorted.Perm original)
    (ordered : sorted.Pairwise (fun a b => a.2 ≤ b.2)) :
    original.filter (fun entry => decide (entry ∈ (witnessPrefix k leftHops sorted).1)) =
      original.filter (fun entry => decide (leftHops + entry.2 ≤ k)) := by
  rw [witness_prefix_exact k leftHops sorted ordered]
  apply List.filter_congr
  intro entry present
  simp [sameEntries.mem_iff.mpr present]

/-- The distance index carries one ordinal per original occurrence. Sort
only the accepted prefix by its ordinals, then project the original rows. -/
def restoreWitnessPrefix (k leftHops : Nat) (indexed : List ((Vertex × Nat) × Nat)) :
    List (Vertex × Nat) :=
  let accepted := indexed.takeWhile (fun entry => decide (leftHops + entry.1.2 ≤ k))
  (accepted.mergeSort (fun a b => decide (a.2 ≤ b.2))).map Prod.fst

theorem restore_witness_prefix_by_ordinal (k leftHops : Nat) (original : List (Vertex × Nat))
    (indexed : List ((Vertex × Nat) × Nat)) (sameEntries : indexed.Perm original.zipIdx)
    (ordered : indexed.Pairwise (fun a b => a.1.2 ≤ b.1.2)) :
    restoreWitnessPrefix k leftHops indexed =
      original.filter (fun entry => decide (leftHops + entry.2 ≤ k)) := by
  let keep (entry : (Vertex × Nat) × Nat) := decide (leftHops + entry.1.2 ≤ k)
  let byOrdinal (a b : (Vertex × Nat) × Nat) := decide (a.2 ≤ b.2)
  have accepted : indexed.takeWhile keep = indexed.filter keep := by
    clear sameEntries
    induction indexed with
    | nil => rfl
    | cons first rest ih =>
      obtain ⟨headOrder, tailOrder⟩ := List.pairwise_cons.mp ordered
      by_cases within : keep first = true
      · simp [within, ih tailOrder]
      · have empty : rest.filter keep = [] := by
          apply List.filter_eq_nil_iff.mpr
          intro entry present fits
          have later := headOrder entry present
          simp only [keep, decide_eq_true_eq] at within fits
          omega
        simp [within, empty]
  have occurrences : (original.zipIdx).Pairwise (fun a b => a.2 < b.2) := by
    have zipOrdered : ∀ (rows : List (Vertex × Nat)) (start : Nat),
        (rows.zipIdx start).Pairwise (fun a b => a.2 < b.2) := by
      intro rows
      induction rows with
      | nil => intro start; simp
      | cons first rest ih =>
        intro start
        rw [List.zipIdx_cons, List.pairwise_cons]
        refine ⟨fun entry present => ?_, ih (start + 1)⟩
        have after := (List.mk_mem_zipIdx_iff_le_and_getElem?_sub.mp present).1
        omega
    exact zipOrdered original 0
  have wanted := occurrences.filter keep
  have perm := (List.mergeSort_perm (indexed.filter keep) byOrdinal).trans (sameEntries.filter keep)
  have output : (indexed.filter keep).mergeSort byOrdinal = original.zipIdx.filter keep := by
    apply List.Perm.eq_of_pairwise (le := fun a b : (Vertex × Nat) × Nat => a.2 ≤ b.2) ?_ ?_ ?_ perm
    · intro a b aIn bIn ab ba
      have aOrig := List.mem_filter.mp (perm.subset aIn) |>.1
      have bOrig := List.mem_filter.mp bIn |>.1
      have sameOrdinal : a.2 = b.2 := by omega
      have aAt := List.mk_mem_zipIdx_iff_getElem?.mp aOrig
      have bAt := List.mk_mem_zipIdx_iff_getElem?.mp bOrig
      rw [sameOrdinal, bAt] at aAt
      exact Prod.ext (Option.some.inj aAt).symm sameOrdinal
    · simpa [byOrdinal] using List.pairwise_mergeSort (le := byOrdinal)
        (fun a b c ab bc => by simp only [byOrdinal, decide_eq_true_eq] at *; omega)
        (fun a b => by simp only [byOrdinal, Bool.or_eq_true, decide_eq_true_eq]; omega)
        (indexed.filter keep)
    · exact wanted.imp Nat.le_of_lt
  change ((indexed.takeWhile keep).mergeSort byOrdinal).map Prod.fst = _
  rw [accepted, output]
  simpa only [List.filter_map, Function.comp_def, List.zipIdx_map_fst] using
    (List.filter_map (p := fun entry : Vertex × Nat => decide (leftHops + entry.2 ≤ k))
      (f := Prod.fst) (l := original.zipIdx)).symm

/-- Restoring order by filtering the entire original bucket for every
incoming entry incurs all of the baseline's bucket visits in addition
to the prefix scan. Count visits to bucket entries in both phases. -/
theorem prefix_with_full_order_restore_cannot_save_visits
    (k : Nat) (incoming outgoing : List (Vertex × Nat)) :
    (incoming.flatMap fun left => outgoing.map fun right => (left, right)).length ≤
      witnessPrefixChecks k incoming outgoing +
        (incoming.map fun _ => outgoing.length).sum := by
  rw [witness_pair_checks]
  have restoreVisits :
      (incoming.map fun _ => outgoing.length).sum = incoming.length * outgoing.length := by
    induction incoming with
    | nil => simp
    | cons left rest ih => simp [ih, Nat.add_mul, Nat.add_comm]
  rw [restoreVisits]
  exact Nat.le_add_left _ _

/-- Sorting by distance may preserve membership but change the exposed
row order, even when every pair passes. -/
theorem distance_order_changes_witness_order :
    witnessPairs 2 [(0, 0)] [(1, 2), (2, 1)] ≠
      witnessPairs 2 [(0, 0)] [(2, 1), (1, 2)] := by decide

/-- When every pair passes, the prefix scan performs the same number
of comparisons as the full join. -/
theorem dense_prefix_checks_equal (k : Nat) (incoming outgoing : List (Vertex × Nat))
    (ordered : outgoing.Pairwise (fun a b => a.2 ≤ b.2))
    (allFit : ∀ left ∈ incoming, ∀ right ∈ outgoing, left.2 + right.2 ≤ k) :
    witnessPrefixChecks k incoming outgoing = incoming.length * outgoing.length := by
  induction incoming with
  | nil => simp [witnessPrefixChecks]
  | cons left rest ih =>
    have full : (witnessPrefix k left.2 outgoing).1 = outgoing := by
      rw [witness_prefix_exact k left.2 outgoing ordered]
      exact List.filter_eq_self.mpr fun right present =>
        decide_eq_true (allFit left (by simp) right present)
    have checks := witness_prefix_checks k left.2 outgoing
    dsimp at checks
    rw [full] at checks
    have tail := ih (fun entry present => allFit entry (List.mem_cons_of_mem left present))
    unfold witnessPrefixChecks at tail
    simp [witnessPrefixChecks, checks, tail, Nat.add_mul, Nat.add_comm]

/-- On the same admitted edit and request sequence, the saving in
recomputation must exceed the cost of finding affected pairs and any
net increase in reading, publication and other elapsed work. Costs are
inputs from the two source paths, in one unit and without double counting. -/
theorem mask_edit_reuse_break_even
    (findAffected repair rebuild reusedRead rebuiltRead reusedOther rebuiltOther : Nat) :
    findAffected + repair + reusedRead + reusedOther < rebuild + rebuiltRead + rebuiltOther ↔
      (findAffected : Int) + ((reusedRead : Int) - rebuiltRead) +
        ((reusedOther : Int) - rebuiltOther) < (rebuild : Int) - repair := by
  omega

/-- Charge initial setup exactly once and aggregate the paired requests
from the same lifecycle. The measured saving can repay extra setup
only when it exceeds that setup difference. -/
theorem lifecycle_reuse_break_even (baselineSetup reuseSetup : Nat)
    (requests : List (Nat × Nat)) :
    reuseSetup + (requests.map Prod.snd).sum <
        baselineSetup + (requests.map Prod.fst).sum ↔
      (reuseSetup : Int) - baselineSetup <
        ((requests.map Prod.fst).sum : Int) - (requests.map Prod.snd).sum := by
  omega

namespace EndpointSearch

def reverseEdge (edge : Vertex → Vertex → Prop) (s t : Vertex) : Prop :=
  edge t s

private theorem exact_prepend (first : edge s x) (rest : Exact edge n x t) :
    Exact edge (n + 1) s t := by
  induction n generalizing t with
  | zero =>
    change x = t at rest
    subst t
    exact ⟨s, rfl, first⟩
  | succ n ih =>
    rcases rest with ⟨y, path, last⟩
    exact ⟨y, ih path, last⟩

private theorem exact_reverse (path : Exact edge n s t) :
    Exact (reverseEdge edge) n t s := by
  induction n generalizing t with
  | zero => exact Eq.symm path
  | succ n ih =>
    rcases path with ⟨x, initialPath, last⟩
    exact exact_prepend (edge := reverseEdge edge) last (ih initialPath)

theorem shortest_reverse :
    Shortest edge n s t ↔ Shortest (reverseEdge edge) n t s := by
  constructor
  · rintro ⟨path, first⟩
    exact ⟨exact_reverse path, fun m earlier reversed =>
      first m earlier (exact_reverse reversed)⟩
  · rintro ⟨path, first⟩
    exact ⟨exact_reverse path, fun m earlier forward =>
      first m earlier (exact_reverse forward)⟩

/-- One BFS layer expands the preceding shortest layer and excludes
every vertex already reached. This recurrence counts distance discovery
only. The native predecessor relation still needs all shortest last edges. -/
theorem next_frontier_exact :
    Shortest edge (n + 1) s t ↔
      (∃ x, Shortest edge n s x ∧ edge x t) ∧ ¬ Bounded edge n s t := by
  constructor
  · intro first
    rcases shortest_has_predecessor first with ⟨x, predecessor⟩
    refine ⟨⟨x, predecessor_decreases predecessor, predecessor.2.2⟩, ?_⟩
    rintro ⟨m, within, path⟩
    exact first.2 m (by omega) path
  · rintro ⟨⟨x, initialPath, last⟩, unseen⟩
    exact ⟨⟨x, initialPath.1, last⟩, fun m earlier path => unseen ⟨m, by omega, path⟩⟩

theorem distance_unique (first : Shortest edge n s t) (second : Shortest edge m s t) :
    n = m := by
  rcases Nat.lt_trichotomy n m with earlier | same | later
  · exact False.elim (second.2 n earlier first.1)
  · exact same
  · exact False.elim (first.2 m later second.1)

/-- A fixed source and target suffice for all possible mask vertices.
The suffix is read from a search rooted at the target on reversed edges. -/
theorem via_endpoint_searches :
    Via edge k s z t ↔ ∃ p q, p + q ≤ k ∧
      Shortest edge p s z ∧ Shortest (reverseEdge edge) q t z := by
  rw [via_iff_shortest]
  constructor
  · rintro ⟨p, q, within, initialPath, finalPath⟩
    exact ⟨p, q, within, initialPath, shortest_reverse.mp finalPath⟩
  · rintro ⟨p, q, within, initialPath, finalPath⟩
    exact ⟨p, q, within, initialPath, shortest_reverse.mpr finalPath⟩

/-- The selected-pair observation uses the source frontier for reachability
and both frontiers for total-hop exclusion. Distances outside the bound
do not participate. -/
def branchFromFrontiers (start target blocked : Scope → Vertex → Prop)
    (forward reverse : Nat → Vertex → Vertex → Prop) (k : Nat)
    (scope : Scope) (s t : Vertex) : Prop :=
  start scope s ∧ target scope t ∧
    (∃ n, n ≤ k ∧ forward n s t) ∧
    ¬ ∃ z p q, blocked scope z ∧ p + q ≤ k ∧ forward p s z ∧ reverse q t z

theorem branch_from_frontiers_iff
    {start target blocked : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {forward reverse : Nat → Vertex → Vertex → Prop}
    {k : Nat} {scope : Scope} {s t : Vertex}
    (forwardExact : ∀ n z, n ≤ k → (forward n s z ↔ Shortest edge n s z))
    (reverseExact : ∀ n z, n ≤ k → (reverse n t z ↔ Shortest (reverseEdge edge) n t z)) :
    branchFromFrontiers start target blocked forward reverse k scope s t ↔
      SelectedBranch start target blocked edge k scope s t := by
  constructor
  · rintro ⟨hs, ht, ⟨n, within, reached⟩, noWitness⟩
    refine ⟨hs, ht, ⟨n, within, ((forwardExact n t within).mp reached).1⟩, ?_⟩
    rintro ⟨z, banned, path⟩
    rcases via_endpoint_searches.mp path with ⟨p, q, total, initialPath, finalPath⟩
    exact noWitness ⟨z, p, q, banned, total,
      (forwardExact p z (by omega)).mpr initialPath, (reverseExact q z (by omega)).mpr finalPath⟩
  · rintro ⟨hs, ht, reach, noWitness⟩
    rcases bounded_has_shortest reach with ⟨n, within, reached⟩
    refine ⟨hs, ht, ⟨n, within, (forwardExact n t within).mpr reached⟩, ?_⟩
    rintro ⟨z, p, q, banned, total, initialPath, finalPath⟩
    exact noWitness ⟨z, banned, via_endpoint_searches.mpr ⟨p, q, total,
      (forwardExact p z (by omega)).mp initialPath, (reverseExact q z (by omega)).mp finalPath⟩⟩

/-- Exact frontiers at the two roots suffice to preserve membership of the
public group answer and every final trace row for that pair. This is a
relation membership result. Ordered rows and derivation evidence are
additional implementation observations. -/
theorem selected_pair_projection
    {candidate : Vertex → Vertex → Prop} {required : Group → Prop} {member : Group → Scope → Prop}
    {start target blocked : Scope → Vertex → Prop}
    {edge : Vertex → Vertex → Prop} {forward reverse : Nat → Vertex → Vertex → Prop}
    {k : Nat} {s t : Vertex}
    (forwardExact : ∀ n z, n ≤ k → (forward n s z ↔ Shortest edge n s z))
    (reverseExact : ∀ n z, n ≤ k → (reverse n t z ↔ Shortest (reverseEdge edge) n t z)) :
    let fromFrontiers := branchFromFrontiers start target blocked forward reverse k
    let fromGraph := SelectedBranch start target blocked edge k
    (ScopedComposition.ScopedAnswer candidate required member fromFrontiers s t ↔
      ScopedComposition.ScopedAnswer candidate required member fromGraph s t) ∧
    (∀ g scope n,
      (ScopedComposition.Answer candidate required member fromFrontiers s t ∧
        ScopedComposition.Witness candidate required member fromFrontiers g scope s t ∧
        n ≤ k ∧ forward n s t) ↔
      Trace candidate required member fromGraph edge g scope s t n) := by
  dsimp only
  have branch (scope : Scope) := branch_from_frontiers_iff
    (start := start) (target := target) (blocked := blocked) (scope := scope)
    forwardExact reverseExact
  have answer :
      ScopedComposition.Answer candidate required member
        (branchFromFrontiers start target blocked forward reverse k) s t ↔
      ScopedComposition.Answer candidate required member
        (SelectedBranch start target blocked edge k) s t := by
    constructor
    · rintro ⟨selected, supported⟩
      refine ⟨selected, fun g needed => ?_⟩
      rcases supported g needed with ⟨scope, belongs, witness⟩
      exact ⟨scope, belongs, (branch scope).mp witness⟩
    · rintro ⟨selected, supported⟩
      refine ⟨selected, fun g needed => ?_⟩
      rcases supported g needed with ⟨scope, belongs, witness⟩
      exact ⟨scope, belongs, (branch scope).mpr witness⟩
  refine ⟨?_, ?_⟩
  · rw [ScopedComposition.no_missing_iff_answer, ScopedComposition.no_missing_iff_answer]
    exact answer
  · intro g scope n
    constructor
    · rintro ⟨covered, ⟨selected, needed, belongs, valid⟩, within, distance⟩
      exact ⟨answer.mp covered, ⟨selected, needed, belongs, (branch scope).mp valid⟩,
        (forwardExact n t within).mp distance⟩
    · rintro ⟨covered, ⟨selected, needed, belongs, valid⟩, shortest⟩
      obtain ⟨m, within, first⟩ := bounded_has_shortest valid.2.2.1
      have same : n = m := distance_unique shortest first
      subst m
      exact ⟨answer.mpr covered, ⟨selected, needed, belongs, (branch scope).mpr valid⟩,
        within, (forwardExact n t within).mpr shortest⟩

theorem predecessor_from_shortest_frontier :
    Predecessor edge n s x t ↔
      Shortest edge (n + 1) s t ∧ Shortest edge n s x ∧ edge x t := by
  constructor
  · intro predecessor
    exact ⟨predecessor.1, predecessor_decreases predecessor, predecessor.2.2⟩
  · rintro ⟨endDistance, initialPath, last⟩
    exact ⟨endDistance, initialPath.1, last⟩

/-- An all-source exact-hop relation can expose a later walk back to an
already reached vertex. A shortest-only replacement would lose this row. -/
theorem exact_layer_not_recoverable_by_shortest_filter (loop : edge s s) :
    Exact edge 1 s s ∧ ¬ Shortest edge 1 s s := by
  refine ⟨⟨s, rfl, loop⟩, fun shortest => ?_⟩
  exact shortest.2 0 (by decide) rfl

/-- Even an all-pairs table of shortest distances is insufficient input
for reconstructing the observable exact layers. The two one-vertex
graphs differ only by a self-loop. -/
theorem exact_layers_not_determined_by_shortest :
    (¬ ∃ reconstruct : (Nat → Unit → Unit → Prop) → Prop,
      ∀ edge : Unit → Unit → Prop, reconstruct (Shortest edge) ↔ Exact edge 1 () ()) := by
  intro ⟨reconstruct, correct⟩
  let withoutLoop : Unit → Unit → Prop := fun _ _ => False
  let withLoop : Unit → Unit → Prop := fun _ _ => True
  have same : Shortest withoutLoop = Shortest withLoop := by
    funext n s t
    cases s
    cases t
    apply propext
    cases n with
    | zero =>
      exact ⟨fun _ => ⟨rfl, fun m earlier => False.elim (Nat.not_lt_zero m earlier)⟩,
        fun _ => ⟨rfl, fun m earlier => False.elim (Nat.not_lt_zero m earlier)⟩⟩
    | succ n =>
      constructor <;> intro shortest <;>
        exact False.elim (shortest.2 0 (Nat.zero_lt_succ n) rfl)
  have hasLoop : Exact withLoop 1 () () := ⟨(), rfl, trivial⟩
  have reconstructed := (correct withLoop).mpr hasLoop
  rw [← same] at reconstructed
  obtain ⟨_, _, absent⟩ := (correct withoutLoop).mp reconstructed
  exact absent

/-- One edge examination per distinct root and stored edge gives this
ceiling for the expansion phase. Repeated roots, duplicate adjacency
entries and other phases are accounted for separately by the caller. -/
def expansionCeiling (sources targets edges : Nat) : Nat :=
  (sources + targets) * edges

theorem expansion_ceiling_split (sources targets edges : Nat) :
    expansionCeiling sources targets edges = sources * edges + targets * edges := by
  simp [expansionCeiling, Nat.add_mul]

/-- If the measured traversal emits a duplicate-free edge-visit trace
for one root and each visit belongs to the admitted adjacency, then it
cannot examine more edges than are stored in that adjacency. -/
theorem root_visit_bound {Edge : Type} {visited adjacency : List Edge}
    (once : visited.Nodup) (admitted : ∀ entry ∈ visited, entry ∈ adjacency) :
    visited.length ≤ adjacency.length :=
  once.length_le_of_subset admitted

/-- For a complete graph, a direct forward join from the identity layer
visits each stored edge once. Each additional positive layer has every
ordered pair and visits each edge once per root. This is a cost model of
that join orientation, contingent on the native probe trace. -/
def denseLayerVisits (vertices additionalLayers edges : Nat) : Nat :=
  (1 + additionalLayers * vertices) * edges

theorem fewer_dense_expansion_visits (sources targets vertices additionalLayers edges : Nat)
    (nonempty : 0 < edges) (selective : sources + targets < 1 + additionalLayers * vertices) :
    expansionCeiling sources targets edges < denseLayerVisits vertices additionalLayers edges := by
  exact Nat.mul_lt_mul_of_pos_right selective nonempty

end EndpointSearch

end Ascent.ScopedQuery
