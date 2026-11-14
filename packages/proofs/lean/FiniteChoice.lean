-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Init

/-! Ground fact-set semantics from Finite-Choice Logic Programming, §2.1.
Attributes and ground values use natural-number identities. The database is a
partial function, so each attribute has at most one value by construction. -/
namespace Ascent.FiniteChoice

abbrev Database := Nat → Option Nat
abbrev Fact := Nat × Nat

inductive Head where
  | closed (keyId : Nat) (values : List Nat)
  | openOffer (keyId value : Nat)

structure Rule where
  body : List Fact
  head : Head

def enabled (database : Database) (rule : Rule) : Prop :=
  ∀ fact ∈ rule.body, database fact.1 = some fact.2

def assign (database : Database) (keyId value : Nat) : Database :=
  fun key => if key = keyId then some value else database key

def choose (database : Database) (keyId value : Nat) : List Database :=
  match database keyId with
  | none => [assign database keyId value]
  | some prior => if prior = value then [database] else []

def evolve (database : Database) (head : Head) : List Database :=
  match head with
  | .closed keyId values => values.flatMap (choose database keyId)
  | .openOffer keyId value => database :: choose database keyId value

/-- Rule successors are interpreted as a set. Duplicate offers may repeat a
successor in the representation without changing saturation. -/
def saturatesHead (database : Database) (head : Head) : Prop :=
  database ∈ evolve database head ∧
    ∀ successor ∈ evolve database head, successor = database

def saturated (rules : List Rule) (database : Database) : Prop :=
  ∀ rule ∈ rules, enabled database rule → saturatesHead database rule.head

inductive Reachable (rules : List Rule) : Database → Prop where
  | empty : Reachable rules (fun _ => none)
  | step {database successor : Database} {rule : Rule} :
      Reachable rules database → rule ∈ rules → enabled database rule →
      successor ∈ evolve database rule.head → Reachable rules successor

def solution (rules : List Rule) (database : Database) : Prop :=
  Reachable rules database ∧ saturated rules database

theorem assigned_distinct (database : Database) (keyId value : Nat)
    (unset : database keyId = none) :
    assign database keyId value ≠ database := by
  intro h
  have atKey := congrFun h keyId
  simp [assign, unset] at atKey

theorem open_saturated_iff (database : Database) (keyId value : Nat) :
    saturatesHead database (.openOffer keyId value) ↔
      database keyId ≠ none := by
  cases h : database keyId with
  | none =>
    have differs := assigned_distinct database keyId value h
    simp [saturatesHead, evolve, choose, h, differs]
  | some prior =>
    by_cases same : prior = value <;> simp [saturatesHead, evolve, choose, h, same]

theorem closed_saturated_iff (database : Database) (keyId : Nat) (values : List Nat) :
    saturatesHead database (.closed keyId values) ↔
      ∃ prior ∈ values, database keyId = some prior := by
  cases h : database keyId with
  | none =>
    have differs (value : Nat) := assigned_distinct database keyId value h
    have absent : database ∉ values.flatMap (choose database keyId) := by
      simp only [List.mem_flatMap, choose, h, List.mem_singleton, not_exists, not_and]
      intro value _ equal
      exact differs value equal.symm
    simp [saturatesHead, evolve, absent]
  | some prior =>
    have member (candidate : Database) :
        candidate ∈ values.flatMap (choose database keyId) ↔
          prior ∈ values ∧ candidate = database := by
      simp only [List.mem_flatMap, choose, h]
      constructor
      · rintro ⟨value, inValues, inside⟩
        split at inside
        · rename_i same
          subst value
          exact ⟨inValues, List.mem_singleton.mp inside⟩
        · simp at inside
      · rintro ⟨inValues, rfl⟩
        exact ⟨prior, inValues, by simp⟩
    simp [saturatesHead, evolve, member]

/-- A fact-set step preserves every assigned value. In particular, siblings
cannot overwrite a value already present in their common parent. -/
theorem step_preserves_assignment (database successor : Database)
    (head : Head) (key value : Nat) (present : database key = some value)
    (step : successor ∈ evolve database head) : successor key = some value := by
  have preserves (keyId offer : Nat) (inside : successor ∈ choose database keyId offer) :
      successor key = some value := by
    cases h : database keyId with
    | none =>
      have distinct : key ≠ keyId := by
        intro same
        subst key
        simp [h] at present
      have equal : successor = assign database keyId offer := by
        simpa [choose, h] using inside
      simpa [equal, assign, distinct] using present
    | some prior =>
      by_cases same : prior = offer
      · have equal : successor = database := by simpa [choose, h, same] using inside
        simpa [equal] using present
      · simp [choose, h, same] at inside
  cases head with
  | closed keyId values =>
    obtain ⟨offer, _, inside⟩ := List.mem_flatMap.mp step
    exact preserves keyId offer inside
  | openOffer keyId offer =>
    rcases List.mem_cons.mp step with equal | inside
    · simpa [equal] using present
    · exact preserves keyId offer inside

end Ascent.FiniteChoice
