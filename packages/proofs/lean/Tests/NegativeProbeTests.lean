-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import StratifiedNegation
open Ascent.StratifiedNegation

example : negativeProbe 1 [true, false, false] = some (true, 0) := by decide
example : negativeProbe 1 [false, true] = none := by decide
example : negativeProbe 2 [false, true] = some (true, 0) := by decide
example : negativeProbe 2 [false, false] = none := by decide
example : negativeProbe 3 [false, false] = some (false, 0) := by decide
example : negativeProbe 0 [] = none := by decide
example : negativeProbe 1 [] = some (false, 0) := by decide
example (tail : List Bool) : negativeProbe 1 (true :: tail) = some (true, 0) :=
  negativeProbe_first_match tail 0
