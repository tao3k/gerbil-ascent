-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderFrontier

/-! Synchronous positive Set iteration with a monotone concrete view.
Initial execution is full; later rounds read exact concrete deltas.
Not native extraction or the general abstract-lattice gamma/injection theorem. -/
namespace Ascent.SemiNaive
open ProviderFrontier

structure Rule (Key Env Row : Type) where
  keys : List Key
  seed : Env
  emit : Env → Row

variable {Key Env Row : Type}

def consequences (rules : List (Rule Key Env Row))
    (relations : Key → Env → Env → Prop) (row : Row) : Prop :=
  ∃ rule ∈ rules, output (body relations rule.keys rule.seed) rule.emit row

def freshConsequences (rules : List (Rule Key Env Row))
    (old next : Key → Env → Env → Prop) (row : Row) : Prop :=
  ∃ rule ∈ rules, output (pivots old next rule.keys rule.seed) rule.emit row

theorem consequences_partition (rules : List (Rule Key Env Row))
    (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (row : Row) :
    consequences rules next row ↔
      consequences rules old row ∨ freshConsequences rules old next row := by
  constructor
  · rintro ⟨rule, member, derivation⟩
    rcases (projected_partition old next grows rule.keys rule.seed rule.emit row).mp
      derivation with prior | fresh
    · exact Or.inl ⟨rule, member, prior⟩
    · exact Or.inr ⟨rule, member, fresh⟩
  · intro admitted
    rcases admitted with ⟨rule, member, derivation⟩ | ⟨rule, member, derivation⟩
    · exact ⟨rule, member, (projected_partition old next grows
        rule.keys rule.seed rule.emit row).mpr (Or.inl derivation)⟩
    · exact ⟨rule, member, (projected_partition old next grows
        rule.keys rule.seed rule.emit row).mpr (Or.inr derivation)⟩

abbrev Database (Row : Type) := Row → Prop
abbrev View (Key Env Row : Type) := Database Row → Key → Env → Env → Prop

def ViewMonotone (view : View Key Env Row) : Prop :=
  ∀ before after, (∀ row, before row → after row) →
    ∀ key input output, view before key input output → view after key input output

def fullStep (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (known : Database Row) : Database Row :=
  fun row => known row ∨ consequences rules (view known) row

def pivotStep (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (old known : Database Row) : Database Row :=
  fun row => known row ∨ freshConsequences rules (view old) (view known) row

def naive (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (initial : Database Row) : Nat → Database Row
  | 0 => initial
  | n + 1 => fullStep rules view (naive rules view initial n)

/-- Consecutive concrete snapshots; no mailbox or scheduler replica. -/
def semiNaive (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (initial : Database Row) : Nat → Database Row × Database Row
  | 0 => (initial, fullStep rules view initial)
  | n + 1 =>
      let prior := semiNaive rules view initial n
      (prior.2, pivotStep rules view prior.1 prior.2)

/-- All-old heads were included by the preceding consequence step.
The history premise is derived; completion is not assumed. -/
theorem pivot_after_full (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view) (old : Database Row) :
    pivotStep rules view old (fullStep rules view old) =
      fullStep rules view (fullStep rules view old) := by
  funext row
  apply propext
  have grows := monotone old (fullStep rules view old) (fun _ h => Or.inl h)
  constructor
  · intro admitted
    rcases admitted with known | fresh
    · exact Or.inl known
    · exact Or.inr ((consequences_partition rules _ _ grows row).mpr (Or.inr fresh))
  · intro admitted
    rcases admitted with known | full
    · exact Or.inl known
    · rcases (consequences_partition rules _ _ grows row).mp full with prior | fresh
      · exact Or.inl (Or.inr prior)
      · exact Or.inr fresh

/-- Every natural-number round agrees; no cutoff or completed-solve premise. -/
theorem iterations_equal (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view)
    (initial : Database Row) (n : Nat) :
    semiNaive rules view initial n =
      (naive rules view initial n, naive rules view initial (n + 1)) := by
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [semiNaive, ih, naive]
      rw [pivot_after_full rules view monotone]

end Ascent.SemiNaive
