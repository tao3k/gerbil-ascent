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

/-- Pointwise rank order is preserved by summing a finite function table. -/
theorem function_table_rank_mono {α β : Type} (rank : β → Nat)
    (f g : α → β) (domain : List α)
    (ordered : ∀ x, x ∈ domain → rank (f x) ≤ rank (g x)) :
    tableRank rank (domain.map f) ≤ tableRank rank (domain.map g) := by
  induction domain with
  | nil => simp [tableRank]
  | cons x xs ih =>
    have head := ordered x (by simp)
    have tail := ih (fun y hy => ordered y (by simp [hy]))
    simp only [List.map_cons, tableRank]
    omega

/-- A changed point in a monotone finite function table increases its rank. -/
theorem function_table_rank_strict {α β : Type} (rank : β → Nat)
    (f g : α → β) (domain : List α)
    (ordered : ∀ x, x ∈ domain → rank (f x) ≤ rank (g x))
    (changed : ∃ x, x ∈ domain ∧ rank (f x) < rank (g x)) :
    tableRank rank (domain.map f) < tableRank rank (domain.map g) := by
  induction domain with
  | nil => obtain ⟨x, hx, _⟩ := changed; simp at hx
  | cons x xs ih =>
    have head := ordered x (by simp)
    have tailOrder : ∀ y, y ∈ xs → rank (f y) ≤ rank (g y) :=
      fun y hy => ordered y (by simp [hy])
    obtain ⟨y, hy, hstrict⟩ := changed
    rcases List.mem_cons.mp hy with heq | hmem
    · subst y
      have tail := function_table_rank_mono rank f g xs tailOrder
      simp only [List.map_cons, tableRank]
      omega
    · have tail := ih tailOrder ⟨y, hmem, hstrict⟩
      simp only [List.map_cons, tableRank]
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

/-- A monotone step iterated from bottom produces an ascending orbit. -/
theorem bottom_orbit_ascending {α : Type} (le : α → α → Prop)
    (step : α → α) (bottom : α)
    (least : ∀ x, le bottom x)
    (mono : ∀ x y, le x y → le (step x) (step y)) (n : Nat) :
    le (iterateStep step bottom n) (iterateStep step bottom (n + 1)) := by
  induction n with
  | zero => exact least (step bottom)
  | succ n ih =>
    exact mono (iterateStep step bottom n) (iterateStep step bottom (n + 1)) ih

/-- Once a Kleene orbit is stationary, every later iterate is identical. -/
theorem stationary_tail {α : Type} (step : α → α) (initial : α) (n : Nat)
    (fixed : step (iterateStep step initial n) = iterateStep step initial n)
    (extra : Nat) :
    iterateStep step initial (n + extra) = iterateStep step initial n := by
  induction extra with
  | zero => simp
  | succ extra ih =>
    change step (iterateStep step initial (n + extra)) = iterateStep step initial n
    rw [ih]
    exact fixed

/-- Monotone iteration from bottom need not be globally inflationary. Only
    strict rank growth on its own orbit is required for full-height unrolling. -/
theorem bounded_orbit_height_fixed {α : Type} (step : α → α) (initial : α)
    (rank : α → Nat) (height : Nat)
    (bounded : ∀ n, rank (iterateStep step initial n) ≤ height)
    (progress : ∀ n, step (iterateStep step initial n) ≠ iterateStep step initial n →
      rank (iterateStep step initial n) < rank (iterateStep step initial (n + 1))) :
    step (iterateStep step initial height) = iterateStep step initial height := by
  have stationary : ∃ n, n ≤ height ∧
      step (iterateStep step initial n) = iterateStep step initial n := by
    apply Classical.byContradiction
    intro h
    have moving : ∀ n, n ≤ height →
        step (iterateStep step initial n) ≠ iterateStep step initial n := by
      intro n hn heq
      exact h ⟨n, hn, heq⟩
    have climbing : ∀ n, n ≤ height + 1 → n ≤ rank (iterateStep step initial n) := by
      intro n
      induction n with
      | zero => intro _; omega
      | succ n ih =>
        intro hn
        have old := ih (by omega)
        have incr := progress n (moving n (by omega))
        omega
    have lower := climbing (height + 1) (by omega)
    have upper := bounded (height + 1)
    omega
  obtain ⟨n, hn, hfixed⟩ := stationary
  have tail := stationary_tail step initial n hfixed (height - n)
  have index : n + (height - n) = height := by omega
  rw [index] at tail
  rw [tail]
  exact hfixed

/-- Every approximation from bottom is below every fixed point. Together
    with full-height stationarity this establishes leastness, without comparing
    runtime function identities or sampling only observed arguments. -/
theorem bottom_iterate_le_fixed {α : Type} (le : α → α → Prop)
    (step : α → α) (bottom value : α)
    (least : ∀ x, le bottom x)
    (mono : ∀ x y, le x y → le (step x) (step y))
    (fixed : step value = value) (n : Nat) :
    le (iterateStep step bottom n) value := by
  induction n with
  | zero => exact least value
  | succ n ih =>
    simpa only [iterateStep, fixed] using mono (iterateStep step bottom n) value ih

/-- Combines full-height stationarity and leastness. The caller must supply
    bounded rank and strict progress for the admitted semantics, rather than
    treating a runtime budget or a sampled function table as that proof. -/
theorem bounded_bottom_least_fixed {α : Type} (le : α → α → Prop)
    (step : α → α) (bottom : α) (rank : α → Nat) (height : Nat)
    (least : ∀ x, le bottom x)
    (mono : ∀ x y, le x y → le (step x) (step y))
    (bounded : ∀ n, rank (iterateStep step bottom n) ≤ height)
    (progress : ∀ n, step (iterateStep step bottom n) ≠ iterateStep step bottom n →
      rank (iterateStep step bottom n) < rank (iterateStep step bottom (n + 1))) :
    step (iterateStep step bottom height) = iterateStep step bottom height ∧
      ∀ value, step value = value → le (iterateStep step bottom height) value := by
  constructor
  · exact bounded_orbit_height_fixed step bottom rank height bounded progress
  · intro value fixed
    exact bottom_iterate_le_fixed le step bottom value least mono fixed height

end Ascent
