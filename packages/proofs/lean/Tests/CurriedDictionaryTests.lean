-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import CurriedDictionary
namespace Ascent.CurriedDictionaryTests
open ProviderRouting CurriedDictionary

def coordinate (row : List Bool) (i : Nat) : Bool := row[i]?.getD false
def rows : List (List Bool) :=
  [[false, false], [false, true], [true, false], [true, true], [false, true]]
def visit (path keys : List Bool) : List Bool :=
  if path = [false] then keys.reverse else keys
theorem visit_permuted (path keys : List Bool) : (visit path keys).Perm keys := by
  unfold visit
  split
  · exact List.reverse_perm _
  · exact List.Perm.refl _

-- Sibling dictionaries may independently reverse their own inventories.
example : ((buildNode 2 coordinate visit [] rows).2 false).1 = [true, false] := by decide
example : ((buildNode 2 coordinate visit [] rows).2 true).1 = [false, true] := by decide
example : (readNode 2 [false] (buildNode 2 coordinate visit [] rows)).Perm
    [[false, false], [false, true], [false, true]] := by decide
example : readNode 2 [false, false, true] (buildNode 2 coordinate visit [] rows) = [] := by decide
example : readNode 2 [false] (buildNode 2 coordinate visit [] ([] : List (List Bool))) = [] := by decide
example : (collectNode 2 (buildNode 2 coordinate visit [] rows)).Perm rows :=
  collect_build_perm _ _ _ visit_permuted _ _
example : ¬(collectNode 2 (buildNode 2 coordinate (fun _ keys => keys ++ keys) [] rows)).Perm rows := by decide
example : ¬(collectNode 2 (buildNode 2 coordinate (fun _ _ => []) [] rows)).Perm rows := by decide
example :
    (restoreRecords (readNode 2 [false]
      (buildNode 2 (fun record : Nat × List Bool => coordinate record.2) visit []
        (replayNumbered (rows.length + 1) (numberRows 1 rows.reverse).reverse
          [[], [[false, true]]]).2))).map Prod.snd =
      [[false, true], [false, false], [false, true], [false, true]] := by
  have restored := numbered_prefix_restore 2 coordinate visit visit_permuted rows
    [[], [[false, true]]] [false]
  simpa [replayRows, rows, List.filter_cons, prefixSelected, coordinate] using restored

#print axioms materialized_keys_membership
#print axioms materialized_keys_unique
#print axioms forget_build
#print axioms materialized_inventory
#print axioms collect_build_count
#print axioms collect_build_perm
#print axioms read_build_perm
#print axioms numbered_prefix_restore
end Ascent.CurriedDictionaryTests
