/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-/
import SourceOccurrences
open Ascent.SourceOccurrences
example : withdraw [10, 10, 20] [1] = [10, 20] := by decide
example : withdraw (withdraw [10, 10, 20] [1]) [1] = [20] := by decide
example : withdraw [10, 10, 20] [1, 2] = [20] := by decide
example : withdraw [10, 20] [2] = [10] := by decide
example : withdraw (withdraw [10, 10, 20] [1]) [1] ≠ [10] := by decide
