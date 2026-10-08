-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import IndexedPositiveTraversal

namespace Ascent.IndexedPositiveTraversalTests
open AtomicBinding PositiveSlots IndexedPositiveTraversal
#print axioms Ascent.IndexedPositiveTraversal.compiled_key_refines
#print axioms Ascent.IndexedPositiveTraversal.precompiled_indexed_pivot_refines
#print axioms Ascent.IndexedPositiveTraversal.row_partition
#print axioms Ascent.IndexedPositiveTraversal.new_output_indexed_pivot
#print axioms Ascent.IndexedPositiveTraversal.indexed_pivot_output_sound

def names : List Nat := [10]
def input : Env Bool := [(10, false)]
def dirty : Frame Bool := fun _ => false
/-- Selected columns keep their order and multiplicity; fresh cells are not
known prefix keys, even when a dirty vector contains a value there. -/
example : compiledVectorKey ([.variable 20, .variable 10, .literal true] : List (Term Bool))
    [2, 1, 2] names #v[false, true] = [some true, some false, some true] := by decide
example : compiledVectorKey ([.variable 20, .variable 10] : List (Term Bool))
    [0] names #v[false, true] ≠ envKey [.variable 20, .variable 10] [0] input := by decide
example : compiledVectorKey ([.variable 10] : List (Term Bool))
    [] names (#v[] : Vector Bool 0) = [] := by decide
#print axioms Ascent.IndexedPositiveTraversal.vector_action_value
#print axioms Ascent.IndexedPositiveTraversal.compiled_vector_key_refines
def second : Atom Bool :=
  ⟨[.variable 20, .variable 10, .variable 20, .literal false], [3, 1, 1],
   List.replicate 32 [false, false, false, false] ++ List.replicate 32 [true, false, true, false],
   List.replicate 32 [true, false, true, false], List.replicate 32 [false, false, false, false]⟩
def last : Atom Bool :=
  ⟨[.variable 30, .variable 20, .variable 30, .variable 10], [3, 1],
   List.replicate 32 [false, false, false, false] ++ List.replicate 32 [true, true, true, false],
   List.replicate 32 [true, true, true, false], List.replicate 32 [false, false, false, false]⟩
def body : List (Atom Bool) := [second, last]
def heads : List (Term Bool) := [.variable 10, .variable 20, .variable 30, .literal false]
def slotEmit (names : List Nat) (frame : Frame Bool) : List (List (Option Bool)) :=
  [observeSlots heads names frame, observeSlots heads names frame]
def envEmit (env : Env Bool) : List (List (Option Bool)) :=
  [observeHead heads env, observeHead heads env]

theorem rep : Represents names input dirty := by
  intro name; by_cases same : name = 10 <;> simp [names, input, lookup, slot, dirty, same]

theorem emits (names : List Nat) (env : Env Bool) (frame : Frame Bool)
    (represented : Represents names env frame) : slotEmit names frame = envEmit env := by
  simp only [slotEmit, envEmit, head_observations heads names env frame represented]

theorem admitted (pivot : Option Nat) : Admitted body pivot 0 names := by
  refine ⟨?_, ?_, ?_, ?_, trivial⟩
  · intro row member
    unfold lane at member
    split at member <;> simp_all [second]
    rcases member with rfl | rfl <;> rfl
  · intro env frame represented
    have value := represented 10
    have found : lookup 10 env = some (frame 0) := by simpa [names, slot] using value
    simp [KnownColumns, second, wanted, found]
  · intro row member
    unfold lane at member
    split at member <;> simp_all [last]
    rcases member with rfl | rfl <;> rfl
  · intro env frame represented
    have valueA := represented 10
    have valueB := represented 20
    have foundA : lookup 10 env = some (frame 0) := by
      simpa [second, names, compile, lower, slot] using valueA
    have foundB : lookup 20 env = some (frame 1) := by
      simpa [second, names, compile, lower, slot] using valueB
    simp [KnownColumns, last, wanted, foundA, foundB]

theorem exactDelta : DeltaExact body := by
  simp [DeltaExact, body, second, last]
  constructor <;> intro row <;> grind

example (pivot : Option Nat) :
    (runBody (compileBody body names).1 pivot 0 (compileBody body names).2 slotEmit dirty).1 =
      PositiveTraversal.reference (rawBody body pivot 0) envEmit input :=
  precompiled_indexed_pivot_refines body pivot 0 slotEmit envEmit emits names input dirty (admitted pivot) rep

example (pivot : Option Nat) : Represents names input (walk body pivot 0 names slotEmit dirty).2 :=
  indexed_reuse body pivot 0 names input slotEmit dirty rep

/-- Physical threshold: below 32 candidates scan unchanged; at 32 the
canonical ordered bucket filters even a repeated arbitrary column list. -/
example : selectedRows {second with allRows := List.replicate 31 [false, true, false, false]}
    none 0 names dirty = List.replicate 31 [false, true, false, false] := by decide
example : selectedRows {second with allRows := List.replicate 32 [false, true, false, false]}
    none 0 names dirty = [] := by decide
example : compiledKey second.terms second.columns names dirty = [some false, some false, some false] := by decide

/-- Row difference cannot be replaced by environment difference: wildcard
projection can map a new row to an already derivable environment. -/
def collapsed : Atom Bool := ⟨[.wildcard], [], [[false], [true]], [[true]], [[false]]⟩
example : transition Atom.deltaRows collapsed [] [] ∧
    ¬ ProviderFrontier.changed (transition Atom.oldRows collapsed)
      (transition Atom.allRows collapsed) [] [] := by
  constructor
  · exact ⟨[true], by simp [collapsed], rfl⟩
  · intro changed
    exact changed.2 ⟨[false], by simp [collapsed], rfl⟩

example (item : List (Option Bool))
    (current : ∃ output, ProviderFrontier.body (transition Atom.allRows) body input output ∧ item ∈ envEmit output)
    (absent : ¬ ∃ output, ProviderFrontier.body (transition Atom.oldRows) body input output ∧ item ∈ envEmit output) :
    ∃ pivot, pivot < body.length ∧ item ∈
      (runBody (compileBody body names).1 (some pivot) 0 (compileBody body names).2 slotEmit dirty).1 :=
  new_output_indexed_pivot body slotEmit envEmit emits (exact_covers body exactDelta) names input dirty rep
    (fun pivot => admitted (some pivot)) item current absent
def newHead : List (Option Bool) := [some false, some true, some true, some false]
theorem newCurrent : ∃ output,
    ProviderFrontier.body (transition Atom.allRows) body input output ∧ newHead ∈ envEmit output := by
  refine ⟨[(30, true), (20, true), (10, false)], ?_, by decide⟩
  refine ⟨[(20, true), (10, false)], ?_, ?_⟩
  · exact ⟨[true, false, true, false], by simp [second], rfl⟩
  · exact ⟨[(30, true), (20, true), (10, false)],
      ⟨[true, true, true, false], by simp [last], rfl⟩, rfl⟩

theorem newAbsent : ¬ ∃ output,
    ProviderFrontier.body (transition Atom.oldRows) body input output ∧ newHead ∈ envEmit output := by
  simp [ProviderFrontier.body, transition, body, second, last, AtomicBinding.bind,
    lookup, input, envEmit, observeHead, heads, wanted, newHead]

example : ∃ pivot, pivot < body.length ∧ newHead ∈
    (runBody (compileBody body names).1 (some pivot) 0 (compileBody body names).2 slotEmit dirty).1 :=
  new_output_indexed_pivot body slotEmit envEmit emits (exact_covers body exactDelta) names input dirty rep
    (fun pivot => admitted (some pivot)) newHead newCurrent newAbsent

/-- An overlap frontier is legal but is not the exact row difference. -/
def overlap : Atom Bool := ⟨[.wildcard], [], [[false], [true]], [[false], [true]], [[false]]⟩
example : DeltaCovers [overlap] := by
  simp [DeltaCovers, overlap]
example : ¬ DeltaExact [overlap] := by
  simp [DeltaExact, overlap]
example : transition Atom.deltaRows overlap [] [] := by
  exact ⟨[false], by simp [overlap], rfl⟩
/-- Missing a fresh row and adding a foreign row violate distinct obligations. -/
def missing : Atom Bool := {overlap with deltaRows := [[false]]}
def foreign : Atom Bool := {overlap with allRows := [[false]]}
example : ¬ DeltaCovers [missing] := by simp [DeltaCovers, missing, overlap]
example : ¬ DeltaCovers [foreign] := by simp [DeltaCovers, foreign, overlap]

#print axioms Ascent.IndexedPositiveTraversal.exact_covers
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.prefix_lookup
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.extend_lookup
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.lookup_membership

example : SharedIndex.lookup [1, 0] [[false, true], [false, true], [true, true]]
    (fun column => if column = 0 then some false else some true) =
    [[false, true], [false, true]] := by decide
example : SharedIndex.lookup [1] ([[false, true], [true, false]].reverse ++ [[true, true]])
    (fun _ => some true) = [[false, true], [true, true]] := by decide
example : (∀ column, column ∈ ([0, 1] : List Nat) ↔ column ∈ ([1, 0, 2] : List Nat).take 2) := by
  intro column; simp; grind

#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.extension_coverage
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.extension_nodup
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.extension_permutation
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.new_requirement_covered
#print axioms Ascent.IndexedPositiveTraversal.SharedIndex.chain_prefix_preserved
example : SharedIndex.extendPermutation [1] [0, 1] = [1, 0] := by decide
example : SharedIndex.extendPermutation [1, 0] [0, 1, 2] = [1, 0, 2] := by decide

#print axioms SharedIndex.MatchingCertificate.matching_bound
#print axioms SharedIndex.MatchingCertificate.maximum
#print axioms SharedIndex.MatchingCertificate.minimum_chains
#print axioms SharedIndex.MatchingCertificate.partition_balance
#print axioms SharedIndex.MatchingCertificate.partition_matching
#print axioms SharedIndex.MatchingCertificate.minimum_partition
example : SharedIndex.MatchingCertificate.partitionEdges [[0, 1, 2], [3]] =
    [(0, 1), (1, 2)] := by decide
example : SharedIndex.MatchingCertificate.Matching
    (SharedIndex.MatchingCertificate.partitionEdges [[0, 1, 2], [3]]) := by
  apply SharedIndex.MatchingCertificate.partition_matching
  decide
-- A false field is a successful lookup, not an absent column. Physical order
-- differs from logical order; overlong and uncovered requests are rejected.
example : SharedIndex.keyValue 0 [2, 0, 1] [true, false, true] = some false := by decide
example : SharedIndex.keyValue 3 [2, 0, 1] [true, false, true] = none := by decide
example : SharedIndex.adaptKey [1, 0, 2] 2 [0, 1] [false, true] =
    some [true, false] := by decide
example : SharedIndex.adaptKey [1, 0, 2] 0 [] ([] : List Bool) = some [] := by decide
example : SharedIndex.adaptKey [1, 0] 3 [0, 1, 2] [false, true, false] = none := by decide
example : SharedIndex.adaptKey [1, 0] 2 [0, 0] [false, true] = none := by decide
example : SharedIndex.adaptKey [1, 0] 2 [0, 1] [false] = none := by decide
example : SharedIndex.adaptKey [1, 0] 2 [0, 1] [false, true] ≠
    some [false, true] := by decide
example : ∃ values,
    SharedIndex.adaptKey [1, 0, 2] 2 [0, 1] ([0, 1].map (fun c => c == 1)) = some values ∧
    (([1, 0, 2].take 2).map (fun c => [false, true, false][c]?) = values.map some ↔
      SharedIndex.Matches [0, 1] [false, true, false] (fun c => some (c == 1))) := by
  apply SharedIndex.adapted_prefix_exact
  · decide
  · intro column; simp only [List.take_succ_cons, List.take_zero, List.mem_cons,
      List.not_mem_nil, or_false]; exact or_comm
#print axioms SharedIndex.key_value_mapped
#print axioms SharedIndex.key_value_absent
#print axioms SharedIndex.key_value_pair
#print axioms SharedIndex.adapt_key_overlong
#print axioms SharedIndex.adapt_key_mapped
#print axioms SharedIndex.adapted_prefix_exact
end Ascent.IndexedPositiveTraversalTests
