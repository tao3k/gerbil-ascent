-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderEncoding
open Ascent.ProviderEncoding

example : encode (none : Option Bool) (false,true) ≠
    encode (some false) (false,true) := by decide
example : decode [false,true,false,true] = none := by rfl
example : decode [false] = none := by rfl
example : decode (encode (some false) (true,false)) =
    some (some false,(true,false)) := decode_encode _ _
example : orient true [1,2,3] ≠ orient false [1,2,3] := by decide
example : 2 ∈ orient true [1,2,3] := (orient_member _ _ _).mpr (by decide)
example : (orient true [1,2,3]).length = 3 := orient_count _ _

#print axioms decode_encode
#print axioms encode_injective
#print axioms scopes_disjoint
#print axioms encoded_member
#print axioms encoded_nodup
#print axioms encoded_count
#print axioms encoded_frontier
#print axioms root_plan_encoded_exact
#print axioms orient_member
#print axioms orient_count
#print axioms orient_nodup
