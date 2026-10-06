-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderRectangles
namespace Ascent.ProviderRectanglesTests
open ProviderRectangles

def bridge : List (Rectangle Nat) := [⟨[0, 1], [2, 3]⟩]
example : expand bridge = [(0, 2), (0, 3), (1, 2), (1, 3)] := by decide
example : count bridge = 4 := by decide
example : ¬ count bridge ≤ 3 := by decide
example : lookup bridge 0 = [(0, 2), (0, 3)] := by decide
example : (expand bridge).Nodup := by decide
-- Descriptor count and logical fact count are different quantities.
example : bridge.length = 1 ∧ count bridge = 4 := by decide
-- Set membership alone fails to prevent overcounting duplicate rectangles.
example : count (bridge ++ bridge) = 8 ∧ ¬ (expand (bridge ++ bridge)).Nodup := by decide
-- Raw injected edges omit an implied bridge pair.
example : (0, 3) ∈ expand bridge ∧ (0, 3) ∉ [(1, 2)] := by decide
-- Empty and diagonal rectangles require no invented active members.
example : count [⟨[], [0, 1]⟩] = 0 := by decide
example : expand [⟨[0], [0]⟩] = [(0, 0)] := by decide

-- A min lattice can ascend in its abstract order while exact winner tuples
-- retract. Set-view monotonicity cannot be inferred from a lawful lattice join.
def winner (n : Nat) (p : Nat × Nat) : Prop := p = (0, n)
example : ¬ (∀ before after : Nat, after ≤ before →
    ∀ p, winner before p → winner after p) := by
  intro monotone
  exact (by simp [winner] : ¬ winner 2 (0, 5)) (monotone 5 2 (by decide) (0, 5) rfl)

#print axioms rectangle_length
#print axioms rectangle_member
#print axioms expansion_member
#print axioms count_exact
#print axioms map_pair_nodup
#print axioms rectangle_nodup
#print axioms expansion_nodup
#print axioms frontier_exact
#print axioms frontier_partition
#print axioms lookup_exact
#print axioms budget_exact
#print axioms duplicate_rectangle
end Ascent.ProviderRectanglesTests
