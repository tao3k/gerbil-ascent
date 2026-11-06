-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import DerivationCounts
namespace Ascent.DerivationCountsTests
open DerivationCounts
example : annotation [[2,3],[2,2]] = 10 := by decide
example : annotation [[2],[2]] = 4 := by decide
example : annotation [] = 0 ∧ annotation [[]] = 1 := by decide
example : body [2,0,3] = 0 := by decide
example : (choices [[0,1],[4,5,6]]).length = 6 := by decide
example : rounds (fun n : Nat => 1 + n) 0 5 = 5 := by decide
example : rounds (fun n : Nat => 1 + n) 0 5 ≠ rounds (fun n => 1 + n) 0 6 := by decide
-- Accumulating old counts again fails even without recursion.
example : rounds (fun n : Nat => n + 2) 0 2 ≠ 2 := by decide
#print axioms length_branches
#print axioms body_counts_trees
#print axioms alternatives_count_trees
#print axioms repeated_body
#print axioms alternative_union
#print axioms stable_rounds
end Ascent.DerivationCountsTests
