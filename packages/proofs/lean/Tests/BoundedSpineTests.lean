/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-/
import BoundedSpine
open Ascent.BoundedSpine Spine
example : boundedLength 0 nil = some 0 := by decide
example : boundedLength 2 (cons (cons nil)) = some 2 := by decide
example : boundedLength 1 (cons (cons nil)) = none := by decide
example : boundedLength 2 (cons improper) = none := by decide
example : advances 1 (cons (cons improper)) = 1 := by decide
