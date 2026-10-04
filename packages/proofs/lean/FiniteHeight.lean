/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Termination for a ranked finite-height state space. This theorem is a
proof obligation for typed descriptors, not a theorem about arbitrary
Scheme closures. Construction and external data validity remain separate.
-/
import Std

namespace Ascent

def iterateStep {α : Type} (step : α → α) (initial : α) : Nat → α
  | 0 => initial
  | n + 1 => step (iterateStep step initial n)

/-- Every nonstationary step must strictly increase a bounded rank. -/
theorem bounded_rank_stabilizes {α : Type} (step : α → α)
    (initial : α) (rank : α → Nat) (height : Nat)
    (bounded : ∀ x, rank x ≤ height)
    (progress : ∀ x, step x ≠ x → rank x < rank (step x)) :
    ∃ n, n ≤ height ∧
      step (iterateStep step initial n) = iterateStep step initial n := by
  apply Classical.byContradiction
  intro h
  have moving : ∀ n, n ≤ height →
      step (iterateStep step initial n) ≠ iterateStep step initial n := by
    intro n hn heq
    exact h ⟨n, hn, heq⟩
  have climbing : ∀ n, n ≤ height + 1 →
      n ≤ rank (iterateStep step initial n) := by
    intro n
    induction n with
    | zero => intro _; omega
    | succ n ih =>
      intro hn
      have old := ih (by omega)
      have incr := progress (iterateStep step initial n)
        (moving n (by omega))
      simp only [iterateStep] at *
      omega
  have lower := climbing (height + 1) (by omega)
  have upper := bounded (iterateStep step initial (height + 1))
  omega

/-- A product's rank is additive; its height is the sum of component heights. -/
theorem product_rank_bounded {α β : Type}
    (ra : α → Nat) (rb : β → Nat) (ha hb : Nat)
    (ba : ∀ x, ra x ≤ ha) (bb : ∀ y, rb y ≤ hb) (x : α × β) :
    ra x.1 + rb x.2 ≤ ha + hb := by
  have := ba x.1
  have := bb x.2
  omega

/-- A finite function table carries one codomain rank per domain element. -/
def tableRank {α : Type} (rank : α → Nat) : List α → Nat
  | [] => 0
  | x :: xs => rank x + tableRank rank xs

theorem table_rank_bounded {α : Type} (rank : α → Nat) (height : Nat)
    (bounded : ∀ x, rank x ≤ height) (values : List α) :
    tableRank rank values ≤ values.length * height := by
  induction values with
  | nil => simp [tableRank]
  | cons x xs ih =>
    have hx := bounded x
    simp only [tableRank, List.length_cons, Nat.succ_mul]
    omega

/-- A finite relation is a Boolean table over its admitted tuple universe. -/
def booleanRank : {n : Nat} → (Fin n → Bool) → Nat
  | 0, _ => 0
  | n + 1, f => (if f 0 then 1 else 0) + booleanRank (fun i : Fin n => f i.succ)

theorem boolean_rank_bounded {n : Nat} (f : Fin n → Bool) :
    booleanRank f ≤ n := by
  induction n with
  | zero => simp [booleanRank]
  | succ n ih =>
    have h := ih (fun i => f i.succ)
    simp only [booleanRank]
    split <;> omega

theorem boolean_rank_mono {n : Nat} (f g : Fin n → Bool)
    (included : ∀ i, f i = true → g i = true) :
    booleanRank f ≤ booleanRank g := by
  induction n with
  | zero => simp [booleanRank]
  | succ n ih =>
    have h := ih (fun i => f i.succ) (fun i => g i.succ)
      (fun i => included i.succ)
    have h0 := included 0
    simp only [booleanRank]
    cases hf : f 0 <;> cases hg : g 0 <;> simp [hf, hg] at * <;> omega

theorem boolean_rank_strict {n : Nat} (f g : Fin n → Bool)
    (included : ∀ i, f i = true → g i = true)
    (changed : ∃ i, f i = false ∧ g i = true) :
    booleanRank f < booleanRank g := by
  induction n with
  | zero => obtain ⟨i, _⟩ := changed; exact Fin.elim0 i
  | succ n ih =>
    obtain ⟨i, hi⟩ := changed
    cases i using Fin.cases with
    | zero =>
      have h := boolean_rank_mono (fun i : Fin n => f i.succ)
        (fun i => g i.succ) (fun i => included i.succ)
      simp only [booleanRank]
      simp [hi.1, hi.2]
      omega
    | succ i =>
      have h := ih (fun i => f i.succ) (fun i => g i.succ)
        (fun i => included i.succ) ⟨i, hi⟩
      have h0 := included 0
      simp only [booleanRank]
      cases hf : f 0 <;> cases hg : g 0 <;> simp [hf, hg] at * <;> omega

/-- An inflationary native relation step stabilizes within its tuple count.
    Monotonicity of each compiled primitive is a separate compiler premise. -/
theorem finite_relation_stabilizes {n : Nat}
    (step : (Fin n → Bool) → (Fin n → Bool)) (initial : Fin n → Bool)
    (inflationary : ∀ f i, f i = true → step f i = true) :
    ∃ k, k ≤ n ∧ step (iterateStep step initial k) = iterateStep step initial k := by
  apply bounded_rank_stabilizes step initial booleanRank n boolean_rank_bounded
  intro f different
  apply boolean_rank_strict f (step f) (inflationary f)
  apply Classical.byContradiction
  intro unchanged
  apply different
  funext i
  cases hf : f i <;> cases hg : step f i
  · rfl
  · exact False.elim (unchanged ⟨i, hf, hg⟩)
  · have := inflationary f i hf; simp [hg] at this
  · rfl

end Ascent
