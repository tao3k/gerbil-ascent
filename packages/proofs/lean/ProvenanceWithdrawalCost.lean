-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Init.Omega

/-! A conditional source-charge ledger for the unary, non-rederiving
benchmark fixture. The native independent closure audit establishes the
fixture preconditions. This is not extraction of the Scheme evaluator. -/
namespace Ascent.WithdrawalCost

structure Ledger where
  edges : Nat
  premises : Nat
  affected : Nat
  dependentOccurrences : Nat
  roots : Nat

def phases (c : Ledger) : List Nat :=
  [c.edges, c.edges + c.premises,
   c.affected + c.dependentOccurrences, c.affected,
   c.edges + c.dependentOccurrences, c.roots]

def total (c : Ledger) : Nat :=
  3*c.edges + c.premises + 2*c.affected +
    2*c.dependentOccurrences + c.roots

theorem charge_sum (c : Ledger) : (phases c).sum = total c := by
  simp [phases, List.sum, total]
  omega

/-- Source probe! increments first and rejects exactly when steps > limit.
The ledger models a completed attempted cut. The caller's actual rollback
semantics are checked separately by the native test. -/
def accepts (charges budget : Nat) : Bool := decide (charges ≤ budget)

theorem exact_budget (c : Ledger) : accepts (total c) (total c) = true := by
  simp [accepts]

theorem one_short_rejected (c : Ledger) (positive : 0 < total c) :
    accepts (total c) (total c - 1) = false := by
  simp [accepts]
  omega

theorem duplicate_fixture : total ⟨258, 2, 2, 2, 1⟩ = 785 := by decide
theorem wide_fixture : total ⟨768, 512, 256, 256, 256⟩ = 4096 := by decide
theorem small_fixture : total ⟨3, 2, 2, 2, 1⟩ = 20 := by decide

/-- A more complete charge definition need not exceed an older algorithm's
count: the older implementation traverses more edges for this fixture. -/
theorem relative_count_is_not_a_completeness_oracle :
    total ⟨258, 2, 2, 2, 1⟩ < 4*258 := by decide

end Ascent.WithdrawalCost
