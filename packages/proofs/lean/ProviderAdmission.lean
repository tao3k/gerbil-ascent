-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderFrontier

/-! B23 concretization obligations and multiplicity-preserving custom index
admission. Procedure/shape contracts do not establish these semantic laws.
Witness extraction, stable field equality and finite bucket coverage are
implementation premises, checked separately by Scheme and TLA controls. -/
namespace Ascent.ProviderAdmission

def mass (bucket : List Row) (count : Row → Nat) : Nat :=
  (bucket.map count).sum

theorem mass_le (bucket : List Row) (packet source : Row → Nat)
    (cap : ∀ r ∈ bucket, packet r ≤ source r) : mass bucket packet ≤ mass bucket source := by
  induction bucket with
  | nil => simp [mass]
  | cons r rest ih =>
      simp only [mass, List.map_cons, List.sum_cons]
      exact Nat.add_le_add (cap r (by simp)) (ih (fun r hr => cap r (by simp [hr])))

-- Aggregate equality does not alone establish coverage. Pointwise caps force
-- every per-row deficit to vanish, preserving duplicate source occurrences
-- independently of packet order.
theorem cap_and_mass_exact (bucket : List Row) (packet source : Row → Nat)
    (cap : ∀ r ∈ bucket, packet r ≤ source r)
    (equal : mass bucket packet = mass bucket source) :
    ∀ r ∈ bucket, packet r = source r := by
  induction bucket with
  | nil => simp
  | cons head rest ih =>
      have headCap := cap head (by simp)
      have tailCap : ∀ r ∈ rest, packet r ≤ source r := fun r hr => cap r (by simp [hr])
      have tailLe := mass_le rest packet source tailCap
      have summed : packet head + mass rest packet = source head + mass rest source := equal
      have headEq : packet head = source head := by omega
      have tailEq : mass rest packet = mass rest source := by omega
      intro r hr
      rcases List.mem_cons.mp hr with same | inside
      · subst r; exact headEq
      · exact ih tailCap tailEq r inside

theorem key_occurrences_exact (bucket : List Row) (key : Row → Key) (wanted : Key)
    (packet source : Row → Nat) (cap : ∀ r, packet r ≤ source r)
    (covered : ∀ r, key r = wanted → r ∈ bucket ∨ source r = 0)
    (equal : mass bucket packet = mass bucket source) :
    ∀ r, key r = wanted → packet r = source r := by
  intro r matched
  rcases covered r matched with present | zero
  · exact cap_and_mass_exact bucket packet source (fun r _ => cap r) equal r present
  · have bound := cap r; omega

theorem foreign_occurrences_zero (packet source : Row → Nat)
    (cap : ∀ r, packet r ≤ source r) (r : Row) (absent : source r = 0) : packet r = 0 := by
  have bound := cap r; omega

-- No ordered-bucket equality is inferred: legal custom packets may permute rows.
structure Domain (State Row : Type) where
  le : State → State → Prop
  merge : State → State → State
  gamma : State → Row → Prop
  tau : State → State → Row → Prop
  delta : State → State → Row → Prop
  old_le_merge : ∀ s d, le s (merge s d)
  gamma_monotone : ∀ s t, le s t → ∀ r, gamma s r → gamma t r
  partition : ∀ s d r, tau s d r ∨ delta s d r ↔ gamma (merge s d) r
  fresh_delta : ∀ s d r, gamma (merge s d) r → ¬ gamma s r → delta s d r

theorem old_visible_preserved (provider : Domain State Row) (s d : State) (r : Row)
    (old : provider.gamma s r) : provider.gamma (provider.merge s d) r :=
  provider.gamma_monotone s _ (provider.old_le_merge s d) r old

theorem delta_sound (provider : Domain State Row) (s d : State) (r : Row)
    (fresh : provider.delta s d r) : provider.gamma (provider.merge s d) r :=
  (provider.partition s d r).mp (Or.inr fresh)

theorem tau_sound (provider : Domain State Row) (s d : State) (r : Row)
    (old : provider.tau s d r) : provider.gamma (provider.merge s d) r :=
  (provider.partition s d r).mp (Or.inl old)

theorem fresh_cannot_skip_delta (provider : Domain State Row) (s d : State) (r : Row)
    (new : provider.gamma (provider.merge s d) r) (absent : ¬ provider.gamma s r) :
    provider.delta s d r := provider.fresh_delta s d r new absent

def providerPivots (delta next : Key → Env → Env → Prop) : List Key → Env → Env → Prop
  | [], _, _ => False
  | key :: rest, input, output =>
      (∃ middle, delta key input middle ∧ ProviderFrontier.body next rest middle output) ∨
      (∃ middle, next key input middle ∧ providerPivots delta next rest middle output)

theorem pivots_complete (old next delta : Key → Env → Env → Prop)
    (covers : ∀ k x y, ProviderFrontier.changed (old k) (next k) x y → delta k x y)
    (keys : List Key) (x y : Env) (hit : ProviderFrontier.pivots old next keys x y) :
    providerPivots delta next keys x y := by
  induction keys generalizing x y with
  | nil => exact False.elim hit
  | cons k rest ih =>
      rcases hit with ⟨middle, fresh, tail⟩ | ⟨middle, first, tail⟩
      · exact Or.inl ⟨middle, covers k x middle fresh, tail⟩
      · exact Or.inr ⟨middle, first, ih middle y tail⟩

theorem pivots_sound (next delta : Key → Env → Env → Prop)
    (sound : ∀ k x y, delta k x y → next k x y) (keys : List Key) (x y : Env)
    (hit : providerPivots delta next keys x y) : ProviderFrontier.body next keys x y := by
  induction keys generalizing x y with
  | nil => exact False.elim hit
  | cons k rest ih =>
      rcases hit with ⟨middle, fresh, tail⟩ | ⟨middle, first, tail⟩
      · exact ⟨middle, sound k x middle fresh, tail⟩
      · exact ⟨middle, first, ih middle y tail⟩

theorem provider_body_partition (old next delta : Key → Env → Env → Prop)
    (grows : ∀ k x y, old k x y → next k x y)
    (covers : ∀ k x y, ProviderFrontier.changed (old k) (next k) x y → delta k x y)
    (sound : ∀ k x y, delta k x y → next k x y) (keys : List Key) (x y : Env) :
    ProviderFrontier.body next keys x y ↔ ProviderFrontier.body old keys x y ∨
      providerPivots delta next keys x y := by
  constructor
  · intro hit
    rcases (ProviderFrontier.body_partition old next grows keys x y).mp hit with prior | fresh
    · exact Or.inl prior
    · exact Or.inr (pivots_complete old next delta covers keys x y fresh)
  · intro hit
    rcases hit with prior | fresh
    · exact (ProviderFrontier.body_partition old next grows keys x y).mpr (Or.inl prior)
    · exact pivots_sound next delta sound keys x y fresh

-- Connect the positive-body result directly to the abstract provider's two
-- concretization laws. Delta may overlap tau; exact Set difference is optional.
theorem domain_body_partition (provider : Domain State (Env × Env))
    (old change : Key → State) (keys : List Key) (x y : Env) :
    ProviderFrontier.body
      (fun k a b => provider.gamma (provider.merge (old k) (change k)) (a,b)) keys x y ↔
    ProviderFrontier.body (fun k a b => provider.gamma (old k) (a,b)) keys x y ∨
    providerPivots (fun k a b => provider.delta (old k) (change k) (a,b))
      (fun k a b => provider.gamma (provider.merge (old k) (change k)) (a,b)) keys x y :=
  provider_body_partition _ _ _
    (fun k a b hit => old_visible_preserved provider (old k) (change k) (a,b) hit)
    (fun k a b hit => fresh_cannot_skip_delta provider (old k) (change k) (a,b) hit.1 hit.2)
    (fun k a b hit => delta_sound provider (old k) (change k) (a,b) hit) keys x y

end Ascent.ProviderAdmission
