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

-- Batch direction, absence, duplicate occurrences and encoded keys are observable.
example : buildBuckets Prod.snd [(10,7),(11,7),(10,7),(12,9)] 7 =
    [(10,7),(11,7),(10,7)] := by decide
example : prependBatch Prod.snd (buildBuckets Prod.snd [(10,7),(12,9)])
    [(11,7),(13,7)] 7 = [(13,7),(11,7),(10,7)] := by decide
example : replayBuckets Prod.snd [[(11,7),(13,7)],[],[(14,7),(15,9)]]
    (buildBuckets Prod.snd [(10,7)]) 7 = [(14,7),(13,7),(11,7),(10,7)] := by decide
example : buildBuckets (fun row : Nat × Nat => row.2 % 2) [(10,7),(12,9)] (7 % 2) ≠
    keyScan Prod.snd 7 [(10,7),(12,9)] := by decide
example : buildBuckets Prod.snd [(10,7),(11,7)] 8 = [] := by decide
#print axioms prepend_batch_exact
#print axioms build_buckets_exact
#print axioms extend_buckets_exact
#print axioms replay_buckets_exact
#print axioms encoded_build_exact
#print axioms built_candidate_routing_exact

example : (enumerateBuckets (buildBuckets Prod.snd [(10,7),(11,7),(10,7),(12,9)])
    [9,7]).count (10,7) = 2 := by decide
-- Equal set membership is insufficient: repeated ReadAll keys overcount rows.
example : (enumerateBuckets (buildBuckets Prod.snd [(10,7),(11,7)])
    [7,7]).count (10,7) = 2 := by decide
example : (enumerateBuckets (buildBuckets Prod.snd [(10,7),(12,9)])
    [7]).count (12,9) = 0 := by decide
#print axioms key_scan_count
#print axioms build_read_all_count
#print axioms complete_read_all_count
#print axioms replay_read_all_count

-- Forward gaps use the successor cursor; fallback preserves arbitrary layouts.
example : compileSteps 0 [0, 3, 7] = [0, 2, 3] := by decide
example : recoverColumns 0 [0, 2, 3] = [0, 3, 7] := by decide
-- Treating the preceding column, rather than its successor, as the cursor is wrong.
example : recoverColumns 0 [0, 3, 4] ≠ [0, 3, 7] := by decide
example : orderedCheck 0 [0, 2, 2] = false := by decide
example : orderedCheck 0 [3, 0] = false := by decide
example : dispatchedKey [false, true, false] [0, 1, 2] =
    [some false, some true, some false] := by decide
example : dispatchedKey [10, 11, 12] [2, 0, 2] =
    [some 12, some 10, some 12] := by decide
example : dispatchedKey ([] : List Nat) [] = [] := by decide
example : dispatchedKey [10, 11] [0, 7] = [some 10, none] := by decide
example : replayBuckets (fun row : List Nat => cursorKey row (compileSteps 0 [0, 2]))
    [[[1, 8, 3], [1, 9, 3]], [], [[1, 7, 3]]]
    (buildBuckets (fun row : List Nat => cursorKey row (compileSteps 0 [0, 2]))
      [[1, 8, 3], [2, 8, 3]]) [some 1, some 3] =
    [[1, 7, 3], [1, 9, 3], [1, 8, 3], [1, 8, 3]] := by decide
#print axioms compiled_columns_exact
#print axioms cursor_columns_exact
#print axioms stepped_projection_exact
#print axioms stepped_build_exact
#print axioms stepped_history_exact
#print axioms ordered_check_iff
#print axioms dispatched_projection_exact
#print axioms column_key_missing_iff
#print axioms admitted_projection_present
