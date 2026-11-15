/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Pure finite-spine refinement of bounded-list-length. Payloads are erased.
Cycles and mutable Gerbil pointers require the independent native controls.
-/
import Std
namespace Ascent.BoundedSpine
inductive Spine where
  | nil
  | cons (rest : Spine)
  | improper
  deriving DecidableEq, Repr
open Spine

def properLength : Spine → Option Nat
  | nil => some 0
  | improper => none
  | cons rest => (properLength rest).map Nat.succ

def boundedLength : Nat → Spine → Option Nat
  | _, nil => some 0
  | _, improper => none
  | 0, cons _ => none
  | cap + 1, cons rest => (boundedLength cap rest).map Nat.succ

theorem bounded_formula (cap : Nat) (spine : Spine) :
    boundedLength cap spine = (properLength spine).bind
      (fun n => if n ≤ cap then some n else none) := by
  induction spine generalizing cap with
  | nil => simp [boundedLength, properLength]
  | improper => simp [boundedLength, properLength]
  | cons rest ih =>
    cases cap with
    | zero => cases h : properLength rest <;> simp [boundedLength, properLength, h]
    | succ cap =>
      cases h : properLength rest with
      | none => simp [boundedLength, properLength, ih, h]
      | some n =>
        by_cases fit : n ≤ cap <;> simp [boundedLength, properLength, ih, h, fit]

theorem accepted_exact (cap n : Nat) (spine : Spine) :
    boundedLength cap spine = some n ↔ properLength spine = some n ∧ n ≤ cap := by
  rw [bounded_formula]
  cases h : properLength spine with
  | none => simp
  | some width =>
    by_cases fit : width ≤ cap <;> simp [fit] <;> omega

theorem improper_rejected (cap : Nat) (spine : Spine)
    (h : properLength spine = none) : boundedLength cap spine = none := by
  simp [bounded_formula, h]

theorem exact_cap (cap : Nat) (spine : Spine)
    (h : properLength spine = some cap) : boundedLength cap spine = some cap := by
  exact (accepted_exact cap cap spine).mpr ⟨h, Nat.le_refl cap⟩

theorem oversized_rejected (cap width : Nat) (spine : Spine)
    (h : properLength spine = some width) (large : cap < width) :
    boundedLength cap spine = none := by
  simp [bounded_formula, h, Nat.not_le.mpr large]

theorem admitted_monotone (small large n : Nat) (spine : Spine)
    (caps : small ≤ large) (h : boundedLength small spine = some n) :
    boundedLength large spine = some n := by
  obtain ⟨proper, fit⟩ := (accepted_exact small n spine).mp h
  exact (accepted_exact large n spine).mpr ⟨proper, Nat.le_trans fit caps⟩

-- Pair advances, excluding the final nil/improper/cap boundary observation.
def advances : Nat → Spine → Nat
  | cap + 1, cons rest => 1 + advances cap rest
  | _, _ => 0

theorem advances_bound (cap : Nat) (spine : Spine) : advances cap spine ≤ cap := by
  induction cap generalizing spine with
  | zero => cases spine <;> simp [advances]
  | succ cap ih =>
    cases spine with
    | nil => simp [advances]
    | improper => simp [advances]
    | cons rest => have h := ih rest; simp only [advances]; omega
/-! The provider still receives detached pair spines. A compiled reader
receives a second snapshot whose private vectors copy field references in
column order. Source witnesses use the same vector key encoding. The owner and
provider never share either snapshot's storage. Mutable field values keep their
existing identity in both representations. -/

theorem providerVectorFields (row : List α) : row.toArray.toList = row := by simp

theorem providerVectorKey (a b : List α) : a.toArray = b.toArray ↔ a = b := by
  constructor
  · intro h
    simpa using congrArg Array.toList h
  · exact congrArg List.toArray

theorem providerVectorPacket (rows : List (List α)) :
    (rows.map List.toArray).map Array.toList = rows := by
  simp [List.map_map, Function.comp_def]

-- Reference slots allocated beyond the first, still-detached provider copy.
-- Each representation also allocates the same outer packet spine. The vector
-- path also encodes each source row for the witness, including duplicates.
-- Object headers and collector traffic are outside this model.
def returnedPairSlots (rows width : Nat) : Nat := rows * (2 * width + 2)
def packedPacketSlots (rows keyRows width : Nat) : Nat := rows * (width + 2) + keyRows * width

theorem packedProviderSlots (rows keyRows width : Nat) (bound : keyRows ≤ rows) :
    packedPacketSlots rows keyRows width ≤ returnedPairSlots rows width := by
  have h : keyRows * width ≤ rows * width := Nat.mul_le_mul_right width bound
  simp only [packedPacketSlots, returnedPairSlots, Nat.mul_add, Nat.two_mul]
  omega

-- A rectangular vector has a fixed header per row, while a wide pair spine
-- has one header per field. With equal numbers of returned and source rows,
-- the new allocation uses two row headers per row in place of width headers.
theorem packedProviderHeaders (rows width : Nat) (wide : 2 ≤ width) :
    rows * 2 ≤ rows * width := Nat.mul_le_mul_left rows wide
-- Every row with the selected key must appear. A uniform literal cut
-- therefore charges the witness encoding to a packet at least as large.
theorem literalCoveragePaysForWitness (source packet : List α) (coverage : source.length ≤ packet.length)
    (width : Nat) :
    packedPacketSlots packet.length source.length width ≤ returnedPairSlots packet.length width :=
  packedProviderSlots _ _ _ coverage

theorem trailingWildcards (check : α → Bool) (terms : List α) (ignored : Nat) :
    (terms.map check ++ List.replicate ignored true).all id = (terms.map check).all id := by
  simp [List.all_append, List.all_replicate]
end Ascent.BoundedSpine
