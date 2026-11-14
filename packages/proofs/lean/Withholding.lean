-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
namespace Ascent.Withholding
variable {Fact : Type}
def Cut (source removed : Fact → Prop) (f : Fact) := source f ∧ ¬ removed f

theorem no_invention (source removed : Fact → Prop) (f : Fact)
    (h : Cut source removed f) : source f := h.1

theorem selected_absent (source removed : Fact → Prop) (f : Fact)
    (h : removed f) : ¬ Cut source removed f := fun hc => hc.2 h

theorem unselected_preserved (source removed : Fact → Prop) (f : Fact)
    (hs : source f) (hr : ¬ removed f) : Cut source removed f := ⟨hs, hr⟩

theorem witnesses_preserved (source removed witnesses : Fact → Prop)
    (observed : ∀ f, witnesses f → source f)
    (disjoint : ∀ f, witnesses f → ¬ removed f) :
    ∀ f, witnesses f → Cut source removed f := fun f hp => ⟨observed f hp, disjoint f hp⟩

-- Required global condition: local per-grounding checks do not imply this.
theorem protection_iff_disjoint (source removed witnesses : Fact → Prop)
    (observed : ∀ f, witnesses f → source f) :
    (∀ f, witnesses f → Cut source removed f) ↔ (∀ f, witnesses f → ¬ removed f) :=
  ⟨fun h f hp => (h f hp).2, fun h => witnesses_preserved source removed witnesses observed h⟩

theorem batch_order_independent (source first second : Fact → Prop) (f : Fact) :
    Cut (Cut source first) second f ↔ Cut (Cut source second) first f := by
  constructor
  · rintro ⟨⟨hs, hf⟩, hn⟩; exact ⟨⟨hs, hn⟩, hf⟩
  · rintro ⟨⟨hs, hn⟩, hf⟩; exact ⟨⟨hs, hf⟩, hn⟩
end Ascent.Withholding
