-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ExecutionFeedback
open Ascent.ExecutionFeedback
example : Missing (fun x : Nat => x = 1) (fun x => x = 1 ∨ x = 2) 2 := by unfold Missing; decide
example : Extra (fun x : Nat => x = 1 ∨ x = 2) (fun x => x = 1) 2 := by unfold Extra; decide
example (actual expected : Nat → Prop) : ¬ AdmittedMatch False True actual expected := fun h => h.1
example (actual expected : Nat → Prop) : ¬ AdmittedMatch True False actual expected := fun h => h.2.1
example : Exact (fun x : Nat => x = 1 ∨ x = 1) (fun x => x = 1) := by simp [Exact]
