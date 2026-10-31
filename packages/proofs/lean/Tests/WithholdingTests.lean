-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Withholding
open Ascent.Withholding
example : Cut (fun _ : Nat => True) (fun x => x = 0) 1 := by unfold Cut; decide
example : ¬ Cut (fun _ : Nat => True) (fun x => x = 0) 0 := by unfold Cut; decide
-- Two locally safe groundings conflict globally: head 0 supports head 1.
example : ¬ (∀ x : Nat, (x = 0 ∨ x = 2) → ¬ (x = 0 ∨ x = 1)) := by
  intro h; exact h 0 (Or.inl rfl) (Or.inl rfl)
