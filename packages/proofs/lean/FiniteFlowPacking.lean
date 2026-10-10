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

/-- Point-local mask join for the ordinary keyed lattice Program. The native
integer representation must be nonnegative and strictly below 2^width. -/
def maskJoin {w : Nat} (a b : BitVec w) := a ||| b
def transfer {w : Nat} (incoming blocked : BitVec w) := incoming &&& ~~~blocked
def gamma {w : Nat} (mask : BitVec w) (i : Nat) : Prop := mask.getLsbD i = true

theorem maskJoin_associative {w : Nat} (a b c : BitVec w) :
    maskJoin (maskJoin a b) c = maskJoin a (maskJoin b c) := BitVec.or_assoc a b c

theorem maskJoin_commutative {w : Nat} (a b : BitVec w) :
    maskJoin a b = maskJoin b a := BitVec.or_comm a b

theorem maskJoin_idempotent {w : Nat} (a : BitVec w) : maskJoin a a = a := BitVec.or_self

theorem gamma_join {w : Nat} (a b : BitVec w) (i : Nat) :
    gamma (maskJoin a b) i ↔ gamma a i ∨ gamma b i := by
  simp [gamma, maskJoin, Bool.or_eq_true]

theorem gamma_transfer {w : Nat} (a blocked : BitVec w) (i : Nat) (bound : i < w) :
    gamma (transfer a blocked) i ↔ gamma a i ∧ ¬ gamma blocked i := by
  simp [gamma, transfer, bound, Bool.and_eq_true]

theorem transfer_join {w : Nat} (a b blocked : BitVec w) :
    transfer (maskJoin a b) blocked = maskJoin (transfer a blocked) (transfer b blocked) :=
  BitVec.and_or_distrib_right

theorem transfer_monotone {w : Nat} (a b blocked : BitVec w)
    (growth : ∀ i, gamma a i → gamma b i) (i : Nat) (bound : i < w) :
    gamma (transfer a blocked) i → gamma (transfer b blocked) i := by
  rw [gamma_transfer a blocked i bound, gamma_transfer b blocked i bound]
  exact fun h => ⟨growth i h.1, h.2⟩

theorem transfer_blockers_antitone {w : Nat} (a old new : BitVec w)
    (growth : ∀ i, gamma old i → gamma new i) (i : Nat) (bound : i < w) :
    gamma (transfer a new) i → gamma (transfer a old) i := by
  rw [gamma_transfer a new i bound, gamma_transfer a old i bound]
  exact fun h => ⟨h.1, fun kill => h.2 (growth i kill)⟩
end Ascent.FiniteFlowPacking
