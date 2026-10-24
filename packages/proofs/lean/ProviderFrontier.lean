-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! Exact frontier and arbitrary finite positive-body pivot decomposition.
This supplies the concrete relation step of B23 §3.2, not the abstract-provider
iteration theorem or a refinement of Scheme indexes, Providers or lattices. -/
namespace Ascent.ProviderFrontier

def delta (old next : Row → Prop) (row : Row) : Prop := next row ∧ ¬ old row

theorem concrete_partition (old next : Row → Prop)
    (grows : ∀ row, old row → next row) (row : Row) :
    next row ↔ old row ∨ delta old next row := by
  classical
  constructor
  · intro h
    by_cases prior : old row
    · exact Or.inl prior
    · exact Or.inr ⟨h, prior⟩
  · intro h
    rcases h with prior | fresh
    · exact grows row prior
    · exact fresh.1

theorem new_fact_must_be_emitted (old next emitted : Row → Prop)
    (complete : ∀ row, next row → old row ∨ emitted row)
    (row : Row) (fresh : delta old next row) : emitted row := by
  rcases complete row fresh.1 with prior | present
  · exact False.elim (fresh.2 prior)
  · exact present

def join (left : A → B → Prop) (right : B → C → Prop) (a : A) (c : C) : Prop :=
  ∃ b, left a b ∧ right b c

def changed (old next : A → B → Prop) (a : A) (b : B) : Prop :=
  next a b ∧ ¬ old a b

theorem binary_join_partition
    (oldL nextL : A → B → Prop) (oldR nextR : B → C → Prop)
    (growsL : ∀ a b, oldL a b → nextL a b)
    (growsR : ∀ b c, oldR b c → nextR b c) (a : A) (c : C) :
    join nextL nextR a c ↔ join oldL oldR a c ∨
      join (changed oldL nextL) nextR a c ∨
      join oldL (changed oldR nextR) a c := by
  classical
  constructor
  · rintro ⟨b, left, right⟩
    by_cases priorL : oldL a b
    · by_cases priorR : oldR b c
      · exact Or.inl ⟨b, priorL, priorR⟩
      · exact Or.inr (Or.inr ⟨b, priorL, right, priorR⟩)
    · exact Or.inr (Or.inl ⟨b, ⟨left, priorL⟩, right⟩)
  · intro h
    rcases h with ⟨b, left, right⟩ | ⟨b, left, right⟩ | ⟨b, left, right⟩
    · exact ⟨b, growsL a b left, growsR b c right⟩
    · exact ⟨b, left.1, right⟩
    · exact ⟨b, growsL a b left, right.1⟩

/-- Each occurrence is a row-matching environment transition. Repeated keys
and shared variables are allowed. Empty bodies preserve the seed. -/
def body (relations : Key → Env → Env → Prop) : List Key → Env → Env → Prop
  | [], input, output => output = input
  | key :: rest, input, output =>
      ∃ middle, relations key input middle ∧ body relations rest middle output

/-- All single-delta pivots; other occurrences read the frozen next snapshot.
Different pivots may emit the same output and require deduplication. -/
def pivots (old next : Key → Env → Env → Prop) : List Key → Env → Env → Prop
  | [], _, _ => False
  | key :: rest, input, output =>
      (∃ middle, changed (old key) (next key) input middle ∧
        body next rest middle output) ∨
      (∃ middle, next key input middle ∧ pivots old next rest middle output)

theorem body_partition (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (keys : List Key) (input output : Env) :
    body next keys input output ↔
      body old keys input output ∨ pivots old next keys input output := by
  classical
  induction keys generalizing input output with
  | nil => simp [body, pivots]
  | cons key rest ih =>
    constructor
    · rintro ⟨middle, first, tail⟩
      by_cases prior : old key input middle
      · rcases (ih middle output).mp tail with oldTail | freshTail
        · exact Or.inl ⟨middle, prior, oldTail⟩
        · exact Or.inr (Or.inr ⟨middle, first, freshTail⟩)
      · exact Or.inr (Or.inl ⟨middle, ⟨first, prior⟩, tail⟩)
    · intro admitted
      rcases admitted with oldBody | freshBody
      · rcases oldBody with ⟨middle, first, tail⟩
        exact ⟨middle, grows key input middle first,
          (ih middle output).mpr (Or.inl tail)⟩
      · rcases freshBody with ⟨middle, first, tail⟩ | ⟨middle, first, tail⟩
        · exact ⟨middle, first.1, tail⟩
        · exact ⟨middle, first, (ih middle output).mpr (Or.inr tail)⟩

/-- Projection may collapse distinct witnesses to the same head row. -/
def output (derivation : Env → Prop) (emit : Env → Row) (row : Row) : Prop :=
  ∃ env, derivation env ∧ emit env = row

theorem projected_partition (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (keys : List Key) (seed : Env) (emit : Env → Row) (row : Row) :
    output (body next keys seed) emit row ↔
      output (body old keys seed) emit row ∨
      output (pivots old next keys seed) emit row := by
  constructor
  · rintro ⟨env, derivation, head⟩
    rcases (body_partition old next grows keys seed env).mp derivation with prior | fresh
    · exact Or.inl ⟨env, prior, head⟩
    · exact Or.inr ⟨env, fresh, head⟩
  · intro admitted
    rcases admitted with ⟨env, derivation, head⟩ | ⟨env, derivation, head⟩
    · exact ⟨env, (body_partition old next grows keys seed env).mpr (Or.inl derivation), head⟩
    · exact ⟨env, (body_partition old next grows keys seed env).mpr (Or.inr derivation), head⟩

/-- Exact output delta subtracts old outputs: fresh witnesses can project to
already known rows. This is a one-step law, not whole-engine convergence. -/
theorem projected_frontier (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (keys : List Key) (seed : Env) (emit : Env → Row) (row : Row) :
    delta (output (body old keys seed) emit) (output (body next keys seed) emit) row ↔
      output (pivots old next keys seed) emit row ∧
        ¬ output (body old keys seed) emit row := by
  constructor
  · rintro ⟨full, absent⟩
    rcases (projected_partition old next grows keys seed emit row).mp full with prior | fresh
    · exact False.elim (absent prior)
    · exact ⟨fresh, absent⟩
  · rintro ⟨fresh, absent⟩
    exact ⟨(projected_partition old next grows keys seed emit row).mpr (Or.inr fresh), absent⟩

/-- Omitting the all-old body needs a history premise: its heads must already
be in the known database. Exact Provider frontiers alone cannot supply it. -/
theorem new_consequence_pivot (old next : Key → Env → Env → Prop)
    (grows : ∀ key input output, old key input output → next key input output)
    (keys : List Key) (seed : Env) (emit : Env → Row) (known : Row → Prop)
    (covered : ∀ row, output (body old keys seed) emit row → known row) (row : Row) :
    output (body next keys seed) emit row ∧ ¬ known row ↔
      output (pivots old next keys seed) emit row ∧ ¬ known row := by
  constructor
  · rintro ⟨full, absent⟩
    rcases (projected_partition old next grows keys seed emit row).mp full with prior | fresh
    · exact False.elim (absent (covered row prior))
    · exact ⟨fresh, absent⟩
  · rintro ⟨fresh, absent⟩
    exact ⟨(projected_partition old next grows keys seed emit row).mpr (Or.inr fresh), absent⟩

namespace SetBatch
variable {Row : Type} [DecidableEq Row]

/-- Consume oldest-first candidate occurrences, retaining the native newest-
first accepted order. Membership, rather than occurrence identity, owns Set
admission; callers retain separate source logs. -/
def admit : List Row → List Row → List Row
  | [], _ => []
  | row :: rest, known =>
      if row ∈ known then admit rest known
      else admit rest (row :: known) ++ [row]

theorem admitted_exact (pending known : List Row) (row : Row) :
    row ∈ admit pending known ↔ row ∈ pending ∧ row ∉ known := by
  induction pending generalizing known with
  | nil => simp [admit]
  | cons first rest ih =>
      by_cases present : first ∈ known
      · simp [admit, present, ih]; grind
      · simp [admit, present, ih]; grind

theorem admitted_unique (pending known : List Row) : (admit pending known).Nodup := by
  induction pending generalizing known with
  | nil => simp [admit]
  | cons first rest ih =>
      by_cases present : first ∈ known
      · simpa [admit, present] using ih known
      · rw [admit, if_neg present, List.nodup_append]
        refine ⟨ih _, by simp, ?_⟩
        intro a member b equal
        have fresh := (admitted_exact rest (first :: known) a).mp member
        simp only [List.mem_singleton] at equal
        subst b
        intro same
        exact fresh.2 (by simp [same])

/-- Injection followed by identity concretization adds exactly the frontier. -/
def publish (pending known : List Row) : List Row := admit pending known ++ known

theorem published_exact (pending known : List Row) (row : Row) :
    row ∈ publish pending known ↔ row ∈ known ∨ row ∈ pending := by
  simp only [publish, List.mem_append, admitted_exact]
  by_cases prior : row ∈ known <;> simp [prior]

theorem published_unique (pending known : List Row) (unique : known.Nodup) :
    (publish pending known).Nodup := by
  rw [publish, List.nodup_append]
  refine ⟨admitted_unique pending known, unique, ?_⟩
  intro a member b prior equal
  subst b
  exact ((admitted_exact pending known a).mp member).2 prior

theorem frontier_exact (pending known : List Row) (row : Row) :
    row ∈ admit pending known ↔ delta (fun r => r ∈ known)
      (fun r => r ∈ publish pending known) row := by
  simp only [admitted_exact, delta, published_exact]
  grind

theorem repeated_batch_empty (pending known : List Row) :
    admit pending (publish pending known) = [] := by
  apply List.eq_nil_iff_forall_not_mem.mpr
  intro row member
  have fresh := (admitted_exact pending (publish pending known) row).mp member
  exact fresh.2 ((published_exact pending known row).mpr (Or.inr fresh.1))

/-- Staged logs are newest-first; only the admitted prefix is consumed. Native
descriptor admission owns the count <= log length precondition. -/
def sourceAdmit (sourceLog : List Row) (count : Nat) (known : List Row) : List Row :=
  admit (sourceLog.take count).reverse known

theorem source_admitted_exact (sourceLog : List Row) (count : Nat) (known : List Row) (row : Row) :
    row ∈ sourceAdmit sourceLog count known ↔ row ∈ sourceLog.take count ∧ row ∉ known := by
  simp [sourceAdmit, admitted_exact]

theorem admit_disjoint (pending known : List Row) (unique : pending.Nodup)
    (disjoint : ∀ row ∈ pending, row ∉ known) : admit pending known = pending.reverse := by
  induction pending generalizing known with
  | nil => rfl
  | cons first rest ih =>
      have fresh := disjoint first List.mem_cons_self
      have tailUnique := (List.nodup_cons.mp unique).2
      have tailDisjoint : ∀ row ∈ rest, row ∉ first :: known := by
        intro row member present
        rcases List.mem_cons.mp present with equal | prior
        · exact (List.nodup_cons.mp unique).1 (equal ▸ member)
        · exact disjoint row (List.mem_cons_of_mem first member) prior
      simp only [admit, if_neg fresh, List.reverse_cons]
      rw [ih _ tailUnique tailDisjoint]

theorem unique_whole_log (sourceLog : List Row) (unique : sourceLog.Nodup) :
    sourceAdmit sourceLog sourceLog.length [] = sourceLog := by
  unfold sourceAdmit
  simp only [List.take_length]
  have reversed : sourceLog.reverse.Nodup := by
    simpa only [List.Nodup, List.pairwise_reverse, ne_comm] using unique
  rw [admit_disjoint _ [] reversed (by simp)]
  simp

end SetBatch
end Ascent.ProviderFrontier
