-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import FiniteFlowPacking
open Ascent.FiniteFlowPacking

-- Adjacent fact ordinals across a byte boundary do not alias.
example : address 3 7 ≠ address 3 8 := by decide
example : address 3 8 ≠ address 4 8 := by decide
-- Propagation suppresses stored and blocked bits independently.
example : freshByte 255 15 240 = 0 := by decide
example : freshByte 255 15 16 = 224 := by decide
example : freshByte 128 0 0 = 128 := by decide
example : ((512 + 7) / 8) * 2048 = 131072 := by decide
#print axioms address_injective
#print axioms bit_in_byte
#print axioms fresh_bit
#print axioms fresh_disjoint
#print axioms merged_difference_exact
#print axioms target_blocker_removes_fresh
#print axioms payload_bound
