-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import CanonicalIndex
namespace Ascent.CanonicalIndexTests
open CanonicalIndex
-- Lexicographic three-column inventory, including incompatible singleton sets.
def inventory : List (List Nat) := [[0], [0,1], [0,1,2], [0,2], [1], [1,2], [2]]
example : canonical inventory [[2], [0,1], [0], [0,1]] = [[0], [0,1], [2]] := by decide
example : canonical inventory [] = [] := by decide
example : canonical inventory [[2], [0,1], [0]] =
    canonical inventory [[0], [0,1], [2]] := by decide
-- An encounter-order planner and an omission are both observably wrong.
example : ([[2], [0]] : List (List Nat)) ≠ [[0], [2]] := by decide
example : canonical inventory [[0], [2]] ≠ canonical inventory [[0]] := by decide
#print axioms membership
#print axioms same_demand_set
#print axioms encounter_order
#print axioms duplicates
#print axioms layout_identity
end Ascent.CanonicalIndexTests
