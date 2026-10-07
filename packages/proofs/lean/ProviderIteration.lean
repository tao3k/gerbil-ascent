-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderAdmission
import SemiNaive
import FiniteHeight

/-! Abstract join/injection and merged-snapshot positive iteration. Laws are
semantic Provider obligations, not inferred from Scheme procedure shapes.
The abstract state need not be a powerset; gamma need not preserve joins.
Delta may overlap old facts. Native extraction and scheduling remain separate. -/
namespace Ascent.ProviderIteration

structure CompleteJoin (State : Type) where
  le : State → State → Prop
  refl : ∀ s, le s s
  trans : ∀ a b c, le a b → le b c → le a c
  antisymm : ∀ a b, le a b → le b a → a = b
  sup : (State → Prop) → State
  upper : ∀ family s, family s → le s (sup family)
  least : ∀ family bound, (∀ s, family s → le s bound) → le (sup family) bound

def join (l : CompleteJoin State) (a b : State) : State :=
  l.sup (fun s => s = a ∨ s = b)

theorem join_left (l : CompleteJoin State) (a b : State) : l.le a (join l a b) :=
  l.upper _ a (Or.inl rfl)
theorem join_right (l : CompleteJoin State) (a b : State) : l.le b (join l a b) :=
  l.upper _ b (Or.inr rfl)
theorem join_le (l : CompleteJoin State) (a b c : State)
    (ha : l.le a c) (hb : l.le b c) : l.le (join l a b) c := by
  apply l.least
  intro s hs
  rcases hs with rfl | rfl
  · exact ha
  · exact hb

theorem join_mono (l : CompleteJoin State) (a b c d : State)
    (ha : l.le a c) (hb : l.le b d) : l.le (join l a b) (join l c d) :=
  join_le l _ _ _ (l.trans _ _ _ ha (join_left l c d))
    (l.trans _ _ _ hb (join_right l c d))

-- Injection is the abstract supremum of tuple injections. It is not gamma's
-- inverse, and can expose implied rows absent from the input tuple family.
def inject (l : CompleteJoin State) (head : Row → State) (rows : Row → Prop) : State :=
  l.sup (fun state => ∃ row, rows row ∧ head row = state)

theorem inject_upper (l : CompleteJoin State) (head : Row → State)
    (rows : Row → Prop) (row : Row) (hit : rows row) : l.le (head row) (inject l head rows) :=
  l.upper _ _ ⟨row,hit,rfl⟩

theorem inject_le (l : CompleteJoin State) (head : Row → State)
    (rows : Row → Prop) (bound : State) (caps : ∀ row, rows row → l.le (head row) bound) :
    l.le (inject l head rows) bound := by
  apply l.least
  rintro state ⟨row,hit,rfl⟩
  exact caps row hit

theorem inject_mono (l : CompleteJoin State) (head : Row → State)
    (a b : Row → Prop) (included : ∀ row, a row → b row) :
    l.le (inject l head a) (inject l head b) :=
  inject_le l head a _ (fun row hit => inject_upper l head b row (included row hit))

theorem inject_union (l : CompleteJoin State) (head : Row → State) (a b : Row → Prop) :
    inject l head (fun r => a r ∨ b r) = join l (inject l head a) (inject l head b) := by
  apply l.antisymm
  · apply inject_le
    intro row hit
    rcases hit with ha | hb
    · exact l.trans _ _ _ (inject_upper l head a row ha) (join_left l _ _)
    · exact l.trans _ _ _ (inject_upper l head b row hb) (join_right l _ _)
  · exact join_le l _ _ _ (inject_mono l head _ _ (fun _ h => Or.inl h))
      (inject_mono l head _ _ (fun _ h => Or.inr h))

structure Program (State Key Env Row : Type) where
  lattice : CompleteJoin State
  head : Row → State
  rules : List (SemiNaive.Rule Key Env Row)
  gamma : State → Key → Env → Env → Prop
  gamma_mono : ∀ a b, lattice.le a b → ∀ k x y, gamma a k x y → gamma b k x y
  delta : State → State → Key → Env → Env → Prop
  delta_sound : ∀ a b, lattice.le a b → ∀ k x y, delta a b k x y → gamma b k x y
  delta_covers : ∀ a b, lattice.le a b → ∀ k x y,
    gamma b k x y → ¬ gamma a k x y → delta a b k x y

def heads (p : Program State Key Env Row) (s : State) : Row → Prop :=
  SemiNaive.consequences p.rules (p.gamma s)
def freshHeads (p : Program State Key Env Row) (a b : State) : Row → Prop :=
  fun row => ∃ rule ∈ p.rules, ProviderFrontier.output
    (ProviderAdmission.providerPivots (p.delta a b) (p.gamma b) rule.keys rule.seed) rule.emit row

theorem heads_partition (p : Program State Key Env Row) (a b : State)
    (grows : p.lattice.le a b) (row : Row) :
    heads p b row ↔ heads p a row ∨ freshHeads p a b row := by
  have body := ProviderAdmission.provider_body_partition (p.gamma a) (p.gamma b) (p.delta a b)
    (p.gamma_mono a b grows) (fun k x y h => p.delta_covers a b grows k x y h.1 h.2)
    (p.delta_sound a b grows)
  constructor
  · rintro ⟨rule,member,env,hit,emitted⟩
    rcases (body rule.keys rule.seed env).mp hit with old | fresh
    · exact Or.inl ⟨rule,member,env,old,emitted⟩
    · exact Or.inr ⟨rule,member,env,fresh,emitted⟩
  · intro hit
    rcases hit with ⟨rule,member,env,old,emitted⟩ | ⟨rule,member,env,fresh,emitted⟩
    · exact ⟨rule,member,env,(body rule.keys rule.seed env).mpr (Or.inl old),emitted⟩
    · exact ⟨rule,member,env,(body rule.keys rule.seed env).mpr (Or.inr fresh),emitted⟩

def fullStep (p : Program State Key Env Row) (s : State) : State :=
  join p.lattice s (inject p.lattice p.head (heads p s))
def pivotStep (p : Program State Key Env Row) (a b : State) : State :=
  join p.lattice b (inject p.lattice p.head (freshHeads p a b))

theorem full_grows (p : Program State Key Env Row) (s : State) : p.lattice.le s (fullStep p s) :=
  join_left p.lattice _ _

theorem heads_mono (p : Program State Key Env Row) (a b : State)
    (grows : p.lattice.le a b) : ∀ row, heads p a row → heads p b row := by
  intro row hit
  exact (heads_partition p a b grows row).mpr (Or.inl hit)

theorem full_mono (p : Program State Key Env Row) (a b : State)
    (grows : p.lattice.le a b) : p.lattice.le (fullStep p a) (fullStep p b) :=
  join_mono p.lattice _ _ _ _ grows
    (inject_mono p.lattice p.head _ _ (heads_mono p a b grows))

-- All-old head injections are already subsumed by the retained abstract state.
-- This is derived from full execution history, not assumed as completed solving.
theorem pivot_after_full (p : Program State Key Env Row) (a : State) :
    pivotStep p a (fullStep p a) = fullStep p (fullStep p a) := by
  let b := fullStep p a
  have grows : p.lattice.le a b := full_grows p a
  apply p.lattice.antisymm
  · exact join_mono p.lattice _ _ _ _ (p.lattice.refl b)
      (inject_mono p.lattice p.head _ _ (fun row hit =>
        (heads_partition p a b grows row).mpr (Or.inr hit)))
  · apply join_le
    · exact join_left p.lattice _ _
    · apply inject_le
      intro row hit
      rcases (heads_partition p a b grows row).mp hit with old | fresh
      · exact p.lattice.trans _ _ _
          (p.lattice.trans _ _ _ (inject_upper p.lattice p.head _ row old)
            (join_right p.lattice a _)) (join_left p.lattice b _)
      · exact p.lattice.trans _ _ _ (inject_upper p.lattice p.head _ row fresh)
          (join_right p.lattice b _)

def naive (p : Program State Key Env Row) (initial : State) : Nat → State :=
  Ascent.iterateStep (fullStep p) initial

def semiNaive (p : Program State Key Env Row) (initial : State) : Nat → State × State
  | 0 => (initial,fullStep p initial)
  | n+1 => let prior := semiNaive p initial n
           (prior.2,pivotStep p prior.1 prior.2)

theorem iterations_equal (p : Program State Key Env Row) (initial : State) (n : Nat) :
    semiNaive p initial n = (naive p initial n,naive p initial (n+1)) := by
  induction n with
  | zero => rfl
  | succ n ih =>
      simp only [semiNaive,ih,naive,Ascent.iterateStep]
      rw [pivot_after_full]

-- Fixed points reached from initial are least among all closed upper bounds.
-- No assumption that gamma commutes with abstract joins is used.
theorem history_below_closed (p : Program State Key Env Row) (initial bound : State)
    (above : p.lattice.le initial bound) (closed : p.lattice.le (fullStep p bound) bound)
    (n : Nat) : p.lattice.le (naive p initial n) bound := by
  induction n with
  | zero => exact above
  | succ n ih => exact p.lattice.trans _ _ _ (full_mono p _ bound ih) closed

theorem initial_below_history (p : Program State Key Env Row) (initial : State) (n : Nat) :
    p.lattice.le initial (naive p initial n) := by
  induction n with
  | zero => exact p.lattice.refl initial
  | succ n ih => exact p.lattice.trans _ _ _ ih (full_grows p _)

theorem stationary_least (p : Program State Key Env Row) (initial : State) (n : Nat)
    (stationary : fullStep p (naive p initial n) = naive p initial n) :
    p.lattice.le initial (naive p initial n) ∧
    p.lattice.le (fullStep p (naive p initial n)) (naive p initial n) ∧
    ∀ bound, p.lattice.le initial bound → p.lattice.le (fullStep p bound) bound →
      p.lattice.le (naive p initial n) bound := by
  refine ⟨initial_below_history p initial n,?_,
    fun bound above closed => history_below_closed p initial bound above closed n⟩
  rw [stationary]
  exact p.lattice.refl _

-- Tarski construction from complete joins: the supremum of all common lower
-- bounds of closed states above the seed. Existence does not imply finite or
-- omega-round convergence of an arbitrary infinite-height abstract domain.
def closedBounds (p : Program State Key Env Row) (initial bound : State) : Prop :=
  p.lattice.le initial bound ∧ p.lattice.le (fullStep p bound) bound
def leastState (p : Program State Key Env Row) (initial : State) : State :=
  p.lattice.sup (fun lower => ∀ bound, closedBounds p initial bound → p.lattice.le lower bound)

theorem least_below_closed (p : Program State Key Env Row) (initial bound : State)
    (closed : closedBounds p initial bound) : p.lattice.le (leastState p initial) bound :=
  p.lattice.least _ bound (fun _ lower => lower bound closed)

theorem seed_below_least (p : Program State Key Env Row) (initial : State) :
    p.lattice.le initial (leastState p initial) :=
  p.lattice.upper _ initial (fun _ bound => bound.1)

theorem least_closed (p : Program State Key Env Row) (initial : State) :
    p.lattice.le (fullStep p (leastState p initial)) (leastState p initial) := by
  apply p.lattice.upper
  intro bound closed
  exact p.lattice.trans _ _ _
    (full_mono p _ bound (least_below_closed p initial bound closed)) closed.2

theorem least_fixed (p : Program State Key Env Row) (initial : State) :
    fullStep p (leastState p initial) = leastState p initial :=
  p.lattice.antisymm _ _ (least_closed p initial) (full_grows p _)

theorem stationary_eq_least (p : Program State Key Env Row) (initial : State) (n : Nat)
    (stationary : fullStep p (naive p initial n) = naive p initial n) :
    naive p initial n = leastState p initial := by
  apply p.lattice.antisymm
  · exact history_below_closed p initial _ (seed_below_least p initial) (least_closed p initial) n
  · exact least_below_closed p initial _
      ⟨(stationary_least p initial n stationary).1,
       (stationary_least p initial n stationary).2.1⟩

-- Finite-height acceptance is optional and parameterized, never a runtime cutoff.
theorem ranked_termination (p : Program State Key Env Row) (initial : State)
    (rank : State → Nat) (height : Nat) (bounded : ∀ s, rank s ≤ height)
    (progress : ∀ s, fullStep p s ≠ s → rank s < rank (fullStep p s)) :
    ∃ n, n ≤ height ∧ fullStep p (naive p initial n) = naive p initial n :=
  Ascent.bounded_rank_stabilizes (fullStep p) initial rank height bounded progress

theorem ranked_converges (p : Program State Key Env Row) (initial : State)
    (rank : State → Nat) (height : Nat) (bounded : ∀ s, rank s ≤ height)
    (progress : ∀ s, fullStep p s ≠ s → rank s < rank (fullStep p s)) :
    ∃ n, n ≤ height ∧ naive p initial n = leastState p initial ∧
      (semiNaive p initial n).1 = leastState p initial := by
  obtain ⟨n,within,stationary⟩ := ranked_termination p initial rank height bounded progress
  have same := stationary_eq_least p initial n stationary
  refine ⟨n,within,same,?_⟩
  rw [iterations_equal]
  exact same

end Ascent.ProviderIteration
