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
