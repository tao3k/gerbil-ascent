-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Ordered positive proof DAG soundness. Source/candidate authentication and
native binding/fixed-clause refinement remain premises of the checkers. This
models validated prefix lookup, not protocol interleavings or proof completeness. -/
namespace Ascent.ProofDag
variable {Row : Type}
inductive Node (Row : Type) where
  | source (row : Row)
  | step (row : Row) (inputs : List Nat)
  deriving DecidableEq
inductive Derivable (base : Row → Prop) (rule : List Row → Row → Prop) : Row → Prop
  | source {row} : base row → Derivable base rule row
  | consequence {rows row} : (∀ input ∈ rows, Derivable base rule input) →
      rule rows row → Derivable base rule row

def lookup : List Row → Nat → Option Row
  | [], _ => none
  | row :: _, 0 => some row
  | _ :: rest, n + 1 => lookup rest n

def resolve (known : List Row) : List Nat → Option (List Row)
  | [] => some []
  | id :: rest => (lookup known id).bind fun row =>
      (resolve known rest).map (row :: ·)

def admit (baseCheck : Row → Bool) (ruleCheck : List Row → Row → Bool)
    (known : List Row) : Node Row → Option Row
  | .source row => if baseCheck row then some row else none
  | .step row ids => (resolve known ids).bind fun inputs =>
      if ruleCheck inputs row then some row else none

def verifyFrom (baseCheck : Row → Bool) (ruleCheck : List Row → Row → Bool)
    (known : List Row) : List (Node Row) → Option (List Row)
  | [] => some known
  | node :: rest => (admit baseCheck ruleCheck known node).bind fun row =>
      verifyFrom baseCheck ruleCheck (known ++ [row]) rest

theorem lookup_member (known : List Row) (id : Nat) (row : Row)
    (h : lookup known id = some row) : row ∈ known := by
  induction known generalizing id with
  | nil => simp [lookup] at h
  | cons first rest ih =>
    cases id with
    | zero => simp [lookup] at h; subst row; simp
    | succ id => exact List.mem_cons_of_mem first (ih id h)

theorem lookup_out_of_range (known : List Row) (id : Nat)
    (h : known.length ≤ id) : lookup known id = none := by
  induction known generalizing id with
  | nil => rfl
  | cons first rest ih =>
    cases id with
    | zero => simp at h
    | succ id => exact ih id (by simp only [List.length_cons] at h; omega)

theorem resolve_members (known : List Row) (ids : List Nat) (rows : List Row)
    (h : resolve known ids = some rows) : ∀ row ∈ rows, row ∈ known := by
  induction ids generalizing rows with
  | nil => simp [resolve] at h; subst rows; simp
  | cons id rest ih =>
    cases found : lookup known id with
    | none => simp [resolve, found] at h
    | some first =>
      cases tail : resolve known rest with
      | none => simp [resolve, found, tail] at h
      | some later =>
        simp [resolve, found, tail] at h
        subst rows
        intro row member
        rcases List.mem_cons.mp member with equal | inLater
        · subst row; exact lookup_member known id first found
        · exact ih later tail row inLater

theorem admit_sound (base : Row → Prop) (rule : List Row → Row → Prop)
    (baseCheck : Row → Bool) (ruleCheck : List Row → Row → Bool)
    (baseSound : ∀ row, baseCheck row = true → base row)
    (ruleSound : ∀ rows row, ruleCheck rows row = true → rule rows row)
    (known : List Row) (grounded : ∀ row ∈ known, Derivable base rule row)
    (node : Node Row) (row : Row) (h : admit baseCheck ruleCheck known node = some row) :
    Derivable base rule row := by
  cases node with
  | source value =>
    simp only [admit] at h
    split at h
    · rename_i checked
      cases h
      exact .source (baseSound _ checked)
    · simp at h
  | step value ids =>
    cases resolved : resolve known ids with
    | none => simp [admit, resolved] at h
    | some rows =>
      simp only [admit, resolved, Option.bind_some] at h
      split at h
      · rename_i checked
        cases h
        exact .consequence (fun input member => grounded input (resolve_members known ids rows resolved input member))
          (ruleSound rows _ checked)
      · simp at h

theorem verified_sound (base : Row → Prop) (rule : List Row → Row → Prop)
    (baseCheck : Row → Bool) (ruleCheck : List Row → Row → Bool)
    (baseSound : ∀ row, baseCheck row = true → base row)
    (ruleSound : ∀ rows row, ruleCheck rows row = true → rule rows row)
    (nodes : List (Node Row)) (known finalRows : List Row)
    (grounded : ∀ row ∈ known, Derivable base rule row)
    (h : verifyFrom baseCheck ruleCheck known nodes = some finalRows) :
    ∀ row ∈ finalRows, Derivable base rule row := by
  induction nodes generalizing known with
  | nil => simp [verifyFrom] at h; subst finalRows; exact grounded
  | cons node rest ih =>
    cases admitted : admit baseCheck ruleCheck known node with
    | none => simp [verifyFrom, admitted] at h
    | some row =>
      simp only [verifyFrom, admitted, Option.bind_some] at h
      apply ih (known ++ [row]) _ h
      intro input member
      rcases List.mem_append.mp member with old | added
      · exact grounded input old
      · simp at added; subst input
        exact admit_sound base rule baseCheck ruleCheck baseSound ruleSound known grounded node row admitted

theorem roots_sound (base : Row → Prop) (rule : List Row → Row → Prop)
    (known : List Row) (grounded : ∀ row ∈ known, Derivable base rule row)
    (ids : List Nat) (rows : List Row) (h : resolve known ids = some rows) :
    ∀ row ∈ rows, Derivable base rule row := by
  intro row member
  exact grounded row (resolve_members known ids rows h row member)

theorem verified_roots_sound (base : Row → Prop) (rule : List Row → Row → Prop)
    (baseCheck : Row → Bool) (ruleCheck : List Row → Row → Bool)
    (baseSound : ∀ row, baseCheck row = true → base row)
    (ruleSound : ∀ rows row, ruleCheck rows row = true → rule rows row)
    (nodes : List (Node Row)) (finalRows : List Row) (ids : List Nat) (rows : List Row)
    (verified : verifyFrom baseCheck ruleCheck [] nodes = some finalRows)
    (resolved : resolve finalRows ids = some rows) :
    ∀ row ∈ rows, Derivable base rule row := by
  apply roots_sound base rule finalRows _ ids rows resolved
  exact verified_sound base rule baseCheck ruleCheck baseSound ruleSound nodes [] finalRows
    (by simp) verified

theorem derivable_in_closed (base : Row → Prop) (rule : List Row → Row → Prop)
    (closed : Row → Prop) (sources : ∀ row, base row → closed row)
    (consequences : ∀ rows row, (∀ input ∈ rows, closed input) → rule rows row → closed row)
    (row : Row) (h : Derivable base rule row) : closed row := by
  induction h with
  | source hb => exact sources _ hb
  | consequence inputs hr ih => exact consequences _ _ ih hr
end Ascent.ProofDag
