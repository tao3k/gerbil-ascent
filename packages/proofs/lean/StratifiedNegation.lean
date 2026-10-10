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

/-- Logical contents of a keyed physical lookup. `program/index.ss`
    chooses a key from already bound terms, while `table/access.ss` owns
    the physical buckets. The theorem below does not prove that a native
    bucket has these contents. -/
def keyedRows [DecidableEq key] (full : List row)
    (keyOf : row → key) (wanted : key) : List row :=
  full.filter (fun value => keyOf value = wanted)

theorem keyed_rows_exact [DecidableEq key] (full : List row)
    (keyOf : row → key) (wanted : key)
    (bind : env → row → Option env) (input : env)
    (matching_key : ∀ value output,
      bind input value = some output → keyOf value = wanted) :
    IndexExact full (keyedRows full keyOf wanted) bind input := by
  constructor
  · intro value member
    exact (List.mem_filter.mp member).1
  · intro value output member bound
    exact List.mem_filter.mpr
      ⟨member, by simpa using matching_key value output bound⟩

theorem keyed_negation_iff [DecidableEq key] (full : List row)
    (keyOf : row → key) (wanted : key)
    (bind : env → row → Option env) (input output : env)
    (matching_key : ∀ value result,
      bind input value = some result → keyOf value = wanted) :
    ClauseHolds (.negation (keyedRows full keyOf wanted) bind) input output ↔
      ClauseHolds (.negation full bind) input output :=
  negation_indexed_iff full (keyedRows full keyOf wanted) bind input output
    (keyed_rows_exact full keyOf wanted bind input matching_key)

/-- Set-membership model of the canonical hash provider's `cons` update.
    A native `hash-get`/`hash-put!` representation relation is still required;
    row order and duplicate occurrences are outside this set observation. -/
def Buckets (key row : Type) := key → List row

def emptyBuckets : Buckets key row := fun _ => []

def insertBucket [DecidableEq key] (keyOf : row → key)
    (buckets : Buckets key row) (value : row) : Buckets key row :=
  fun wanted => if keyOf value = wanted
    then value :: buckets wanted else buckets wanted

def extendBuckets [DecidableEq key] (keyOf : row → key) :
    List row → Buckets key row → Buckets key row
  | [], buckets => buckets
  | value :: rest, buckets =>
      extendBuckets keyOf rest (insertBucket keyOf buckets value)

def buildBuckets [DecidableEq key] (keyOf : row → key)
    (full : List row) : Buckets key row :=
  extendBuckets keyOf full.reverse emptyBuckets

def BucketRep (full : List row) (keyOf : row → key)
    (buckets : Buckets key row) : Prop :=
  ∀ wanted value, value ∈ buckets wanted ↔
    value ∈ full ∧ keyOf value = wanted

theorem insert_bucket_iff [DecidableEq key] (keyOf : row → key)
    (buckets : Buckets key row) (added value : row) (wanted : key) :
    value ∈ insertBucket keyOf buckets added wanted ↔
      (value = added ∧ keyOf added = wanted) ∨ value ∈ buckets wanted := by
  by_cases h : keyOf added = wanted <;> simp [insertBucket, h]

theorem extend_buckets_iff [DecidableEq key] (keyOf : row → key)
    (newRows : List row) (buckets : Buckets key row)
    (wanted : key) (value : row) :
    value ∈ extendBuckets keyOf newRows buckets wanted ↔
      (value ∈ newRows ∧ keyOf value = wanted) ∨
        value ∈ buckets wanted := by
  induction newRows generalizing buckets with
  | nil => simp [extendBuckets]
  | cons added rest ih =>
      rw [extendBuckets, ih, insert_bucket_iff]
      simp only [List.mem_cons]
      constructor
      · rintro (⟨member, key⟩ | (⟨same, key⟩ | old))
        · exact Or.inl ⟨Or.inr member, key⟩
        · subst value
          exact Or.inl ⟨Or.inl rfl, key⟩
        · exact Or.inr old
      · rintro (⟨head | tail, key⟩ | old)
        · subst value
          exact Or.inr (Or.inl ⟨rfl, key⟩)
        · exact Or.inl ⟨tail, key⟩
        · exact Or.inr (Or.inr old)

theorem build_bucket_rep [DecidableEq key] (keyOf : row → key)
    (full : List row) : BucketRep full keyOf (buildBuckets keyOf full) := by
  intro wanted value
  simp [buildBuckets, extend_buckets_iff, emptyBuckets]

theorem extend_bucket_rep [DecidableEq key] (keyOf : row → key)
    (full newRows : List row) (buckets : Buckets key row)
    (rep : BucketRep full keyOf buckets) :
    BucketRep (newRows ++ full) keyOf
      (extendBuckets keyOf newRows buckets) := by
  intro wanted value
  rw [extend_buckets_iff, rep wanted value]
  simp only [List.mem_append]
  constructor
  · rintro (⟨newMember, key⟩ | ⟨oldMember, key⟩)
    · exact ⟨Or.inl newMember, key⟩
    · exact ⟨Or.inr oldMember, key⟩
  · rintro ⟨newMember | oldMember, key⟩
    · exact Or.inl ⟨newMember, key⟩
    · exact Or.inr ⟨oldMember, key⟩

theorem bucket_index_exact (full : List row) (keyOf : row → key)
    (buckets : Buckets key row) (rep : BucketRep full keyOf buckets)
    (bind : env → row → Option env) (input : env) (wanted : key)
    (matching_key : ∀ value output,
      bind input value = some output → keyOf value = wanted) :
    IndexExact full (buckets wanted) bind input := by
  constructor
  · intro value member
    exact ((rep wanted value).mp member).1
  · intro value output member bound
    exact (rep wanted value).mpr
      ⟨member, matching_key value output bound⟩

theorem bucket_negation_iff (full : List row) (keyOf : row → key)
    (buckets : Buckets key row) (rep : BucketRep full keyOf buckets)
    (bind : env → row → Option env) (input output : env) (wanted : key)
    (matching_key : ∀ value result,
      bind input value = some result → keyOf value = wanted) :
    ClauseHolds (.negation (buckets wanted) bind) input output ↔
      ClauseHolds (.negation full bind) input output :=
  negation_indexed_iff full (buckets wanted) bind input output
    (bucket_index_exact full keyOf buckets rep bind input wanted matching_key)

/-- The callback-free, admitted negation term subset. A `bound` term stores
    the value already resolved from the preceding clause environment; a
    wildcard contributes no index column. Expression callbacks and custom
    patterns are deliberately outside this correspondence. -/
inductive GroundTerm (value : Type) where
  | literal (expected : value)
  | bound (expected : value)
  | wildcard

def termKey : List (GroundTerm value) → List value
  | [] => []
  | .literal expected :: rest => expected :: termKey rest
  | .bound expected :: rest => expected :: termKey rest
  | .wildcard :: rest => termKey rest

def rowKey : List (GroundTerm value) → List value → List value
  | .literal _ :: rest, observed :: tail => observed :: rowKey rest tail
  | .bound _ :: rest, observed :: tail => observed :: rowKey rest tail
  | .wildcard :: rest, _ :: tail => rowKey rest tail
  | _, _ => []

def matchGround [DecidableEq value] :
    List (GroundTerm value) → List value → Bool
  | [], [] => true
  | .literal expected :: rest, observed :: tail =>
      decide (expected = observed) && matchGround rest tail
  | .bound expected :: rest, observed :: tail =>
      decide (expected = observed) && matchGround rest tail
  | .wildcard :: rest, _ :: tail => matchGround rest tail
  | _, _ => false

def bindGround [DecidableEq value] (terms : List (GroundTerm value))
    (input : env) (row : List value) : Option env :=
  if matchGround terms row then some input else none

theorem match_ground_key [DecidableEq value]
    (terms : List (GroundTerm value)) (row : List value)
    (matched : matchGround terms row = true) :
    rowKey terms row = termKey terms := by
  induction terms generalizing row with
  | nil =>
      cases row <;> simp [matchGround, rowKey, termKey] at matched ⊢
  | cons term rest ih =>
      cases row with
      | nil => simp [matchGround] at matched
      | cons observed tail =>
          cases term with
          | literal expected =>
              simp only [matchGround, Bool.and_eq_true, decide_eq_true_eq] at matched
              simp [rowKey, termKey, matched.1, ih tail matched.2]
          | bound expected =>
              simp only [matchGround, Bool.and_eq_true, decide_eq_true_eq] at matched
              simp [rowKey, termKey, matched.1, ih tail matched.2]
          | wildcard =>
              simpa [rowKey, termKey] using ih tail matched

theorem bind_ground_key [DecidableEq value]
    (terms : List (GroundTerm value)) (input output : env)
    (row : List value) (bound : bindGround terms input row = some output) :
    rowKey terms row = termKey terms := by
  by_cases matched : matchGround terms row = true
  · exact match_ground_key terms row matched
  · simp [bindGround, matched] at bound

theorem ground_bucket_negation_iff [DecidableEq value]
    (terms : List (GroundTerm value)) (full : List (List value))
    (buckets : Buckets (List value) (List value))
    (rep : BucketRep full (rowKey terms) buckets)
    (input output : env) :
    ClauseHolds (.negation (buckets (termKey terms))
      (bindGround terms)) input output ↔
      ClauseHolds (.negation full (bindGround terms)) input output :=
  bucket_negation_iff full (rowKey terms) buckets rep
    (bindGround terms) input output (termKey terms)
    (fun row result bound => bind_ground_key terms input result row bound)

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

/-- Frozen-row probe outcomes. Each inspected row costs one unit; an absence
    continuation costs one more. `none` is refusal, never an absence result. -/
def negativeProbe (fuel : Nat) : List Bool → Option (Bool × Nat)
  | [] => match fuel with
    | 0 => none
    | remaining + 1 => some (false, remaining)
  | matched :: rest => match fuel with
    | 0 => none
    | remaining + 1 => if matched then some (true, remaining) else negativeProbe remaining rest

theorem negativeProbe_truth (rows : List Bool) (fuel left : Nat) (found : Bool)
    (h : negativeProbe fuel rows = some (found, left)) :
    found = rows.any id := by
  induction rows generalizing fuel with
  | nil => cases fuel <;> simp [negativeProbe] at h ⊢; exact h.1
  | cons value rest ih =>
    cases fuel with
    | zero => simp [negativeProbe] at h
    | succ fuel =>
      cases value with
      | false => simpa using ih fuel h
      | true => simp [negativeProbe] at h; simpa using h.1

theorem negativeProbe_remaining (rows : List Bool) (fuel left : Nat) (found : Bool)
    (h : negativeProbe fuel rows = some (found, left)) : left < fuel := by
  induction rows generalizing fuel with
  | nil => cases fuel <;> simp [negativeProbe] at h; cases h; omega
  | cons value rest ih =>
    cases fuel with
    | zero => simp [negativeProbe] at h
    | succ fuel =>
      cases value with
      | false => have := ih fuel h; omega
      | true => simp [negativeProbe] at h; cases h; omega

theorem negativeProbe_absence_cost (rows : List Bool) (fuel left : Nat)
    (h : negativeProbe fuel rows = some (false, left)) :
    fuel = left + rows.length + 1 := by
  induction rows generalizing fuel with
  | nil => cases fuel <;> simp [negativeProbe] at h; cases h; simp
  | cons value rest ih =>
    cases fuel with
    | zero => simp [negativeProbe] at h
    | succ fuel =>
      cases value with
      | false => have := ih fuel h; simp only [List.length_cons]; omega
      | true => simp [negativeProbe] at h

theorem negativeProbe_first_match (rest : List Bool) (fuel : Nat) :
    negativeProbe (fuel + 1) (true :: rest) = some (true, fuel) := by
  simp [negativeProbe]

theorem negativeProbe_sufficient (rows : List Bool) (fuel : Nat)
    (enough : rows.length + 1 ≤ fuel) :
    ∃ left, negativeProbe fuel rows = some (rows.any id, left) := by
  induction rows generalizing fuel with
  | nil =>
    cases fuel with
    | zero => simp at enough
    | succ fuel => exact ⟨fuel, rfl⟩
  | cons value rest ih =>
    cases fuel with
    | zero => simp at enough
    | succ fuel =>
      cases value with
      | true => exact ⟨fuel, by simp [negativeProbe]⟩
      | false =>
        have hr : rest.length + 1 ≤ fuel := by simp only [List.length_cons] at enough; omega
        obtain ⟨left, hl⟩ := ih fuel hr
        exact ⟨left, by simpa [negativeProbe] using hl⟩

theorem negativeProbe_binding_truth (rows : List row) (bind : env → row → Option env)
    (input : env) (fuel left : Nat) (found : Bool)
    (h : negativeProbe fuel (rows.map (fun value => (bind input value).isSome)) =
      some (found, left)) : found = true ↔ matchingRow rows bind input := by
  have ht := negativeProbe_truth _ fuel left found h
  have mapped : (rows.map (fun value => (bind input value).isSome)).any id =
      rows.any (fun value => (bind input value).isSome) := by simp
  rw [mapped] at ht
  rw [ht]
  exact any_matching_iff rows bind input

theorem negativeProbe_preserves_negation (rows : List row) (bind : env → row → Option env)
    (input output : env) (fuel left : Nat) (found : Bool)
    (h : negativeProbe fuel (rows.map (fun value => (bind input value).isSome)) =
      some (found, left)) :
    output ∈ visitClause (.negation rows bind) input ↔ output = input ∧ found = false := by
  rw [visitClause_iff]
  simp only [ClauseHolds]
  have truth := negativeProbe_binding_truth rows bind input fuel left found h
  cases found <;> simp_all

end Ascent.StratifiedNegation
