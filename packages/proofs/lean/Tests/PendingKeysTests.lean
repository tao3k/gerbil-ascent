-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PendingKeys
open Ascent.PendingKeys

def ledger : Ledger Bool Nat := replay empty [(false,7),(true,5),(false,2)]
example : ledger.events = [false,true,false] := by decide
example : ledger.table false = some 2 := by decide
example : ledger.table true = some 5 := by decide
example : materialized ledger (false,2) := by unfold materialized; decide
example : ¬ materialized ledger (false,7) := by unfold materialized; decide
-- Dropping a pending key loses its final row even with a correct table.
example : ¬ materialized (⟨ledger.table,[true]⟩ : Ledger Bool Nat) (false,2) := by unfold materialized; decide
#print axioms empty_covered
#print axioms write_covered
#print axioms replay_covered
#print axioms materialization_exact
#print axioms materialization_unique
#print axioms repeated_key_final
#print axioms write_untouched
