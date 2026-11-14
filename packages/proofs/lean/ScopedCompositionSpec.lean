-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

namespace Ascent.ScopedComposition
variable {Group Scope Vertex : Type}
def Witness (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (g : Group) (scope : Scope) (s t : Vertex) :=
  candidate s t ∧ required g ∧ member g scope ∧ branch scope s t
def Covered (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (g : Group) (s t : Vertex) :=
  ∃ scope, Witness candidate required member branch g scope s t
def Missing (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (g : Group) (s t : Vertex) :=
  candidate s t ∧ required g ∧ ¬ Covered candidate required member branch g s t
def ScopedAnswer (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (s t : Vertex) :=
  candidate s t ∧ ¬ ∃ g, Missing candidate required member branch g s t
def Answer (candidate : Vertex → Vertex → Prop) (required : Group → Prop)
    (member : Group → Scope → Prop) (branch : Scope → Vertex → Vertex → Prop) (s t : Vertex) :=
  candidate s t ∧ ∀ g, required g → ∃ scope, member g scope ∧ branch scope s t

-- Stratified relational division is AND over required groups, OR over members.
theorem no_missing_iff_answer : ScopedAnswer candidate required member branch s t ↔
    Answer candidate required member branch s t := by
  classical
  constructor
  · rintro ⟨selected, noMissing⟩
    refine ⟨selected, fun g hg => ?_⟩
    apply Classical.byContradiction
    intro unsupported
    apply noMissing
    refine ⟨g,selected,hg,?_⟩
    rintro ⟨scope,_,_,hm,hb⟩
    exact unsupported ⟨scope,hm,hb⟩
  · rintro ⟨selected, supported⟩
    refine ⟨selected,?_⟩
    rintro ⟨g,_,hg,missing⟩
    rcases supported g hg with ⟨scope,hm,hb⟩
    exact missing ⟨scope,selected,hg,hm,hb⟩

theorem empty_group_reject (hg : required g) (empty : ∀ scope, ¬ member g scope) :
    ¬ Answer candidate required member branch s t := by
  rintro ⟨_,supported⟩
  rcases supported g hg with ⟨scope,hm,_⟩
  exact empty scope hm
theorem no_required_groups (none : ∀ g, ¬ required g) :
    Answer candidate required member branch s t ↔ candidate s t := by
  constructor
  · exact fun h => h.1
  · exact fun selected => ⟨selected,fun g hg => False.elim (none g hg)⟩
theorem branches_monotone (grow : ∀ scope s t, before scope s t → after scope s t)
    (h : Answer candidate required member before s t) : Answer candidate required member after s t := by
  refine ⟨h.1,fun g hg => ?_⟩
  rcases h.2 g hg with ⟨scope,hm,hb⟩
  exact ⟨scope,hm,grow scope s t hb⟩

end Ascent.ScopedComposition
