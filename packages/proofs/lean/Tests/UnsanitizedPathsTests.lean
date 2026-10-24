-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import UnsanitizedPaths
open Ascent.UnsanitizedPaths
example : CleanPath (fun x y : Nat => x = 0 ∧ y = 2) (fun v => v ≠ 1) 0 2 :=
  .step (.refl (by decide)) ⟨rfl,rfl⟩ (by decide)
example (edge : Nat → Nat → Prop) : ¬ CleanPath edge (fun v => v ≠ 0) 0 2 := by
  intro h; exact (endpoints edge _ 0 2 h).1 rfl
example (edge : Nat → Nat → Prop) : ¬ CleanPath edge (fun v => v ≠ 2) 0 2 := by
  intro h; exact (endpoints edge _ 0 2 h).2 rfl
example : CleanPath (fun _ _ : Nat => False) (fun _ => True) 0 0 := .refl trivial
