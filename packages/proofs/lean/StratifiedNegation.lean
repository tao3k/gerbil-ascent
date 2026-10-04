/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

One completed stratum of the checked rule body's atom/negation path.
`visit` follows program/evaluate.ss: an atom extends its environment once
per matching row; negation keeps that environment only if no row matches.
Rows are frozen lower-stratum membership. This is a model of the control
path, not an extraction or proof of the native index/binding implementation.
-/
import Std

namespace Ascent.StratifiedNegation

inductive Clause (env row : Type) where
  | atom (rows : List row) (bind : env → row → Option env)
  | negation (rows : List row) (bind : env → row → Option env)

def matchingRow (rows : List row) (bind : env → row → Option env)
    (input : env) : Prop :=
  ∃ value, value ∈ rows ∧ ∃ output, bind input value = some output

def visitClause (clause : Clause env row) (input : env) : List env :=
  match clause with
  | .atom rows bind => rows.flatMap fun value =>
      match bind input value with
      | some output => [output]
      | none => []
  | .negation rows bind =>
      if rows.any (fun value => (bind input value).isSome) then [] else [input]

def visit : List (Clause env row) → env → List env
  | [], input => [input]
  | clause :: rest, input =>
      (visitClause clause input).flatMap (visit rest)

def ClauseHolds (clause : Clause env row) (input output : env) : Prop :=
  match clause with
  | .atom rows bind =>
      ∃ value, value ∈ rows ∧ bind input value = some output
  | .negation rows bind => output = input ∧ ¬ matchingRow rows bind input

def BodyHolds : List (Clause env row) → env → env → Prop
  | [], input, output => output = input
  | clause :: rest, input, output =>
      ∃ middle, ClauseHolds clause input middle ∧ BodyHolds rest middle output

theorem any_matching_iff (rows : List row) (bind : env → row → Option env)
    (input : env) :
    rows.any (fun value => (bind input value).isSome) = true ↔
      matchingRow rows bind input := by
  induction rows with
  | nil => simp [matchingRow]
  | cons value rest ih =>
      simp [List.any_cons, matchingRow, ih]
      cases bind input value <;> simp

theorem visitClause_iff (clause : Clause env row) (input output : env) :
    output ∈ visitClause clause input ↔ ClauseHolds clause input output := by
  classical
  cases clause with
  | atom rows bind =>
      simp only [visitClause, ClauseHolds, List.mem_flatMap]
      constructor
      · rintro ⟨value, member, present⟩
        cases h : bind input value with
        | none => simp [h] at present
        | some found =>
            simp [h] at present
            subst output
            exact ⟨value, member, h⟩
      · rintro ⟨value, member, bound⟩
        exact ⟨value, member, by simp [bound]⟩
  | negation rows bind =>
      simp only [visitClause, ClauseHolds]
      by_cases h : rows.any (fun value => (bind input value).isSome) = true
      · simp [h, (any_matching_iff rows bind input).mp h]
      · have absent : ¬ matchingRow rows bind input := by
          intro present
          exact h ((any_matching_iff rows bind input).mpr present)
        simp [h, absent]

theorem visit_iff (clauses : List (Clause env row)) (input output : env) :
    output ∈ visit clauses input ↔ BodyHolds clauses input output := by
  induction clauses generalizing input with
  | nil => simp [visit, BodyHolds]
  | cons clause rest ih =>
      simp only [visit, BodyHolds, List.mem_flatMap]
      constructor
      · rintro ⟨middle, member, follows⟩
        exact ⟨middle, (visitClause_iff clause input middle).mp member,
          (ih middle).mp follows⟩
      · rintro ⟨middle, holds, follows⟩
        exact ⟨middle, (visitClause_iff clause input middle).mpr holds,
          (ih middle).mpr follows⟩

/-- All candidate rows came from the frozen relation; every matching row is
    still present in the indexed candidate list. These are explicit premises,
    not properties proved about `indexed-rows` in Scheme. -/
def IndexExact (full candidates : List row)
    (bind : env → row → Option env) (input : env) : Prop :=
  (∀ value, value ∈ candidates → value ∈ full) ∧
  (∀ value output, value ∈ full → bind input value = some output →
    value ∈ candidates)

theorem matchingRow_indexed_iff (full candidates : List row)
    (bind : env → row → Option env) (input : env)
    (exact : IndexExact full candidates bind input) :
    matchingRow candidates bind input ↔ matchingRow full bind input := by
  constructor
  · rintro ⟨value, member, output, bound⟩
    exact ⟨value, exact.1 value member, output, bound⟩
  · rintro ⟨value, member, output, bound⟩
    exact ⟨value, exact.2 value output member bound, output, bound⟩

theorem atom_indexed_iff (full candidates : List row)
    (bind : env → row → Option env) (input output : env)
    (exact : IndexExact full candidates bind input) :
    ClauseHolds (.atom candidates bind) input output ↔
      ClauseHolds (.atom full bind) input output := by
  constructor
  · rintro ⟨value, member, bound⟩
    exact ⟨value, exact.1 value member, bound⟩
  · rintro ⟨value, member, bound⟩
    exact ⟨value, exact.2 value output member bound, bound⟩

theorem negation_indexed_iff (full candidates : List row)
    (bind : env → row → Option env) (input output : env)
    (exact : IndexExact full candidates bind input) :
    ClauseHolds (.negation candidates bind) input output ↔
      ClauseHolds (.negation full bind) input output := by
  simp only [ClauseHolds, matchingRow_indexed_iff full candidates bind input exact]

def overwrite (_input value : row) : Option row := some value

def equalBind [DecidableEq row] (input value : row) : Option row :=
  if input = value then some input else none

theorem matching_equal_iff [DecidableEq row] (blocked : List row)
    (input : row) :
    matchingRow blocked equalBind input ↔ input ∈ blocked := by
  constructor
  · rintro ⟨value, member, output, bound⟩
    by_cases same : input = value
    · simpa [same] using member
    · simp [equalBind, same] at bound
  · intro member
    exact ⟨input, member, input, by simp [equalBind]⟩

/-- A concrete checked clause sequence: bind a via row, then test the
    lower-stratum exclusion against that binding. -/
def viaBody [DecidableEq row] (via blocked : List row) :
    List (Clause row row) :=
  [.atom via overwrite, .negation blocked equalBind]

theorem viaBody_iff [DecidableEq row] (via blocked : List row)
    (seed output : row) :
    output ∈ visit (viaBody via blocked) seed ↔
      output ∈ via ∧ output ∉ blocked := by
  rw [visit_iff]
  simp only [viaBody, BodyHolds, ClauseHolds]
  constructor
  · rintro ⟨middle, ⟨value, member, bound⟩,
        ⟨last, ⟨same, absent⟩, final⟩⟩
    simp only [overwrite, Option.some.injEq] at bound
    subst middle
    subst last
    subst output
    exact ⟨member, fun present =>
      absent ((matching_equal_iff blocked value).mpr present)⟩
  · rintro ⟨member, absent⟩
    exact ⟨output, ⟨output, member, rfl⟩,
      ⟨output, ⟨rfl, fun present =>
        absent ((matching_equal_iff blocked output).mp present)⟩, rfl⟩⟩

/-- The checked branch's negation is evaluated before union with the direct
    branch. A direct witness survives even when it is excluded from the other
    branch. -/
def branchAnswer (direct via blocked : row → Prop) : row → Prop :=
  fun value => direct value ∨ (via value ∧ ¬ blocked value)

def Included (left right : row → Prop) : Prop :=
  ∀ value, left value → right value

/-- Once the negative relation is fixed by a completed lower stratum,
    positive current-stratum growth remains monotone. This is the premise
    needed before applying a least-fixed-point law to the current stratum. -/
theorem frozen_blocker_step_monotone
    (via : (row → Prop) → row → Prop)
    (viaMono : ∀ left right, Included left right →
      Included (via left) (via right))
    (direct blocked : row → Prop) (left right : row → Prop)
    (grows : Included left right) :
    Included (branchAnswer direct (via left) blocked)
      (branchAnswer direct (via right) blocked) := by
  intro value member
  cases member with
  | inl directMember => exact Or.inl directMember
  | inr viaMember =>
      exact Or.inr ⟨viaMono left right grows value viaMember.1,
        viaMember.2⟩

def evaluateBranches [DecidableEq row] (direct via blocked : List row)
    (seed : row) : List row :=
  visit [.atom direct overwrite] seed ++ visit (viaBody via blocked) seed

theorem directBody_iff (direct : List row) (seed output : row) :
    output ∈ visit [.atom direct overwrite] seed ↔ output ∈ direct := by
  rw [visit_iff]
  simp only [BodyHolds, ClauseHolds]
  constructor
  · rintro ⟨middle, ⟨value, member, bound⟩, final⟩
    simp only [overwrite, Option.some.injEq] at bound
    subst middle
    subst output
    exact member
  · intro member
    exact ⟨output, ⟨output, member, rfl⟩, rfl⟩

theorem evaluateBranches_iff [DecidableEq row]
    (direct via blocked : List row) (seed output : row) :
    output ∈ evaluateBranches direct via blocked seed ↔
      branchAnswer (· ∈ direct) (· ∈ via) (· ∈ blocked) output := by
  simp [evaluateBranches, branchAnswer, directBody_iff, viaBody_iff]

def postUnionNegation (direct via blocked : row → Prop) : row → Prop :=
  fun value => (direct value ∨ via value) ∧ ¬ blocked value

theorem branch_answer_iff (direct via blocked : row → Prop) (value : row) :
    branchAnswer direct via blocked value ↔
      direct value ∨ (via value ∧ ¬ blocked value) := Iff.rfl

theorem post_union_loses_direct (direct via blocked : row → Prop) (value : row)
    (present : direct value) (excluded : blocked value) :
    branchAnswer direct via blocked value ∧
      ¬ postUnionNegation direct via blocked value := by
  exact ⟨Or.inl present, fun wrong => wrong.2 excluded⟩

end Ascent.StratifiedNegation
