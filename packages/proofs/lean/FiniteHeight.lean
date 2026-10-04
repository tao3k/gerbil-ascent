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

end Ascent
