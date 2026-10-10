-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderRouting
open Ascent.ProviderRouting

-- Actual nested construction and insertion, including duplicate-valued rows.
def trieCoordinate (row : List Bool) (i : Nat) : Bool := row[i]?.getD false
def trieRows : List (List Bool) := [[false, true], [true, false], [false, true]]
example : trieRead [false, true] 2 [false] (trieBuild 2 trieCoordinate trieRows) =
    [[false, true], [false, true]] := by decide
example : trieRead [true, false] 2 [false, true] (trieBuild 2 trieCoordinate trieRows) =
    [[false, true], [false, true]] := by decide
example : trieRead [false, true] 2 [true, true] (trieBuild 2 trieCoordinate trieRows) = [] := by decide
example : trieRead [false, true] 2 [false, true, false]
    (trieBuild 2 trieCoordinate trieRows) = [] := by decide
example : trieRead [false, true] 2 [false]
    (triePrepend 2 trieCoordinate [[false, true], [false, false]]
      (trieBuild 2 trieCoordinate trieRows)) =
    [[false, false], [false, true], [false, true], [false, true]] := by decide
-- Repeated or missing child enumeration cannot satisfy occurrence coverage.
example : ¬(trieCollect [false, false, true] 2 (trieBuild 2 trieCoordinate trieRows)).Perm
    trieRows := by decide
example : ¬(trieCollect [true] 2 (trieBuild 2 trieCoordinate trieRows)).Perm trieRows := by decide
example : trieInsert 2 trieCoordinate [false, true] (trieBuild 2 trieCoordinate trieRows) =
    trieBuild 2 trieCoordinate ([false, true] :: trieRows) :=
  trie_insert_build _ _ _ _
example :
    (restoreRecords (trieRead [true, false] 2 [false]
      (trieNumberedReplay 2 (fun record : Nat × List Bool => trieCoordinate record.2)
        (trieRows.length + 1) [[], [[false, true]]]
        (trieBuild 2 (fun record : Nat × List Bool => trieCoordinate record.2)
          (numberRows 1 trieRows.reverse).reverse)))).map Prod.snd =
      [[false, true], [false, true], [false, true]] := by
  have restored := trie_numbered_prefix_restore 2 trieCoordinate trieRows
    [[], [[false, true]]] [true, false] [false] (by decide)
    (by intro record _ i _; cases trieCoordinate record.2 i <;> simp)
  simpa [replayRows, trieRows, List.filter_cons, prefixSelected, trieCoordinate] using restored
#print axioms trie_insert_build
#print axioms trie_prepend_build
#print axioms trie_replay_build
#print axioms trie_collect_build_count
#print axioms trie_collect_build_perm
#print axioms trie_read_build_perm
#print axioms prefix_selected_projection
#print axioms trie_numbered_replay_build
#print axioms trie_numbered_prefix_restore
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

-- Repeated field values retain distinct insertion occurrences and ordinals.
def occurrenceTree : RecordTree Nat :=
  .fork (.leaf [(2, 7)]) (.fork (.leaf [(1, 9)]) (.leaf [(3, 7)]))
example : collectRecords occurrenceTree [(0, 99)] =
    [(3, 7), (1, 9), (2, 7), (0, 99)] := by decide
example : leafCopies occurrenceTree = 3 := by decide
example : subtreeCopies occurrenceTree = 8 := by decide
example : (restoreRecords [(2, 7), (1, 9), (3, 7)]).map Prod.snd = [7, 7, 9] := by
  have ordered : ([(3, 7), (2, 7), (1, 9)] : List (Nat × Nat)).Pairwise
      (fun a b => b.1 < a.1) := by decide
  have perm : ([(2, 7), (1, 9), (3, 7)] : List (Nat × Nat)).Perm [(3, 7), (2, 7), (1, 9)] := by decide
  rw [restored_occurrences_exact _ _ ordered perm]
  rfl
example : (restoreRecords [(2, 7), (1, 9)]).map Prod.snd ≠ [7, 7, 9] := by
  intro equal
  have lengths := congrArg List.length equal
  simp [restoreRecords] at lengths
-- Ascending ordinals reverse the retained order, even though membership agrees.
example : ([(1, 9), (2, 7), (3, 7)] : List (Nat × Nat)).map Prod.snd ≠ [7, 7, 9] := by decide
-- Duplicate ordinal labels destroy the strict-order admission contract.
example : ¬ ([(1, 7), (1, 9)] : List (Nat × Nat)).Pairwise
    (fun a b => b.1 < a.1) := by decide
example : (replayNumbered 3 [(2, 7), (1, 9)] [[7, 7], [], [8]]).2 =
    [(5, 8), (4, 7), (3, 7), (2, 7), (1, 9)] := by decide
#print axioms collect_tail_exact
#print axioms leaf_copies_exact
#print axioms collection_copies_le
#print axioms numbered_values_exact
#print axioms numbered_lower_bound
#print axioms numbered_upper_bound
#print axioms numbered_strict_order
#print axioms extended_ordinal_order
#print axioms extended_ordinal_bound
#print axioms numbered_history_order
#print axioms numbered_history_values
#print axioms strict_ordinal_unique
#print axioms native_strict_sort_exact
#print axioms restored_occurrences_exact
#print axioms constructed_ordinal_restore
#print axioms constructed_history_restore
example : (restoreRecords [(2, 7), (3, 7)]).map Prod.snd = [7, 7] := by
  exact constructed_prefix_restore [7, 7, 9] [] (fun n : Nat => n == 7)
    [(2, 7), (3, 7)] (by decide)
#print axioms constructed_prefix_restore
