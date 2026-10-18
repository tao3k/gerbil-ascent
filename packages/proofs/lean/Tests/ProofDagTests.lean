-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProofDag
open Ascent.ProofDag
private def sourceCheck (row : Nat) := row == 1
private def ruleCheck (rows : List Nat) (row : Nat) := rows == [row - 1] && row > 1
example : verifyFrom sourceCheck ruleCheck [] [.source 1, .step 2 [0], .step 3 [1]] = some [1,2,3] := by decide
example : verifyFrom sourceCheck ruleCheck [] [.source 1, .step 2 [1]] = none := by decide
example : verifyFrom sourceCheck ruleCheck [] [.step 2 [0], .source 1] = none := by decide
example : verifyFrom sourceCheck ruleCheck [] [.source 0] = none := by decide
example : resolve [1,2,3] [2,0] = some [3,1] := by decide

#print axioms verified_roots_sound
#print axioms derivable_in_closed
