-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
namespace Ascent.ExecutionFeedback
variable {Row : Type}
def Missing (actual expected : Row → Prop) (row : Row) := expected row ∧ ¬ actual row
def Extra (actual expected : Row → Prop) (row : Row) := actual row ∧ ¬ expected row
def Exact (actual expected : Row → Prop) := ∀ row, actual row ↔ expected row

theorem no_differences_iff_exact (actual expected : Row → Prop) :
    ((∀ row, ¬ Missing actual expected row) ∧ (∀ row, ¬ Extra actual expected row)) ↔ Exact actual expected := by
  classical
  constructor
  · rintro ⟨hm, he⟩ row
    constructor
    · intro ha
      exact Classical.byContradiction (fun hn => he row ⟨ha, hn⟩)
    · intro hw
      exact Classical.byContradiction (fun hn => hm row ⟨hw, hn⟩)
  · intro h
    exact ⟨fun row ⟨hw, hn⟩ => hn ((h row).mpr hw),
           fun row ⟨ha, hn⟩ => hn ((h row).mp ha)⟩

theorem mismatch_witness (actual expected : Row → Prop) (h : ¬ Exact actual expected) :
    ∃ row, Missing actual expected row ∨ Extra actual expected row := by
  classical
  apply Classical.byContradiction
  intro hn
  apply h
  apply (no_differences_iff_exact actual expected).mp
  exact ⟨fun row hm => hn ⟨row, Or.inl hm⟩, fun row he => hn ⟨row, Or.inr he⟩⟩

theorem differences_disjoint (actual expected : Row → Prop) (row : Row) :
    ¬ (Missing actual expected row ∧ Extra actual expected row) := by
  rintro ⟨⟨_, hn⟩, ⟨ha, _⟩⟩
  exact hn ha

-- The publication predicate includes completion and content binding explicitly.
-- It does not assert that a caller's expected relation specifies intended meaning.
def AdmittedMatch (bound complete : Prop) (actual expected : Row → Prop) :=
  bound ∧ complete ∧ Exact actual expected

theorem match_requires_binding (bound complete : Prop) (actual expected : Row → Prop)
    (h : AdmittedMatch bound complete actual expected) : bound := h.1

theorem match_requires_completion (bound complete : Prop) (actual expected : Row → Prop)
    (h : AdmittedMatch bound complete actual expected) : complete := h.2.1
end Ascent.ExecutionFeedback
