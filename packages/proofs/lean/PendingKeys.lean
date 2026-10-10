-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import LatticeProjection

/-! Native pending-table/event-roster representation contract. Only effective
writes enter this ledger; join evaluation and the decision to write are external.
Hash lookup must refine the functional table and field equality below. -/
namespace Ascent.PendingKeys
open LatticeProjection
variable {Key Value : Type} [DecidableEq Key]

structure Ledger (Key Value : Type) where
  table : Store Key Value
  events : List Key

def empty : Ledger Key Value := ⟨fun _ => none, []⟩
def Covered (ledger : Ledger Key Value) : Prop :=
  ∀ key, key ∈ ledger.events ↔ ∃ value, ledger.table key = some value

def write (ledger : Ledger Key Value) (key : Key) (value : Value) : Ledger Key Value :=
  ⟨fun other => if other = key then some value else ledger.table other,
   key :: ledger.events⟩

omit [DecidableEq Key] in
theorem empty_covered : Covered (empty : Ledger Key Value) := by
  intro key
  simp [empty]

theorem write_covered (ledger : Ledger Key Value) (covered : Covered ledger)
    (key : Key) (value : Value) : Covered (write ledger key value) := by
  intro other
  by_cases same : other = key
  · subst other
    simp [write]
  · simpa [write,same] using covered other

def replay : Ledger Key Value → List (Key × Value) → Ledger Key Value
  | ledger, [] => ledger
  | ledger, row :: rest => replay (write ledger row.1 row.2) rest

theorem replay_covered (ledger : Ledger Key Value) (covered : Covered ledger)
    (rows : List (Key × Value)) : Covered (replay ledger rows) := by
  induction rows generalizing ledger with
  | nil => exact covered
  | cons row rest ih => exact ih _ (write_covered ledger covered row.1 row.2)

-- List order and repeated events are intentionally irrelevant to membership.
-- Each visited key is read from the final pending table, never from an event's
-- earlier value. This is the native visited-table publication seam.
def materialized (ledger : Ledger Key Value) (row : Key × Value) : Prop :=
  row.1 ∈ ledger.events ∧ ledger.table row.1 = some row.2

omit [DecidableEq Key] in
theorem materialization_exact (ledger : Ledger Key Value) (covered : Covered ledger)
    (row : Key × Value) : materialized ledger row ↔ gamma ledger.table row := by
  constructor
  · exact fun h => h.2
  · intro hit
    exact ⟨(covered row.1).mpr ⟨row.2,hit⟩,hit⟩

omit [DecidableEq Key] in
theorem materialization_unique (ledger : Ledger Key Value) (key : Key) (a b : Value)
    (first : materialized ledger (key,a)) (second : materialized ledger (key,b)) : a = b := by
  exact gamma_unique ledger.table key a b first.2 second.2

theorem repeated_key_final (ledger : Ledger Key Value) (key : Key) (a b : Value) :
    (write (write ledger key a) key b).table key = some b := by simp [write]

theorem write_untouched (ledger : Ledger Key Value) (key other : Key) (value : Value)
    (different : other ≠ key) : (write ledger key value).table other = ledger.table other := by
  simp [write,different]

end Ascent.PendingKeys
