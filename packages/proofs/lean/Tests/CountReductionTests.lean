-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import CountReduction
open Ascent.CountReduction
example : countFold 0 [] = 0 := rfl
example : countFold 0 [false, true, false, true] = 2 := by decide
example : countFold 7 [false, true, false, true] = 9 := by decide
example : countFold 0 [true, true, true] = 3 := by decide
example : countFold 3 [false, false] = 3 := rfl
