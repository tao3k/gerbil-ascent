/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
-/
import StableSourceSupport
open Ascent.StableSourceSupport
example : keep [(10, 1), (10, 2), (20, 3)] [1] = [(10, 2), (20, 3)] := by decide
example : keep (keep [(10, 1), (10, 2), (20, 3)] [1]) [2] = [(20, 3)] := by decide
example : keep [(10, 1), (10, 2), (20, 3)] [1, 2] = [(20, 3)] := by decide
example : keep [(10, 1), (10, 2), (20, 3)] [2] = [(10, 1), (20, 3)] := by decide
