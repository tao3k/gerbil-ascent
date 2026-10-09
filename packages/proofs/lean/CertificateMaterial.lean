/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Counter transition used by candidate/certificate-limits.ss. Widths represent
distinct admitted rows after membership checks; this does not prove decoding,
deduplication, scalar equality, a heap bound, or certificate soundness.
-/
import Std
namespace Ascent.CertificateMaterial
structure Limits where
  rows : Nat
  cells : Nat
  arity : Nat
  deriving DecidableEq, Repr
structure Usage where
  rows : Nat
  cells : Nat
  deriving DecidableEq, Repr
def Fits (cap : Limits) (u : Usage) (width : Nat) : Prop :=
  width ≤ cap.arity ∧ u.rows < cap.rows ∧ u.cells + width ≤ cap.cells
instance (cap : Limits) (u : Usage) (width : Nat) : Decidable (Fits cap u width) :=
  inferInstanceAs (Decidable (_ ∧ _ ∧ _))
def reserve (cap : Limits) (u : Usage) (width : Nat) : Option Usage :=
  if Fits cap u width then some ⟨u.rows + 1, u.cells + width⟩ else none
def transition (cap : Limits) (u : Usage) (width : Nat) : Usage :=
  (reserve cap u width).getD u
theorem accepted_bounds (cap : Limits) (u v : Usage) (width : Nat)
    (h : reserve cap u width = some v) :
    v.rows ≤ cap.rows ∧ v.cells ≤ cap.cells ∧ width ≤ cap.arity := by
  unfold reserve at h
  split at h
  · rename_i hf
    cases h
    rcases hf with ⟨hw, hr, hc⟩
    exact ⟨(by change u.rows + 1 ≤ cap.rows; omega), hc, hw⟩
  · simp at h
theorem accepted_exact (cap : Limits) (u v : Usage) (width : Nat)
    (h : reserve cap u width = some v) :
    v.rows = u.rows + 1 ∧ v.cells = u.cells + width := by
  unfold reserve at h
  split at h
  · cases h; exact ⟨rfl, rfl⟩
  · simp at h
theorem refused_unchanged (cap : Limits) (u : Usage) (width : Nat)
    (h : reserve cap u width = none) : transition cap u width = u := by
  simp [transition, h]
theorem refused_iff (cap : Limits) (u : Usage) (width : Nat) :
    reserve cap u width = none ↔ ¬ Fits cap u width := by
  simp [reserve]
def reserveAll (cap : Limits) (u : Usage) : List Nat → Option Usage
  | [] => some u
  | width :: rest => (reserve cap u width).bind (fun next => reserveAll cap next rest)
theorem successful_trace_exact (cap : Limits) (widths : List Nat) (u v : Usage)
    (h : reserveAll cap u widths = some v) :
    v.rows = u.rows + widths.length ∧ v.cells = u.cells + widths.sum := by
  induction widths generalizing u with
  | nil => simp [reserveAll] at h; cases h; simp
  | cons width rest ih =>
    cases hr : reserve cap u width with
    | none => simp [reserveAll, hr] at h
    | some next =>
      simp only [reserveAll, hr, Option.bind_some] at h
      have hn := accepted_exact cap u next width hr
      have ht := ih next h
      simp only [List.length_cons, List.sum_cons]
      constructor <;> omega
theorem trace_append (cap : Limits) (initialWidths laterWidths : List Nat) (u : Usage) :
    reserveAll cap u (initialWidths ++ laterWidths) =
      (reserveAll cap u initialWidths).bind (fun next => reserveAll cap next laterWidths) := by
  induction initialWidths generalizing u with
  | nil => simp [reserveAll]
  | cons width rest ih =>
    cases hr : reserve cap u width <;> simp [reserveAll, hr, ih]
theorem blocked_trace_stays_blocked (cap : Limits) (initialWidths laterWidths : List Nat) (u : Usage)
    (h : reserveAll cap u initialWidths = none) :
    reserveAll cap u (initialWidths ++ laterWidths) = none := by
  rw [trace_append, h]; rfl
theorem successful_trace_bounds (cap : Limits) (widths : List Nat) (u v : Usage)
    (initial : u.rows ≤ cap.rows ∧ u.cells ≤ cap.cells)
    (h : reserveAll cap u widths = some v) :
    v.rows ≤ cap.rows ∧ v.cells ≤ cap.cells := by
  induction widths generalizing u with
  | nil => simp [reserveAll] at h; cases h; exact initial
  | cons width rest ih =>
    cases hr : reserve cap u width with
    | none => simp [reserveAll, hr] at h
    | some next =>
      simp only [reserveAll, hr, Option.bind_some] at h
      have hn := accepted_bounds cap u next width hr
      exact ih next ⟨hn.1, hn.2.1⟩ h
end Ascent.CertificateMaterial
