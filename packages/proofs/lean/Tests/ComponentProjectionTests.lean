-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentProjection
namespace Ascent.ComponentProjectionTests
open ComponentClosure ComponentProjection

def rules : List (ComponentClosure.Rule (Nat × Nat)) :=
  [⟨[(0, 0)], (1, 0)⟩, ⟨[(1, 0)], (2, 0)⟩]
example : RuleGraphClosure.ReadsInto (relationRules rules) 0 1 := by
  simp [RuleGraphClosure.ReadsInto, RuleGraphClosure.ClauseKind.reads, relationRules, rules]
/-- Direct metadata excludes transitive edges; readiness requires immediate predecessors. -/
example : ¬ RuleGraphClosure.ReadsInto (relationRules rules) 0 2 := by
  simp [RuleGraphClosure.ReadsInto, RuleGraphClosure.ClauseKind.reads, relationRules, rules]
example : Depends rules (fun fact => fact.1) 1 2 := by
  simp [Depends, rules]
/-- Omitting a required edge changes the dependency contract. -/
example : ¬ (Depends rules (fun fact => fact.1) 1 2 ↔ False) := by
  simp [Depends, rules]
example : ¬ Topological rules (fun fact => fact.1) [2, 1, 0] := by
  simp [Topological, Depends, rules]
example : Topological rules (fun fact => fact.1) [0, 1, 2] := by
  apply topological_of_projection rules id [0, 1, 2]
  · intro earlier later _ _ before sourceKey target sourceEq targetEq read
    change sourceKey = later at sourceEq
    change target = earlier at targetEq
    subst sourceKey
    subst target
    simp [RuleGraphClosure.ReadsInto, RuleGraphClosure.ClauseKind.reads, relationRules, rules] at read
    rcases read with ⟨head, body⟩ | ⟨head, body⟩
    all_goals subst earlier; subst later; revert before; decide
  · decide
#print axioms Ascent.ComponentProjection.reads_exact
#print axioms Ascent.ComponentProjection.depends_exact
#print axioms Ascent.ComponentProjection.topological_of_projection
end Ascent.ComponentProjectionTests
