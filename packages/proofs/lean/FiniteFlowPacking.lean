-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std
import PoloniusInitialization

/-! Address and byte-delta laws for core/finite-flow.ss. The native kernel
uses one point root per right-domain ordinal and fact bits in eight-bit bytes.
These laws establish mathematical packing and byte operations; conversion of
Gambit fixnums/u8vectors and queue scheduling is not extracted or proved here. -/
namespace Ascent.FiniteFlowPacking

def address (point fact : Nat) : Nat × Nat × Nat := (point, fact / 8, fact % 8)

theorem address_injective (p x q y : Nat) (same : address p x = address q y) :
    p = q ∧ x = y := by
  simp only [address, Prod.mk.injEq] at same
  omega

theorem bit_in_byte (p x : Nat) : (address p x).2.2 < 8 := by
  simp [address, Nat.mod_lt]

def freshByte (incoming stored blocked : BitVec 8) : BitVec 8 :=
  incoming &&& (~~~stored) &&& (~~~blocked)

theorem fresh_bit (incoming stored blocked : BitVec 8) (i : Nat) (bound : i < 8) :
    (freshByte incoming stored blocked).getLsbD i =
      (incoming.getLsbD i && !stored.getLsbD i && !blocked.getLsbD i) := by
  simp [freshByte, bound]

theorem fresh_disjoint (incoming stored blocked : BitVec 8) (i : Nat) (bound : i < 8) :
    (stored.getLsbD i && (freshByte incoming stored blocked).getLsbD i) = false := by
  rw [fresh_bit incoming stored blocked i bound]
  cases incoming.getLsbD i <;> cases stored.getLsbD i <;> cases blocked.getLsbD i <;> decide

theorem merged_difference_exact (incoming stored blocked : BitVec 8) (i : Nat) (bound : i < 8) :
    ((stored ||| freshByte incoming stored blocked).getLsbD i && !stored.getLsbD i) =
      (freshByte incoming stored blocked).getLsbD i := by
  simp only [BitVec.getLsbD_or, fresh_bit incoming stored blocked i bound]
  cases incoming.getLsbD i <;> cases stored.getLsbD i <;> cases blocked.getLsbD i <;> decide

theorem target_blocker_removes_fresh (incoming stored blocked : BitVec 8)
    (i : Nat) (bound : i < 8) (kill : blocked.getLsbD i = true) :
    (freshByte incoming stored blocked).getLsbD i = false := by
  simp [fresh_bit incoming stored blocked i bound, kill]

/-- This bounds bitmap payload only. Domain values, ordinal maps, roots, CFG,
queue, pending bytes, fresh scratch vectors and the collector are excluded. -/
theorem payload_bound (facts occupied points : Nat) (h : occupied ≤ points) :
    ((facts + 7) / 8) * occupied ≤ ((facts + 7) / 8) * points :=
  Nat.mul_le_mul_left _ h
end Ascent.FiniteFlowPacking
