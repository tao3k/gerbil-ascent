-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ExecutionPolicy

/-! Arbitrary-length assignment/completion/drain traces, independent of task
count or graph size. The actual Actor owner checks the terminal counts after
joining monitors. Rayon reduces one completion per returned task before publish.
The host primitives' assignment identity, exclusive ownership and join semantics
are explicit representation/runtime boundaries, not inferred from finite TLC. -/
namespace Ascent.ScheduledExecution
structure Ledger where
  assigned : Nat
  completed : Nat
  active : Nat
  drained : Nat
  pending : Nat
  failed : Bool

def Balanced (s : Ledger) : Prop := s.assigned = s.completed + s.active + s.drained
def initial (pending : Nat) : Ledger := ⟨0,0,0,0,pending,false⟩
def dispatch (s : Ledger) : Ledger :=
  {s with assigned := s.assigned + 1, active := s.active + 1, pending := s.pending - 1}
def complete (s : Ledger) : Ledger :=
  {s with completed := s.completed + 1, active := s.active - 1}
def refuse (s : Ledger) : Ledger := {s with failed := true, pending := 0}
def drain (s : Ledger) : Ledger :=
  {s with drained := s.drained + 1, active := s.active - 1}

inductive Step : Ledger → Ledger → Prop where
  | dispatch (s : Ledger) (healthy : s.failed = false) (pending : 0 < s.pending) : Step s (dispatch s)
  | complete (s : Ledger) (active : 0 < s.active) : Step s (complete s)
  | refuse (s : Ledger) : Step s (refuse s)
  | drain (s : Ledger) (failed : s.failed = true) (active : 0 < s.active) : Step s (drain s)

inductive Trace : Ledger → Ledger → Prop where
  | refl (s : Ledger) : Trace s s
  | next {a b c : Ledger} : Trace a b → Step b c → Trace a c

theorem step_balanced {a b : Ledger} (balanced : Balanced a) (step : Step a b) : Balanced b := by
  cases step <;> simp_all [Balanced, dispatch, complete, refuse, drain] <;> omega

theorem trace_balanced (tasks : Nat) (s : Ledger) (trace : Trace (initial tasks) s) : Balanced s := by
  have preserve : ∀ {a b : Ledger}, Trace a b → Balanced a → Balanced b := by
    intro a b path
    induction path with
    | refl => exact id
    | next _ step ih => exact fun balanced => step_balanced (ih balanced) step
  exact preserve trace rfl

def numbers (s : Ledger) : String → Nat
  | "assigned" => s.assigned
  | "completed" => s.completed
  | "active" => s.active
  | "pending" => s.pending
  | _ => 0
def flags (s : Ledger) (joined : Bool) : String → Bool
  | "failed" => s.failed
  | "joined" => joined
  | _ => false

theorem terminal_certificate (s : Ledger) (joined : Bool)
    (accepted : ExecutionPolicy.eval (numbers s) (flags s joined) ExecutionPolicy.joinedRound = true) :
    s.failed = false ∧ joined = true ∧ s.assigned = s.completed ∧ s.active = 0 ∧ s.pending = 0 := by
  simpa [numbers, flags] using (ExecutionPolicy.joined_round_exact (numbers s) (flags s joined)).mp accepted

theorem refusal_persistent {a b : Ledger} (path : Trace a b) (failed : a.failed = true) : b.failed = true := by
  induction path with
  | refl => exact failed
  | next _ step ih =>
      cases step with
      | dispatch healthy _ => simp_all
      | complete => exact ih
      | refuse => rfl
      | drain => exact ih

theorem successful_terminal_has_no_drain (s : Ledger) (joined : Bool)
    (balanced : Balanced s)
    (accepted : ExecutionPolicy.eval (numbers s) (flags s joined) ExecutionPolicy.joinedRound = true) :
    s.drained = 0 := by
  have terminal := terminal_certificate s joined accepted
  simp only [Balanced] at balanced
  omega

end Ascent.ScheduledExecution
