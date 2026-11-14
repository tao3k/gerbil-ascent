-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import FiniteHeight

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

/-- This is the branch decision in Scheme's offer scan, expressed in
terms of the assigned value and the grounded alternatives. -/
def acceptsHead (database : Database) : Head → Prop
  | .openOffer keyId _ => database keyId ≠ none
  | .closed keyId values => ∃ prior ∈ values, database keyId = some prior

theorem accepts_head_exact (database : Database) (head : Head) :
    acceptsHead database head ↔ saturatesHead database head := by
  cases head with
  | closed keyId values => exact (closed_saturated_iff database keyId values).symm
  | openOffer keyId value => exact (open_saturated_iff database keyId value).symm

/-- The Scheme scan can only introduce values for an unset key. Accepted
self steps are already represented by the current state. -/
def offersExtension (database successor : Database) : Head → Prop
  | .openOffer keyId value =>
      database keyId = none ∧ successor = assign database keyId value
  | .closed keyId values =>
      database keyId = none ∧ ∃ offer ∈ values, successor = assign database keyId offer

theorem offers_extension_exact (database successor : Database) (head : Head) :
    offersExtension database successor head ↔
      successor ≠ database ∧ successor ∈ evolve database head := by
  cases head with
  | openOffer keyId value =>
    cases h : database keyId with
    | none =>
      have differs := assigned_distinct database keyId value h
      simp [offersExtension, evolve, choose, h, and_or_left, and_comm]
      exact fun same => same ▸ differs
    | some prior =>
      by_cases own : prior = value <;> simp [offersExtension, evolve, choose, h, own]
  | closed keyId values =>
    cases h : database keyId with
    | none =>
      simp only [offersExtension, evolve, List.mem_flatMap, choose, h, List.mem_singleton,
        true_and]
      constructor
      · rintro ⟨offer, allowed, rfl⟩
        exact ⟨assigned_distinct database keyId offer h, offer, allowed, rfl⟩
      · exact And.right
    | some prior =>
      simp only [offersExtension, evolve, h, reduceCtorEq, false_and, List.mem_flatMap,
        choose]
      refine ⟨False.elim, ?_⟩
      rintro ⟨different, offer, _, chosen⟩
      split at chosen
      · exact different (List.mem_singleton.mp chosen)
      · simp at chosen

/-- Strict successors omit self steps before scheduling. -/
def StrictStep (rules : List Rule) (before after : Database) : Prop :=
  before ≠ after ∧ ∃ rule ∈ rules, enabled before rule ∧ after ∈ evolve before rule.head

/-- Closing the worklist establishes completeness. The initial empty database
was scheduled, each discovered database was processed, and each processed
database registered every strict successor. -/
theorem exhausted_worklist_complete (rules : List Rule) (processed : Database → Prop)
    (initial : processed (fun _ => none))
    (closed : ∀ before after, processed before → StrictStep rules before after → processed after)
    {database : Database} (reached : Reachable rules database) : processed database := by
  induction reached with
  | empty => exact initial
  | @step before successor rule _ hRule hEnabled hNext ih =>
    by_cases same : before = successor
    · simpa [← same] using ih
    · exact closed before successor ih ⟨same, rule, hRule, hEnabled, hNext⟩

theorem exhausted_answers_exact (rules : List Rule)
    (processed accepted : Database → Prop)
    (initial : processed (fun _ => none))
    (closed : ∀ before after, processed before → StrictStep rules before after → processed after)
    (sound : ∀ database, processed database → Reachable rules database)
    (publish : ∀ database, accepted database ↔ processed database ∧ saturated rules database)
    (database : Database) : accepted database ↔ solution rules database := by
  rw [publish]
  exact ⟨fun h => ⟨sound database h.1, h.2⟩,
         fun h => ⟨exhausted_worklist_complete rules processed initial closed h.1, h.2⟩⟩

/-- The Scheme state budget charges a distinct discovery, including the
empty database. The processed and pending keys together form seen. An
unseen successor cannot exhaust a budget that covers the finite universe. -/
theorem fresh_discovery_fits_budget {State : Type} [DecidableEq State]
    (states seen : List State) (budget : Nat) (next : State)
    (covered : states.length ≤ budget) (distinct : seen.Nodup)
    (inside : seen ⊆ states) (legal : next ∈ states) (fresh : next ∉ seen) :
    seen.length < budget := by
  have sub : next :: seen ⊆ states := by
    intro value member
    rcases List.mem_cons.mp member with rfl | previous
    · exact legal
    · exact inside previous
  have length := List.Nodup.length_le_of_subset (List.nodup_cons.mpr ⟨fresh, distinct⟩) sub
  exact Nat.lt_of_succ_le (Nat.le_trans length covered)

/-- The Scheme worklist marks a state as seen before putting it on the
pending list. After popping the active state, every outgoing strict edge
is covered either by an earlier discovery or by an entry added now. -/
theorem register_successors_closes_cut {State : Type}
    (seen discoveries : State → Prop) (edge : State → State → Prop) (active : State)
    (recorded : ∀ next, edge active next → ¬ seen next → discoveries next) :
    ∀ next, edge active next → seen next ∨ discoveries next := by
  intro next reachable
  by_cases known : seen next
  · exact Or.inl known
  · exact Or.inr (recorded next reachable known)

theorem worklist_drain_covers_discovery {State : Type}
    (seen queued processed : State → Prop)
    (partition : ∀ state, seen state ↔ queued state ∨ processed state)
    (done : ∀ state, ¬ queued state) :
    ∀ state, seen state ↔ processed state := by
  intro state
  rw [partition]
  exact ⟨fun h => h.resolve_left (done state), Or.inr⟩

/-- Each coordinate is unset or one of the admitted values. -/
def finiteDatabases (attributes values : Nat) :
    List (Fin attributes → Fin (values + 1)) :=
  Ascent.enumerateTables (List.finRange (values + 1)) attributes

theorem finite_databases_count (attributes values : Nat) :
    (finiteDatabases attributes values).length = (values + 1) ^ attributes := by
  simp [finiteDatabases, Ascent.enumerate_tables_length]

theorem finite_databases_complete (attributes values : Nat)
    (database : Fin attributes → Fin (values + 1)) :
    database ∈ finiteDatabases attributes values :=
  Ascent.enumerate_tables_complete _ List.mem_finRange _ database

/-- Abstract a single Scheme search iteration as removing the active
entry and appending previously unseen strict successors. Seen includes
both processed and pending entries. -/
structure Worklist where
  seen : Nat
  pending : Nat
  processed : Nat

def Worklist.counts (state : Worklist) : Prop :=
  state.seen = state.pending + state.processed

def Worklist.advance (state : Worklist) (discoveries : Nat) : Worklist :=
  ⟨state.seen + discoveries, state.pending - 1 + discoveries, state.processed + 1⟩

theorem worklist_counts_preserved (state : Worklist) (discoveries : Nat)
    (counts : state.counts) (pending : 0 < state.pending) :
    (state.advance discoveries).counts := by
  simp only [Worklist.counts, Worklist.advance] at *
  omega

/-- Processing increases the count exactly once even if it adds many
successors. Together with the finite discovery bound this excludes an
infinite loop of successful iterations. -/
theorem worklist_budget_decreases (state : Worklist) (discoveries budget : Nat)
    (counts : state.counts) (pending : 0 < state.pending)
    (covered : state.seen ≤ budget) :
    budget - (state.advance discoveries).processed < budget - state.processed := by
  simp only [Worklist.counts, Worklist.advance] at *
  omega

end Ascent.FiniteChoice
