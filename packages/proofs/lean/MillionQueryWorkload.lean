-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
import RuntimeMeasurement

/-! Measurement scope and the independent complete-row oracle. This does not
prove the Scheme bitmap, rule evaluator, concrete allocation or achieved speed. -/
namespace Ascent.MillionQueryWorkload

def inputFacts (groups width : Nat) : Nat := groups * (width - 1)
def closureRows (groups width : Nat) : Nat := groups * width * (width - 1) / 2
def materializedFacts (groups width : Nat) : Nat :=
  inputFacts groups width + closureRows groups width

theorem million_input_profile : inputFacts 1000000 2 = 1000000 := by decide
theorem recursive_input_profile : inputFacts 128 128 = 16256 := by decide
theorem recursive_output_profile : closureRows 128 128 = 1040384 := by decide
theorem million_total_profile : materializedFacts 1000000 2 = 2000000 := by decide
theorem recursive_total_profile : materializedFacts 128 128 = 1056640 := by decide

/-- Membership, uniqueness and exact cardinality establish complete coverage.
The native oracle must establish all three against its independent universe. -/
theorem complete_oracle {Row : Type} (observed expected : List Row)
    (unique : observed.Nodup) (members : observed ⊆ expected)
    (count : observed.length = expected.length) : expected ⊆ observed := by
  classical
  intro row member
  by_cases found : row ∈ observed
  · exact found
  have absent := found
  apply False.elim
  have extended : (row :: observed).Nodup := List.nodup_cons.mpr ⟨absent, unique⟩
  have included : row :: observed ⊆ expected := by
    intro value inside
    rcases List.mem_cons.mp inside with same | old
    · subst value; exact member
    · exact members old
  have bound := extended.length_le_of_subset included
  simp only [List.length_cons] at bound
  omega

/-- A width-indexed bitmap may encode distinct columns only within that width. -/
def bitmapIndex (width left right : Nat) : Nat := left * width + right

theorem bitmap_index_injective (width left right otherLeft otherRight : Nat)
    (rightBound : right < width) (otherBound : otherRight < width)
    (same : bitmapIndex width left right = bitmapIndex width otherLeft otherRight) :
    left = otherLeft ∧ right = otherRight := by
  have positive : 0 < width := Nat.zero_lt_of_lt rightBound
  have divide := congrArg (fun n => n / width) same
  have remainder := congrArg (fun n => n % width) same
  have quotient (a b : Nat) (bound : b < width) : (a * width + b) / width = a := by
    rw [Nat.add_comm, Nat.add_mul_div_right b a positive, Nat.div_eq_of_lt bound]
    exact Nat.zero_add a
  change (left * width + right) / width = (otherLeft * width + otherRight) / width at divide
  rw [quotient left right rightBound, quotient otherLeft otherRight otherBound] at divide
  simp [bitmapIndex, Nat.add_mod, Nat.mod_eq_of_lt rightBound,
    Nat.mod_eq_of_lt otherBound] at remainder
  exact ⟨divide, remainder⟩

structure DataEvidence where
  inputFacts : Nat
  exportedRows : Nat
  requests : Nat
  unit : RuntimeMeasurement.Unit

def MillionData (e : DataEvidence) : Prop :=
  1000000 ≤ e.inputFacts ∨ 1000000 ≤ e.exportedRows

theorem million_messages_do_not_establish_million_data :
    ¬ MillionData ⟨0, 0, 1000000, .sessionState⟩ := by
  simp [MillionData]

theorem state_reply_cannot_certify_complete_query
    (e : RuntimeMeasurement.Evidence) (state : e.unit = .sessionState) (bound : Nat) :
    ¬ RuntimeMeasurement.Admitted .relationRun bound e := by
  apply RuntimeMeasurement.different_units_rejected
  simp [state]

end Ascent.MillionQueryWorkload

#print axioms Ascent.MillionQueryWorkload.complete_oracle
#print axioms Ascent.MillionQueryWorkload.bitmap_index_injective
#print axioms Ascent.MillionQueryWorkload.state_reply_cannot_certify_complete_query
