/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
Z19 minimum-height certificate characterization. Native relaxation, source
identity and decoded rule/premise IDs remain representation obligations.
-/
import ComponentClosure
namespace Ascent.MinimumHeight
open ComponentClosure
variable {Fact : Type}
/-- A proof of height at most n. Raising the bound permits unequal child heights. -/
inductive Within (rules : List (Rule Fact)) (source : Database Fact) : Fact → Nat → Prop
  | seed {fact} : source fact → Within rules source fact 0
  | raise {fact n} : Within rules source fact n → Within rules source fact (n + 1)
  | fire {rule n} : rule ∈ rules →
      (∀ premise ∈ rule.body, Within rules source premise n) →
      Within rules source rule.head (n + 1)
/-- Missing annotations are infinity, never zero. Fixed-point inequalities
include all ground alternatives, not merely the first witness. -/
def Closed (rules : List (Rule Fact)) (source : Database Fact) (height : Fact → Option Nat) : Prop :=
  (∀ fact, source fact → height fact = some 0) ∧
  (∀ rule ∈ rules, ∀ n,
    (∀ premise ∈ rule.body, ∃ h, height premise = some h ∧ h ≤ n) →
    ∃ h, height rule.head = some h ∧ h ≤ n + 1)
theorem lower_bound (rules : List (Rule Fact)) (source : Database Fact)
    (height : Fact → Option Nat) (closed : Closed rules source height)
    {fact n} (proof : Within rules source fact n) :
    ∃ h, height fact = some h ∧ h ≤ n := by
  induction proof with
  | seed present => exact ⟨0, closed.1 _ present, Nat.le_refl 0⟩
  | raise _ ih =>
      obtain ⟨h, read, bound⟩ := ih
      exact ⟨h, read, by omega⟩
  | fire member _ ih => exact closed.2 _ member _ ih
/-- Attainment plus all-alternative closure certifies the exact minimum bound.
An unfounded cycle cannot satisfy attainment with a finite annotation. -/
theorem minimum (rules : List (Rule Fact)) (source : Database Fact)
    (height : Fact → Option Nat) (closed : Closed rules source height)
    (attained : ∀ fact h, height fact = some h → Within rules source fact h)
    {fact h} (read : height fact = some h) :
    Within rules source fact h ∧ ∀ n, Within rules source fact n → h ≤ n := by
  constructor
  · exact attained fact h read
  · intro n proof
    obtain ⟨value, found, bound⟩ := lower_bound rules source height closed proof
    have equal : value = h := Option.some.inj (found.symm.trans read)
    simpa [equal] using bound
end Ascent.MinimumHeight
