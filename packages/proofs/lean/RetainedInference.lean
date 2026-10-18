-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Lean
namespace Ascent.RetainedInference
-- Answer admission requires exact source and query identity, independently of
-- whether a query path can be retained and evaluated against a new source.
def Admit (source cachedSource : Nat) (query cachedQuery : Nat) :=
  source = cachedSource ∧ query = cachedQuery
theorem admitted_answer_sound (evaluate : Nat → Nat → α)
    (h : Admit source cachedSource query cachedQuery) :
    evaluate source query = evaluate cachedSource cachedQuery := by
  rcases h with ⟨rfl, rfl⟩
  rfl
theorem changed_source_rejects_answer (h : source ≠ cachedSource) :
    ¬ Admit source cachedSource query cachedQuery := fun admitted => h admitted.1
theorem changed_query_rejects_answer (h : query ≠ cachedQuery) :
    ¬ Admit source cachedSource query cachedQuery := fun admitted => h admitted.2
def ExtendEvidence (mentor : Actor → Actor → Prop) (eligible : Actor → Film → Prop) (a : Actor) :=
  ∃ y z f, mentor a y ∧ mentor y z ∧ eligible z f
-- A later query may extend a previously established subgoal only while its
-- relation is extensionally equal to evidence over the current source.
theorem subgoal_extension_sound (mentor : Actor → Actor → Prop)
    (eligible cached : Actor → Film → Prop)
    (h : ∀ z f, eligible z f ↔ cached z f) :
    ExtendEvidence mentor eligible a ↔ ExtendEvidence mentor cached a := by
  constructor
  · rintro ⟨y,z,f,hxy,hyz,he⟩
    exact ⟨y,z,f,hxy,hyz,(h z f).mp he⟩
  · rintro ⟨y,z,f,hxy,hyz,he⟩
    exact ⟨y,z,f,hxy,hyz,(h z f).mpr he⟩
def bit (id n : Nat) := id / 2^n % 2 == 1
def current (id phase : Nat) := if phase == 1 && bit id 2 then id-4 else id
def answer (id : Nat) :=
  (if bit id 0 || (bit id 1 && bit id 2) then 1 else 0) + (if bit id 2 then 2 else 0)
def grade (n : Nat) :=
  let id := n/2; let phase := n%2; let now := current id phase
  [id,phase,now,answer now,if id == now then 1 else 0]
def corpus := (List.range 32).map grade
theorem withdrawal_is_observable : answer 4 = 2 ∧ answer (current 4 1) = 0 := by decide
theorem all_changed_sources_reject_old_answer :
    ∀ id : Fin 16, current id 1 ≠ id → ¬ Admit (current id 1) id 0 0 := by
  intro id h
  exact changed_source_rejects_answer h
def check (args : List String) : IO Unit := do
  unless args.length > 0 do throw (IO.userError "expected correspondence paths")
  for path in args do
    let parsed ← match Lean.Json.parse (← IO.FS.readFile path) with
      | .ok x => pure x
      | .error e => throw (IO.userError e)
    unless parsed == Lean.toJson corpus do throw (IO.userError s!"retained inference differs: {path}")
  IO.println "RETAINED-INFERENCE-LEAN-OK observations=32"
end Ascent.RetainedInference
def main := Ascent.RetainedInference.check
