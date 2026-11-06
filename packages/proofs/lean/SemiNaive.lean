-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderFrontier

/-! Synchronous positive Set iteration with a monotone concrete view.
Initial execution is full; later rounds read exact concrete deltas.
Not native extraction or the general abstract-lattice gamma/injection theorem. -/
namespace Ascent.SemiNaive
open ProviderFrontier

structure Rule (Key Env Row : Type) where
  keys : List Key
  seed : Env
  emit : Env → Row

variable {Key Env Row : Type}

def consequences (rules : List (Rule Key Env Row))
    (relations : Key → Env → Env → Prop) (row : Row) : Prop :=
  ∃ rule ∈ rules, output (body relations rule.keys rule.seed) rule.emit row

def freshConsequences (rules : List (Rule Key Env Row))
    (old next : Key → Env → Env → Prop) (row : Row) : Prop :=
  ∃ rule ∈ rules, output (pivots old next rule.keys rule.seed) rule.emit row

theorem consequences_partition (rules : List (Rule Key Env Row))
    (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (row : Row) :
    consequences rules next row ↔
      consequences rules old row ∨ freshConsequences rules old next row := by
  constructor
  · rintro ⟨rule, member, derivation⟩
    rcases (projected_partition old next grows rule.keys rule.seed rule.emit row).mp
      derivation with prior | fresh
    · exact Or.inl ⟨rule, member, prior⟩
    · exact Or.inr ⟨rule, member, fresh⟩
  · intro admitted
    rcases admitted with ⟨rule, member, derivation⟩ | ⟨rule, member, derivation⟩
    · exact ⟨rule, member, (projected_partition old next grows
        rule.keys rule.seed rule.emit row).mpr (Or.inl derivation)⟩
    · exact ⟨rule, member, (projected_partition old next grows
        rule.keys rule.seed rule.emit row).mpr (Or.inr derivation)⟩

abbrev Database (Row : Type) := Row → Prop
abbrev View (Key Env Row : Type) := Database Row → Key → Env → Env → Prop

def ViewMonotone (view : View Key Env Row) : Prop :=
  ∀ before after, (∀ row, before row → after row) →
    ∀ key input output, view before key input output → view after key input output

def fullStep (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (known : Database Row) : Database Row :=
  fun row => known row ∨ consequences rules (view known) row

def pivotStep (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (old known : Database Row) : Database Row :=
  fun row => known row ∨ freshConsequences rules (view old) (view known) row

def naive (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (initial : Database Row) : Nat → Database Row
  | 0 => initial
  | n + 1 => fullStep rules view (naive rules view initial n)

/-- Consecutive concrete snapshots; no mailbox or scheduler replica. -/
def semiNaive (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (initial : Database Row) : Nat → Database Row × Database Row
  | 0 => (initial, fullStep rules view initial)
  | n + 1 =>
      let prior := semiNaive rules view initial n
      (prior.2, pivotStep rules view prior.1 prior.2)

/-- All-old heads were included by the preceding consequence step.
The history premise is derived; completion is not assumed. -/
theorem pivot_after_full (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view) (old : Database Row) :
    pivotStep rules view old (fullStep rules view old) =
      fullStep rules view (fullStep rules view old) := by
  funext row
  apply propext
  have grows := monotone old (fullStep rules view old) (fun _ h => Or.inl h)
  constructor
  · intro admitted
    rcases admitted with known | fresh
    · exact Or.inl known
    · exact Or.inr ((consequences_partition rules _ _ grows row).mpr (Or.inr fresh))
  · intro admitted
    rcases admitted with known | full
    · exact Or.inl known
    · rcases (consequences_partition rules _ _ grows row).mp full with prior | fresh
      · exact Or.inl (Or.inr prior)
      · exact Or.inr fresh

/-- Every natural-number round agrees; no cutoff or completed-solve premise. -/
theorem iterations_equal (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view)
    (initial : Database Row) (n : Nat) :
    semiNaive rules view initial n =
      (naive rules view initial n, naive rules view initial (n + 1)) := by
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [semiNaive, ih, naive]
      rw [pivot_after_full rules view monotone]

end Ascent.SemiNaive

/-! The first fresh occurrence partitions witnesses, whereas the original
`ProviderFrontier.pivots` permits overlap. No assumption about projected-head
uniqueness is made: different witnesses can still derive the same fact. -/
namespace Ascent.SemiNaive
open ProviderFrontier
variable {Key Env Row : Type}

def disjointPivots (old next : Key → Env → Env → Prop) : List Key → Env → Env → Prop
  | [], _, _ => False
  | key :: rest, input, output =>
      (∃ middle, changed (old key) (next key) input middle ∧ body next rest middle output) ∨
      (∃ middle, old key input middle ∧ disjointPivots old next rest middle output)

theorem disjoint_partition (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (keys : List Key) (input output : Env) :
    body next keys input output ↔
      body old keys input output ∨ disjointPivots old next keys input output := by
  classical
  induction keys generalizing input output with
  | nil => simp [body, disjointPivots]
  | cons key rest ih =>
    constructor
    · rintro ⟨middle, first, tail⟩
      by_cases prior : old key input middle
      · rcases (ih middle output).mp tail with oldTail | freshTail
        · exact Or.inl ⟨middle, prior, oldTail⟩
        · exact Or.inr (Or.inr ⟨middle, prior, freshTail⟩)
      · exact Or.inr (Or.inl ⟨middle, ⟨first, prior⟩, tail⟩)
    · intro admitted
      rcases admitted with ⟨middle, first, tail⟩ | fresh
      · exact ⟨middle, grows key input middle first, (ih middle output).mpr (Or.inl tail)⟩
      · rcases fresh with ⟨middle, first, tail⟩ | ⟨middle, first, tail⟩
        · exact ⟨middle, first.1, tail⟩
        · exact ⟨middle, grows key input middle first, (ih middle output).mpr (Or.inr tail)⟩

/-- A concrete body witness records whether each matched tuple is fresh. -/
def FirstFresh : List Bool → Nat → Prop
  | true :: _, 0 => True
  | false :: rest, n + 1 => FirstFresh rest n
  | _, _ => False

theorem first_fresh_unique (marks : List Bool) (i j : Nat)
    (left : FirstFresh marks i) (right : FirstFresh marks j) : i = j := by
  induction marks generalizing i j with
  | nil => simp [FirstFresh] at left
  | cons mark rest ih =>
    cases mark <;> cases i <;> cases j <;> simp_all [FirstFresh]
    exact ih _ _ left right

theorem all_old_not_scheduled (marks : List Bool) (allOld : ∀ m ∈ marks, m = false)
    (i : Nat) : ¬ FirstFresh marks i := by
  induction marks generalizing i with
  | nil => simp [FirstFresh]
  | cons mark rest ih =>
    have hm : mark = false := allOld mark (by simp)
    subst mark
    cases i with
    | zero => simp [FirstFresh]
    | succ i => exact ih (fun m h => allOld m (by simp [h])) i

/-- Equality of consecutive admitted rounds implies closure; budget exhaustion
or an empty worker mailbox does not provide this premise. -/
theorem settled_is_closed (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (monotone : ViewMonotone view) (initial : Database Row) (n : Nat)
    (settled : (semiNaive rules view initial n).1 = (semiNaive rules view initial n).2) :
    fullStep rules view (naive rules view initial n) = naive rules view initial n := by
  rw [iterations_equal rules view monotone initial n] at settled
  exact settled.symm

/-- Independent leastness argument for every finite round, without assuming
that a solver has completed. -/
theorem naive_below_closed (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (monotone : ViewMonotone view) (initial bound : Database Row)
    (seed : ∀ row, initial row → bound row)
    (closed : ∀ row, fullStep rules view bound row → bound row) (n : Nat) :
    ∀ row, naive rules view initial n row → bound row := by
  induction n with
  | zero => exact seed
  | succ n ih =>
    intro row admitted
    rcases admitted with prior | ⟨rule, member, env, derivation, emitted⟩
    · exact ih row prior
    · apply closed row
      right
      refine ⟨rule, member, env, ?_, emitted⟩
      -- Body transitions are monotone in the database.
      have lift : ∀ keys input output,
          body (view (naive rules view initial n)) keys input output →
          body (view bound) keys input output := by
        intro keys
        induction keys with
        | nil => exact fun _ _ h => h
        | cons key rest tail =>
          rintro input output ⟨middle, first, more⟩
          exact ⟨middle, monotone _ _ ih key input middle first, tail middle output more⟩
      exact lift rule.keys rule.seed env derivation

def disjointStep (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (old known : Database Row) : Database Row := fun row => known row ∨
      ∃ rule ∈ rules, output (disjointPivots (view old) (view known) rule.keys rule.seed) rule.emit row

theorem disjoint_after_full (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view) (old : Database Row) :
    disjointStep rules view old (fullStep rules view old) =
      fullStep rules view (fullStep rules view old) := by
  funext row
  apply propext
  have grows := monotone old (fullStep rules view old) (fun _ h => Or.inl h)
  constructor
  · intro admitted
    rcases admitted with known | ⟨rule, member, env, fresh, emitted⟩
    · exact Or.inl known
    · exact Or.inr ⟨rule, member, env,
        (disjoint_partition _ _ grows rule.keys rule.seed env).mpr (Or.inr fresh), emitted⟩
  · intro admitted
    rcases admitted with known | ⟨rule, member, env, full, emitted⟩
    · exact Or.inl known
    · rcases (disjoint_partition _ _ grows rule.keys rule.seed env).mp full with prior | fresh
      · exact Or.inl (Or.inr ⟨rule, member, env, prior, emitted⟩)
      · exact Or.inr ⟨rule, member, env, fresh, emitted⟩

def disjointIteration (rules : List (Rule Key Env Row)) (view : View Key Env Row)
    (initial : Database Row) : Nat → Database Row × Database Row
  | 0 => (initial, fullStep rules view initial)
  | n + 1 =>
      let prior := disjointIteration rules view initial n
      (prior.2, disjointStep rules view prior.1 prior.2)

theorem disjoint_iterations_equal (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view)
    (initial : Database Row) (n : Nat) :
    disjointIteration rules view initial n =
      (naive rules view initial n, naive rules view initial (n + 1)) := by
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [disjointIteration, ih, naive]
      rw [disjoint_after_full rules view monotone]

theorem disjoint_settled_is_least (rules : List (Rule Key Env Row))
    (view : View Key Env Row) (monotone : ViewMonotone view)
    (initial : Database Row) (n : Nat)
    (settled : (disjointIteration rules view initial n).1 = (disjointIteration rules view initial n).2) :
    fullStep rules view (naive rules view initial n) = naive rules view initial n ∧
    ∀ bound, (∀ row, initial row → bound row) →
      (∀ row, fullStep rules view bound row → bound row) →
      ∀ row, naive rules view initial n row → bound row := by
  rw [disjoint_iterations_equal rules view monotone initial n] at settled
  exact ⟨settled.symm, fun bound seed closed =>
    naive_below_closed rules view monotone initial bound seed closed n⟩

end Ascent.SemiNaive
