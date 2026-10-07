-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderRouting
open Ascent.ProviderRouting
-- Identity is independent of value equality. Output retains original occurrences.
def coordinate (row : Nat × Nat) (_column : Nat) : Nat := row.2
example : scan coordinate [(2,7),(0,7)] [(10,7),(11,7),(10,7),(12,9)] =
    [(10,7),(11,7),(10,7)] := by decide
example : scan coordinate [(0,7),(0,9)] [(10,7),(11,9)] = [] := by decide
example : routed coordinate [(0,7)] (fun _ => true) [(10,7),(11,9)] = [(10,7)] := by decide
example : routed coordinate [(0,7)] (fun _ => false) [(10,7)] ≠
    scan coordinate [(0,7)] [(10,7)] := by decide
#print axioms selected_constraint
#print axioms routed_exact
#print axioms coordinate_bucket_exact
#print axioms stored_occurrence
#print axioms conflicting_duplicate
#print axioms constraints_permuted
#print axioms bucket_choice_independent
