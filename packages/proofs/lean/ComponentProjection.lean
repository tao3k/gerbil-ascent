-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ComponentClosure
import RuleGraphClosure

/-! Project ground fact reads to relation edges and component dependencies.
This proves the semantic metadata contract; native Tarjan representation is
qualified separately, not assumed to be extracted sourceKey this theorem. -/
namespace Ascent.ComponentProjection
open ComponentClosure
variable {Key Value Component : Type}

def relationRules (rules : List (ComponentClosure.Rule (Key × Value))) :
    List (RuleGraphClosure.Rule Key) :=
  rules.map fun rule => ⟨[rule.head.1], rule.body.map fun fact => ⟨.atom, some fact.1⟩⟩

theorem reads_exact (rules : List (ComponentClosure.Rule (Key × Value))) (source target : Key) :
    RuleGraphClosure.ReadsInto (relationRules rules) source target ↔
      ∃ rule ∈ rules, rule.head.1 = target ∧ ∃ fact ∈ rule.body, fact.1 = source := by
  constructor
  · rintro ⟨plan, member, clause, clauseMember, _, sourceEq, headMember⟩
    obtain ⟨rule, ruleMember, equal⟩ := List.mem_map.mp member
    subst plan
    obtain ⟨fact, factMember, equal⟩ := List.mem_map.mp clauseMember
    subst clause
    exact ⟨rule, ruleMember, (List.mem_singleton.mp headMember).symm,
      fact, factMember, Option.some.inj sourceEq⟩
  · rintro ⟨rule, member, head, fact, factMember, sourceEq⟩
    refine ⟨⟨[rule.head.1], rule.body.map fun f => ⟨.atom, some f.1⟩⟩,
      List.mem_map.mpr ⟨rule, member, rfl⟩, ⟨.atom, some fact.1⟩,
      List.mem_map.mpr ⟨fact, factMember, rfl⟩, rfl, ?_, ?_⟩
    · exact congrArg some sourceEq
    · exact List.mem_singleton.mpr head.symm

theorem depends_exact (rules : List (ComponentClosure.Rule (Key × Value)))
    (owner : Key → Component) (source target : Component) :
    Depends rules (fun fact => owner fact.1) source target ↔
      ∃ sourceKey to, owner sourceKey = source ∧ owner to = target ∧
        RuleGraphClosure.ReadsInto (relationRules rules) sourceKey to := by
  constructor
  · rintro ⟨rule, member, head, fact, factMember, read⟩
    exact ⟨fact.1, rule.head.1, read, head,
      (reads_exact rules _ _).mpr ⟨rule, member, rfl, fact, factMember, rfl⟩⟩
  · rintro ⟨sourceKey, to, sourceEq, targetEq, read⟩
    obtain ⟨rule, member, head, fact, factMember, body⟩ := (reads_exact rules _ _).mp read
    exact ⟨rule, member, (congrArg owner head).trans targetEq, fact, factMember, (congrArg owner body).trans sourceEq⟩

/-- Absence of backward projected relation edges supplies the exact premise
needed by finite component closure, without a ground dependency assumption. -/
theorem topological_of_projection (rules : List (ComponentClosure.Rule (Key × Value)))
    (owner : Key → Component) (order : List Component) [DecidableEq Component]
    (forward : ∀ earlier later, earlier ∈ order → later ∈ order →
      order.idxOf earlier < order.idxOf later →
      ∀ sourceKey to, owner sourceKey = later → owner to = earlier →
        ¬ RuleGraphClosure.ReadsInto (relationRules rules) sourceKey to)
    (unique : order.Nodup) :
    Topological rules (fun fact => owner fact.1) order := by
  induction order with
  | nil => trivial
  | cons component rest ih =>
      refine ⟨?_, ih ?_ unique.tail⟩
      · intro later member dependency
        obtain ⟨sourceKey, to, fromEq, toEq, read⟩ :=
          (depends_exact rules owner later component).mp dependency
        have different : component ≠ later := fun equal => (List.nodup_cons.mp unique).1 (equal ▸ member)
        exact forward component later (by simp) (by simp [member])
          (by simp [List.idxOf_cons, different]) sourceKey to fromEq toEq read
      · intro earlier later earlierMember laterMember before sourceKey to fromEq toEq
        have notEarlier : component ≠ earlier := fun equal => (List.nodup_cons.mp unique).1 (equal ▸ earlierMember)
        have notLater : component ≠ later := fun equal => (List.nodup_cons.mp unique).1 (equal ▸ laterMember)
        exact forward earlier later (by simp [earlierMember]) (by simp [laterMember])
          (by simpa [List.idxOf_cons, notEarlier, notLater] using before)
          sourceKey to fromEq toEq
end Ascent.ComponentProjection
