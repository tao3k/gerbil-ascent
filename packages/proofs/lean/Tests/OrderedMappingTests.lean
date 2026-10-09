-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import OrderedMapping
open Ascent.OrderedMapping
example : lookup 0 [(0, 7), (1, 8), (0, 9), (0, 7)] = [7, 9, 7] := by decide
example : lookup 2 [(0, 7), (1, 8)] = [] := by decide
example : [0, 1, 0].flatMap (fun key => lookup key [(0, 7), (1, 8), (0, 9)]) =
    [7, 9, 8, 7, 9] := by decide
example : prependBucket 0 [(0, 7), (0, 9)] [] ≠ scan 0 [(0, 7), (0, 9)] := by decide
example : lookup 0 [(0, 7), (0, 7)] ≠ [7] := by decide
