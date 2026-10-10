-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import PendingKeys

/-! Effective native lattice admission: pending-before-committed lookup,
join, unchanged-value suppression and key-ledger publication. Arbitrary merge
functions are supported for replay equivalence; semilattice growth still needs
JoinLaws. Native hash/equality and field checks remain representation premises. -/
namespace Ascent.LatticeAdmission
open LatticeProjection PendingKeys
variable {Key Value : Type} [DecidableEq Key] [DecidableEq Value]

def overlay (committed : Store Key Value) (ledger : Ledger Key Value) : Store Key Value :=
  fun key => (ledger.table key).or (committed key)

def merged (merge : Value → Value → Value) (prior : Option Value) (incoming : Value) : Value :=
  match prior with | none => incoming | some value => merge value incoming

def effective (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value) : Bool :=
  decide (overlay committed ledger key ≠ some (merged merge (overlay committed ledger key) value))

def admit (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value) : Ledger Key Value :=
  if effective merge committed ledger key value then
    write ledger key (merged merge (overlay committed ledger key) value) else ledger

-- Cost counts newly staged keys; repeated improvements and ineffective joins
-- consume no additional pending slot. The total budget also includes previous
-- consumed work and source materialization, which are external to this ledger.
def cost (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value) : Nat :=
  if effective merge committed ledger key value && (ledger.table key).isNone then 1 else 0

omit [DecidableEq Key] [DecidableEq Value] in
theorem empty_overlay (committed : Store Key Value) : overlay committed empty = committed := by
  funext key
  simp [overlay,empty]

omit [DecidableEq Key] [DecidableEq Value] in
theorem pending_priority (committed : Store Key Value) (ledger : Ledger Key Value)
    (key : Key) (value : Value) (hit : ledger.table key = some value) :
    overlay committed ledger key = some value := by simp [overlay,hit]

omit [DecidableEq Key] [DecidableEq Value] in
theorem committed_fallback (committed : Store Key Value) (ledger : Ledger Key Value)
    (key : Key) (absent : ledger.table key = none) :
    overlay committed ledger key = committed key := by simp [overlay,absent]

theorem admit_covered (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (covered : Covered ledger) (key : Key) (value : Value) :
    Covered (admit merge committed ledger key value) := by
  unfold admit
  split
  · exact write_covered ledger covered key _
  · exact covered

omit [DecidableEq Value] in
theorem overlay_write (committed : Store Key Value) (ledger : Ledger Key Value)
    (key : Key) (value : Value) :
    overlay committed (write ledger key value) =
      fun other => if other = key then some value else overlay committed ledger other := by
  funext other
  by_cases same : other = key <;> simp [overlay,write,same]

theorem ineffective_unchanged (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value)
    (noChange : effective merge committed ledger key value = false) :
    admit merge committed ledger key value = ledger := by simp [admit,noChange]

theorem admission_update_exact (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value) :
    overlay committed (admit merge committed ledger key value) =
      update merge (overlay committed ledger) key value := by
  by_cases changes : effective merge committed ledger key value = true
  · rw [admit,ite_eq_left changes,overlay_write]
    rfl
  · have unchanged : overlay committed ledger key =
        some (merged merge (overlay committed ledger key) value) := by
      simpa [effective] using changes
    rw [admit,ite_eq_right changes]
    funext other
    by_cases same : other = key
    · subst other
      cases prior : overlay committed ledger key <;> simp [update,merged,prior] at * <;> assumption
    · simp [update,same]

def collect (merge : Value → Value → Value) (committed : Store Key Value) :
    Ledger Key Value → List (Key × Value) → Ledger Key Value
  | ledger, [] => ledger
  | ledger, row :: rest => collect merge committed (admit merge committed ledger row.1 row.2) rest

theorem collection_covered (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (covered : Covered ledger) (rows : List (Key × Value)) :
    Covered (collect merge committed ledger rows) := by
  induction rows generalizing ledger with
  | nil => exact covered
  | cons row rest ih => exact ih _ (admit_covered merge committed ledger covered row.1 row.2)

theorem collection_stage_exact (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (rows : List (Key × Value)) :
    overlay committed (collect merge committed ledger rows) =
      stage merge (overlay committed ledger) rows := by
  induction rows generalizing ledger with
  | nil => rfl
  | cons row rest ih =>
      rw [collect,ih,admission_update_exact]
      rfl

theorem empty_collection_stage_exact (merge : Value → Value → Value) (committed : Store Key Value)
    (rows : List (Key × Value)) : overlay committed (collect merge committed empty rows) =
      stage merge committed rows := by rw [collection_stage_exact,empty_overlay]

-- Publication through effective keys reconstructs the merged store, without
-- requiring every incoming row to be recorded as an event.
omit [DecidableEq Value] in
theorem publication_exact (committed : Store Key Value) (ledger : Ledger Key Value)
    (covered : Covered ledger) :
    publish committed (overlay committed ledger) ledger.events = overlay committed ledger := by
  apply publish_exact
  intro key absent
  have noValue : ledger.table key = none := by
    cases found : ledger.table key with
    | none => rfl
    | some value => exact False.elim (absent ((covered key).mpr ⟨value,found⟩))
  exact committed_fallback committed ledger key noValue

theorem collection_publication_exact (merge : Value → Value → Value) (committed : Store Key Value)
    (rows : List (Key × Value)) :
    publish committed (overlay committed (collect merge committed empty rows))
      (collect merge committed empty rows).events = stage merge committed rows := by
  rw [publication_exact committed _ (collection_covered merge committed empty empty_covered rows),
      empty_collection_stage_exact]

omit [DecidableEq Key] in
theorem ineffective_cost_zero (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value)
    (noChange : effective merge committed ledger key value = false) :
    cost merge committed ledger key value = 0 := by simp [cost,noChange]

omit [DecidableEq Key] in
theorem repeated_key_cost_zero (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (prior value : Value)
    (hit : ledger.table key = some prior) : cost merge committed ledger key value = 0 := by
  simp [cost,hit]

omit [DecidableEq Key] in
theorem fresh_effective_cost_one (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (key : Key) (value : Value)
    (changes : effective merge committed ledger key value = true)
    (absent : ledger.table key = none) : cost merge committed ledger key value = 1 := by
  simp [cost,changes,absent]

theorem cost_support_exact (merge : Value → Value → Value) (committed : Store Key Value)
    (ledger : Ledger Key Value) (covered : Covered ledger) (key : Key) (value : Value) :
    cost merge committed ledger key value =
      if effective merge committed ledger key value && decide (key ∉ ledger.events) then 1 else 0 := by
  cases found : ledger.table key with
  | none =>
    have absent : key ∉ ledger.events := by
      intro member
      obtain ⟨prior,hit⟩ := (covered key).mp member
      simp [found] at hit
    simp [cost,found,absent]
  | some prior =>
    have member := (covered key).mpr ⟨prior,found⟩
    simp [cost,found,member]

theorem collection_inflationary (join : JoinLaws Value) (committed : Store Key Value)
    (rows : List (Key × Value)) :
    StoreBelow join committed (overlay committed (collect join.merge committed empty rows)) := by
  rw [empty_collection_stage_exact]
  exact stage_inflationary join committed rows

end Ascent.LatticeAdmission
