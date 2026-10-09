-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import NumericReduction
open Ascent.NumericReduction
example : reduce .sum [some (-8), some 3, some 5] = some 0 := by decide
example : reduce .min [some 8, some 3, some 5] = some 3 := by decide
example : reduce .max [some (-8), some (-3), some (-5)] = some (-3) := by decide
example : reduce .min [some 0] = some 0 := by decide
example : reduce .sum [some 8, none, some 2] = none := by decide
example : reduce .min [none, some 2] = none := by decide
example : reduce .max [some 2, none] = none := by decide
example : reduce .sum [some (2^100), some (-(2^100))] = some 0 := by decide
