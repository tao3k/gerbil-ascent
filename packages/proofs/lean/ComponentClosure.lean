-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import SemiNaive
import FiniteHeight

/-! Ground positive rules, component-local saturation and least closure.
This is semantic decomposition, not a scheduler state machine. Grounding,
native SCC projection and general non-ground termination are separate obligations. -/
namespace Ascent.ComponentClosure
variable {Fact Component : Type}
abbrev Database (Fact : Type) := Fact → Prop
structure Rule (Fact : Type) where
  body : List Fact
  head : Fact

def Holds (database : Database Fact) (body : List Fact) : Prop :=
  ∀ fact ∈ body, database fact

inductive Derivable (rules : List (Rule Fact)) (seed : Database Fact) : Fact → Prop where
  | seed {fact} : seed fact → Derivable rules seed fact
  | fire (rule : Rule Fact) : rule ∈ rules →
      (∀ fact ∈ rule.body, Derivable rules seed fact) → Derivable rules seed rule.head

def Depends (rules : List (Rule Fact)) (owner : Fact → Component) (source target : Component) : Prop :=
  ∃ rule ∈ rules, owner rule.head = target ∧ ∃ fact ∈ rule.body, owner fact = source

def ClosedAt (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) : Prop :=
  ∀ rule ∈ rules, owner rule.head = component → Holds database rule.body → database rule.head

def ClosedOn (rules : List (Rule Fact)) (owner : Fact → Component)
    (components : List Component) (database : Database Fact) : Prop :=
  ∀ component ∈ components, ClosedAt rules owner component database

def step (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) : Database Fact :=
  fun fact => database fact ∨ ∃ rule ∈ rules,
    owner rule.head = component ∧ Holds database rule.body ∧ rule.head = fact

def iterate (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) : Nat → Database Fact
  | 0 => database
  | n + 1 => step rules owner component (iterate rules owner component database n)

def solve (rules : List (Rule Fact)) (owner : Fact → Component) :
    List (Component × Nat) → Database Fact → Database Fact
  | [], database => database
  | entry :: rest, database => solve rules owner rest (iterate rules owner entry.1 database entry.2)

def Ordered (rules : List (Rule Fact)) (owner : Fact → Component) : List (Component × Nat) → Prop
  | [] => True
  | entry :: rest => (∀ later ∈ rest, ¬ Depends rules owner later.1 entry.1) ∧ Ordered rules owner rest

def StablePlan (rules : List (Rule Fact)) (owner : Fact → Component) :
    List (Component × Nat) → Database Fact → Prop
  | [], _ => True
  | entry :: rest, database =>
      iterate rules owner entry.1 database (entry.2 + 1) = iterate rules owner entry.1 database entry.2 ∧
      StablePlan rules owner rest (iterate rules owner entry.1 database entry.2)

theorem iterate_grows (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) (n : Nat) :
    ∀ fact, database fact → iterate rules owner component database n fact := by
  induction n with
  | zero => exact fun _ present => present
  | succ n ih => exact fun fact present => Or.inl (ih fact present)

/-- Local writes cannot change another component's facts. -/
theorem iterate_frame (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) (n : Nat) (fact : Fact)
    (foreign : owner fact ≠ component) :
    iterate rules owner component database n fact ↔ database fact := by
  induction n with
  | zero => rfl
  | succ n ih =>
      constructor
      · rintro (old | ⟨rule, _, owned, _, same⟩)
        · exact ih.mp old
        · subst fact; exact False.elim (foreign owned)
      · exact fun present => Or.inl (ih.mpr present)

/-- Observed no-new-fact stability entails local closure; closure is derived. -/
theorem stable_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) (n : Nat)
    (stable : iterate rules owner component database (n + 1) = iterate rules owner component database n) :
    ClosedAt rules owner component (iterate rules owner component database n) := by
  intro rule member owned body
  have generated : iterate rules owner component database (n + 1) rule.head :=
    Or.inr ⟨rule, member, owned, body, rfl⟩
  rw [stable] at generated
  exact generated

/-- No backward read edge lets a later local solve preserve earlier closure. -/
theorem preserve_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component earlier : Component) (database : Database Fact) (n : Nat)
    (closed : ClosedAt rules owner earlier database)
    (noBack : ¬ Depends rules owner component earlier) :
    ClosedAt rules owner earlier (iterate rules owner component database n) := by
  intro rule member owned body
  apply iterate_grows rules owner component database n rule.head
  apply closed rule member owned
  intro fact present
  have foreign : owner fact ≠ component := by
    intro same
    exact noBack ⟨rule, member, owned, fact, present, same⟩
  exact (iterate_frame rules owner component database n fact foreign).mp (body fact present)

theorem solve_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (plan : List (Component × Nat)) (database : Database Fact) (prior : List Component)
    (closed : ClosedOn rules owner prior database)
    (forward : ∀ entry ∈ plan, ∀ earlier ∈ prior, ¬ Depends rules owner entry.1 earlier)
    (ordered : Ordered rules owner plan) (stable : StablePlan rules owner plan database) :
    ClosedOn rules owner (prior ++ plan.map Prod.fst) (solve rules owner plan database) := by
  induction plan generalizing database prior with
  | nil => simpa [solve] using closed
  | cons entry rest ih =>
      have extended : ClosedOn rules owner (prior ++ [entry.1])
          (iterate rules owner entry.1 database entry.2) := by
        intro earlier member
        rcases List.mem_append.mp member with old | current
        · exact preserve_closed rules owner entry.1 earlier database entry.2
            (closed earlier old) (forward entry List.mem_cons_self earlier old)
        · have same : earlier = entry.1 := List.mem_singleton.mp current
          subst earlier
          exact stable_closed rules owner entry.1 database entry.2 stable.1
      have tailForward : ∀ later ∈ rest, ∀ earlier ∈ prior ++ [entry.1],
          ¬ Depends rules owner later.1 earlier := by
        intro later member earlier previous
        rcases List.mem_append.mp previous with old | current
        · exact forward later (List.mem_cons_of_mem entry member) earlier old
        · have same : earlier = entry.1 := List.mem_singleton.mp current
          subst earlier
          exact ordered.1 later member
      have result := ih _ _ extended tailForward ordered.2 stable.2
      simpa [solve, List.map_cons, List.append_assoc] using result

theorem iterate_sound (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database seed : Database Fact) (n : Nat)
    (sound : ∀ fact, database fact → Derivable rules seed fact) :
    ∀ fact, iterate rules owner component database n fact → Derivable rules seed fact := by
  induction n with
  | zero => exact sound
  | succ n ih =>
      rintro fact (old | ⟨rule, member, _, body, same⟩)
      · exact ih fact old
      · subst fact
        exact Derivable.fire rule member (fun fact present => ih fact (body fact present))

theorem solve_sound (rules : List (Rule Fact)) (owner : Fact → Component)
    (plan : List (Component × Nat)) (database seed : Database Fact)
    (sound : ∀ fact, database fact → Derivable rules seed fact) :
    ∀ fact, solve rules owner plan database fact → Derivable rules seed fact := by
  induction plan generalizing database with
  | nil => exact sound
  | cons entry rest ih => exact ih _ (iterate_sound rules owner entry.1 database seed entry.2 sound)

theorem solve_grows (rules : List (Rule Fact)) (owner : Fact → Component)
    (plan : List (Component × Nat)) (database : Database Fact) :
    ∀ fact, database fact → solve rules owner plan database fact := by
  induction plan generalizing database with
  | nil => exact fun _ present => present
  | cons entry rest ih =>
      intro fact present
      exact ih _ fact (iterate_grows rules owner entry.1 database entry.2 fact present)

/-- Every stable topological component decomposition computes the least positive
closure. Independent components may appear in either order. No Nat cutoff. -/
theorem least_closure (rules : List (Rule Fact)) (owner : Fact → Component)
    (plan : List (Component × Nat)) (seed : Database Fact)
    (heads : ∀ rule ∈ rules, owner rule.head ∈ plan.map Prod.fst)
    (ordered : Ordered rules owner plan) (stable : StablePlan rules owner plan seed) (fact : Fact) :
    solve rules owner plan seed fact ↔ Derivable rules seed fact := by
  have closed := solve_closed rules owner plan seed [] (by intro c h; cases h)
    (by intro entry member c h; cases h) ordered stable
  constructor
  · exact solve_sound rules owner plan seed seed (fun _ present => Derivable.seed present) fact
  · intro derived
    induction derived with
    | seed present => exact solve_grows rules owner plan seed _ present
    | fire rule member body ih =>
        exact closed (owner rule.head) (heads rule member) rule member rfl (fun f h => ih f h)

/-- The component result is contained in every closed model covering the seed,
so least_closure denotes leastness, not only agreement with a chosen runner. -/
theorem least_model (rules : List (Rule Fact)) (owner : Fact → Component)
    (plan : List (Component × Nat)) (seed model : Database Fact)
    (heads : ∀ rule ∈ rules, owner rule.head ∈ plan.map Prod.fst)
    (ordered : Ordered rules owner plan) (stable : StablePlan rules owner plan seed)
    (covers : ∀ fact, seed fact → model fact)
    (closed : ∀ rule ∈ rules, Holds model rule.body → model rule.head)
    (fact : Fact) (produced : solve rules owner plan seed fact) : model fact := by
  have derived := (least_closure rules owner plan seed heads ordered stable fact).mp produced
  clear produced
  induction derived with
  | seed present => exact covers _ present
  | fire rule member body ih => exact closed rule member (fun f h => ih f h)

/-- Count known rule-head occurrences. Duplicate heads may overestimate the
height but cannot invalidate strict progress; facts outside heads are framed. -/
noncomputable def headRank (rules : List (Rule Fact)) (database : Database Fact) : Nat := by
  classical
  exact Ascent.booleanRank (fun i : Fin rules.length => decide (database (rules.get i).head))

theorem local_stabilizes (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) :
    ∃ n, n ≤ rules.length ∧
      iterate rules owner component database (n + 1) = iterate rules owner component database n := by
  classical
  have progress : ∀ before, step rules owner component before ≠ before →
      headRank rules before < headRank rules (step rules owner component before) := by
    intro before different
    have fresh : ∃ fact, step rules owner component before fact ∧ ¬ before fact := by
      apply Classical.byContradiction
      intro absent
      apply different
      funext fact
      apply propext
      constructor
      · intro present
        apply Classical.byContradiction
        intro missing
        exact absent ⟨fact, present, missing⟩
      · exact Or.inl
    obtain ⟨fact, present, missing⟩ := fresh
    have next := present
    obtain old | ⟨rule, member, _, _, same⟩ := present
    · exact False.elim (missing old)
    obtain ⟨index, selected⟩ := List.mem_iff_get.mp member
    apply Ascent.boolean_rank_strict
    · intro i known
      simp only [decide_eq_true_eq] at known ⊢
      exact Or.inl known
    · refine ⟨index, ?_, ?_⟩
      · change decide (before (rules.get index).head) = false
        simp only [selected, same, decide_eq_false_iff_not]
        exact missing
      · simp only [selected, same, decide_eq_true_eq]
        exact next
  have bounded : ∀ before, headRank rules before ≤ rules.length :=
    fun before => Ascent.boolean_rank_bounded _
  obtain ⟨n, bound, stable⟩ := Ascent.bounded_rank_stabilizes
    (step rules owner component) database (headRank rules) rules.length bounded progress
  have same : ∀ k, Ascent.iterateStep (step rules owner component) database k =
      iterate rules owner component database k := by
    intro k
    induction k with
    | zero => rfl
    | succ k ih => simp only [Ascent.iterateStep, iterate, ih]
  exact ⟨n, bound, by simpa only [same, iterate] using stable⟩

noncomputable def rounds (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) : Nat :=
  Classical.choose (local_stabilizes rules owner component database)

theorem rounds_spec (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact) :
    rounds rules owner component database ≤ rules.length ∧
      iterate rules owner component database (rounds rules owner component database + 1) =
        iterate rules owner component database (rounds rules owner component database) :=
  Classical.choose_spec (local_stabilizes rules owner component database)

/-- Semantic plan selects proved stabilization witnesses; it is not a native
scheduler or a runtime iteration cutoff. -/
noncomputable def planned (rules : List (Rule Fact)) (owner : Fact → Component) :
    List Component → Database Fact → List (Component × Nat)
  | [], _ => []
  | component :: rest, database =>
      let n := rounds rules owner component database
      (component, n) :: planned rules owner rest (iterate rules owner component database n)

theorem planned_components (rules : List (Rule Fact)) (owner : Fact → Component)
    (order : List Component) (database : Database Fact) :
    (planned rules owner order database).map Prod.fst = order := by
  induction order generalizing database with
  | nil => rfl
  | cons component rest ih => simp only [planned, List.map_cons, ih]

theorem planned_stable (rules : List (Rule Fact)) (owner : Fact → Component)
    (order : List Component) (database : Database Fact) :
    StablePlan rules owner (planned rules owner order database) database := by
  induction order generalizing database with
  | nil => trivial
  | cons component rest ih => exact ⟨(rounds_spec rules owner component database).2, ih _⟩

def Topological (rules : List (Rule Fact)) (owner : Fact → Component) : List Component → Prop
  | [] => True
  | component :: rest => (∀ later ∈ rest, ¬ Depends rules owner later component) ∧
      Topological rules owner rest

theorem planned_ordered (rules : List (Rule Fact)) (owner : Fact → Component)
    (order : List Component) (database : Database Fact) (topology : Topological rules owner order) :
    Ordered rules owner (planned rules owner order database) := by
  induction order generalizing database with
  | nil => trivial
  | cons component rest ih =>
      refine ⟨?_, ih _ topology.2⟩
      intro entry member
      have present := List.mem_map_of_mem (f := Prod.fst) member
      rw [planned_components] at present
      exact topology.1 entry.1 present

/-- Complete topological decomposition has no supplied stability premise:
finite ground rule heads provide every required local termination witness. -/
theorem topological_least (rules : List (Rule Fact)) (owner : Fact → Component)
    (order : List Component) (seed : Database Fact)
    (heads : ∀ rule ∈ rules, owner rule.head ∈ order)
    (topology : Topological rules owner order) (fact : Fact) :
    solve rules owner (planned rules owner order seed) seed fact ↔ Derivable rules seed fact :=
  least_closure rules owner _ seed (by simpa only [planned_components] using heads)
    (planned_ordered rules owner order seed topology) (planned_stable rules owner order seed) fact

theorem orders_equal (rules : List (Rule Fact)) (owner : Fact → Component)
    (first second : List (Component × Nat)) (seed : Database Fact)
    (firstHeads : ∀ rule ∈ rules, owner rule.head ∈ first.map Prod.fst)
    (secondHeads : ∀ rule ∈ rules, owner rule.head ∈ second.map Prod.fst)
    (firstOrder : Ordered rules owner first) (secondOrder : Ordered rules owner second)
    (firstStable : StablePlan rules owner first seed) (secondStable : StablePlan rules owner second seed) :
    solve rules owner first seed = solve rules owner second seed := by
  funext fact
  apply propext
  exact (least_closure rules owner first seed firstHeads firstOrder firstStable fact).trans
    (least_closure rules owner second seed secondHeads secondOrder secondStable fact).symm
end Ascent.ComponentClosure
