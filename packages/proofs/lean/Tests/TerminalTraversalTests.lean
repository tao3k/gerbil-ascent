/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-/
import TerminalTraversal
open Ascent.TerminalTraversal
example : trace false [true, false] = [] := by decide
example : trace true [true, true] = [true, true] := by decide
example : trace true [false, true, true] = [false] := by decide
example : trace true [true, false, true] = [true, false] := by decide
example : trace true ([true, false] ++ [true, false]) = [true, false] := by decide
