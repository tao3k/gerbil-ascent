-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import TransitiveComponents

/-! Directed closure uses a latent reflexive preorder. Public UF rows restrict
it to active endpoints; strict trrel rows expose off-diagonal reach and only
explicitly supplied self edges. Native SCC/hash/index extraction is separate. -/
namespace Ascent.DirectedFrontier
variable {N : Type}

structure State (N : Type) where
  active : N → Prop
  reach : N → N → Prop
  refl : ∀ x, reach x x
  trans : ∀ x y z, reach x y → reach y z → reach x z
  supported : ∀ x y, reach x y → x = y ∨ (active x ∧ active y)

def activeAfter (state : State N) (a b x : N) : Prop :=
  state.active x ∨ x = a ∨ x = b

def cross (state : State N) (a b x y : N) : Prop :=
  state.reach x a ∧ state.reach b y

theorem cross_supported (state : State N) (a b x y : N)
    (known : cross state a b x y) : activeAfter state a b x ∧ activeAfter state a b y := by
  constructor
  · rcases state.supported x a known.1 with same | present
    · exact Or.inr (Or.inl same)
    · exact Or.inl present.1
  · rcases state.supported b y known.2 with same | present
    · exact Or.inr (Or.inr same.symm)
    · exact Or.inl present.2

def extendState (state : State N) (a b : N) : State N where
  active := activeAfter state a b
  reach := TransitiveComponents.insertEdge state.reach a b
  refl := fun x => Or.inl (state.refl x)
  trans := TransitiveComponents.insertion_transitive state.reach state.trans a b
  supported := by
    intro x y known
    rcases known with old | crossed
    · rcases state.supported x y old with same | present
      · exact Or.inl same
      · exact Or.inr ⟨Or.inl present.1, Or.inl present.2⟩
    · exact Or.inr (cross_supported state a b x y crossed)

def ufVisible (state : State N) (x y : N) : Prop :=
  state.reach x y ∧ state.active x ∧ state.active y

def ufCandidate (state : State N) (a b x y : N) : Prop :=
  cross state a b x y ∨ (x = a ∧ y = a) ∨ (x = b ∧ y = b)

theorem uf_partition (state : State N) (a b x y : N) :
    ufVisible (extendState state a b) x y ↔
      ufVisible state x y ∨ ufCandidate state a b x y := by
  constructor
  · rintro ⟨old | crossed, present, _⟩
    · rcases state.supported x y old with same | active
      · subst y
        rcases present with known | atA | atB
        · exact Or.inl ⟨old, known, known⟩
        · exact Or.inr (Or.inr (Or.inl ⟨atA, atA⟩))
        · exact Or.inr (Or.inr (Or.inr ⟨atB, atB⟩))
      · exact Or.inl ⟨old, active⟩
    · exact Or.inr (Or.inl crossed)
  · rintro (⟨known, ax, ay⟩ | crossed | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩)
    · exact ⟨Or.inl known, Or.inl ax, Or.inl ay⟩
    · exact ⟨Or.inr crossed, cross_supported state a b x y crossed⟩
    · exact ⟨Or.inl (state.refl _), Or.inr (Or.inl rfl), Or.inr (Or.inl rfl)⟩
    · exact ⟨Or.inl (state.refl _), Or.inr (Or.inr rfl), Or.inr (Or.inr rfl)⟩

def ufEmitted (state : State N) (a b x y : N) : Prop :=
  ufCandidate state a b x y ∧ ¬ ufVisible state x y

theorem uf_emitted_exact (state : State N) (a b x y : N) :
    ufEmitted state a b x y ↔
      ufVisible (extendState state a b) x y ∧ ¬ ufVisible state x y := by
  rw [uf_partition]
  simp only [ufEmitted]
  constructor
  · rintro ⟨candidate, fresh⟩
    exact ⟨Or.inr candidate, fresh⟩
  · rintro ⟨old | candidate, fresh⟩
    · exact False.elim (fresh old)
    · exact ⟨candidate, fresh⟩

/-- Native UF emits missing predecessor/successor rectangles plus newly
activated endpoint diagonals. Latent self reach is not a visible old row. -/
theorem uf_emitted_decomposition (state : State N) (a b x y : N) :
    ufEmitted state a b x y ↔
      (cross state a b x y ∧ ¬ state.reach x y) ∨
      (x = a ∧ y = a ∧ ¬ state.active a) ∨
      (x = b ∧ y = b ∧ ¬ state.active b) := by
  classical
  constructor
  · rintro ⟨candidate, fresh⟩
    rcases candidate with crossed | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · by_cases prior : state.reach x y
      · rcases state.supported x y prior with equal | active
        · subst y
          have inactive : ¬ state.active x := fun active => fresh ⟨prior, active, active⟩
          rcases state.supported x a crossed.1 with equal | active
          · subst x; exact Or.inr (Or.inl ⟨rfl, rfl, inactive⟩)
          · exact False.elim (inactive active.1)
        · exact False.elim (fresh ⟨prior, active⟩)
      · exact Or.inl ⟨crossed, prior⟩
    · exact Or.inr (Or.inl ⟨rfl, rfl, fun active => fresh ⟨state.refl _, active, active⟩⟩)
    · exact Or.inr (Or.inr ⟨rfl, rfl, fun active => fresh ⟨state.refl _, active, active⟩⟩)
  · rintro (⟨crossed, missing⟩ | ⟨rfl, rfl, inactive⟩ | ⟨rfl, rfl, inactive⟩)
    · exact ⟨Or.inl crossed, fun visible => missing visible.1⟩
    · exact ⟨Or.inr (Or.inl ⟨rfl, rfl⟩), fun visible => inactive visible.2.1⟩
    · exact ⟨Or.inr (Or.inr ⟨rfl, rfl⟩), fun visible => inactive visible.2.1⟩

def selfAfter (self : N → Prop) (a b x : N) : Prop :=
  self x ∨ (x = a ∧ a = b)

def strictVisible (state : State N) (self : N → Prop) (x y : N) : Prop :=
  state.reach x y ∧ (x ≠ y ∨ self x)

def strictCandidate (state : State N) (a b x y : N) : Prop :=
  cross state a b x y ∧ (x ≠ y ∨ (x = a ∧ a = b))

theorem strict_partition (state : State N) (self : N → Prop) (a b x y : N) :
    strictVisible (extendState state a b) (selfAfter self a b) x y ↔
      strictVisible state self x y ∨ strictCandidate state a b x y := by
  classical
  constructor
  · rintro ⟨known, visible⟩
    rcases visible with different | oldSelf | ⟨atA, same⟩
    · rcases known with old | crossed
      · exact Or.inl ⟨old, Or.inl different⟩
      · exact Or.inr ⟨crossed, Or.inl different⟩
    · by_cases same : x = y
      · subst y
        exact Or.inl ⟨state.refl x, Or.inr oldSelf⟩
      · rcases known with old | crossed
        · exact Or.inl ⟨old, Or.inr oldSelf⟩
        · exact Or.inr ⟨crossed, Or.inl same⟩
    · by_cases different : x ≠ y
      · rcases known with old | crossed
        · exact Or.inl ⟨old, Or.inl different⟩
        · exact Or.inr ⟨crossed, Or.inl different⟩
      · have sameXY : x = y := Classical.byContradiction different
        subst y
        subst x
        subst b
        exact Or.inr ⟨⟨state.refl a, state.refl a⟩, Or.inr ⟨rfl, rfl⟩⟩
  · rintro (⟨known, different | self⟩ | ⟨crossed, different | explicit⟩)
    · exact ⟨Or.inl known, Or.inl different⟩
    · exact ⟨Or.inl known, Or.inr (Or.inl self)⟩
    · exact ⟨Or.inr crossed, Or.inl different⟩
    · exact ⟨Or.inr crossed, Or.inr (Or.inr explicit)⟩

def strictEmitted (state : State N) (self : N → Prop) (a b x y : N) : Prop :=
  strictCandidate state a b x y ∧ ¬ strictVisible state self x y

theorem strict_emitted_exact (state : State N) (self : N → Prop) (a b x y : N) :
    strictEmitted state self a b x y ↔
      strictVisible (extendState state a b) (selfAfter self a b) x y ∧
      ¬ strictVisible state self x y := by
  rw [strict_partition]
  simp only [strictEmitted]
  constructor
  · rintro ⟨candidate, fresh⟩
    exact ⟨Or.inr candidate, fresh⟩
  · rintro ⟨old | candidate, fresh⟩
    · exact False.elim (fresh old)
    · exact ⟨candidate, fresh⟩

theorem uf_self_exact (state : State N) (x : N) :
    ufVisible state x x ↔ state.active x := by
  constructor
  · exact fun known => known.2.1
  · exact fun known => ⟨state.refl x, known, known⟩

theorem strict_self_exact (state : State N) (self : N → Prop) (x : N) :
    strictVisible state self x x ↔ self x := by
  simp [strictVisible, state.refl]

theorem uf_insert_least (state : State N) (a b : N) (other : N → N → Prop)
    (contains : ∀ x y, ufVisible state x y → other x y)
    (edge : other a b)
    (refl : ∀ x, activeAfter state a b x → other x x)
    (trans : ∀ x y z, other x y → other y z → other x z)
    (x y : N) (known : ufVisible (extendState state a b) x y) : other x y := by
  have lift : ∀ x y, state.reach x y → activeAfter state a b x → other x y := by
    intro origin target reached active
    rcases state.supported origin target reached with same | supported
    · subst target
      exact refl origin active
    · exact contains origin target ⟨reached, supported⟩
  rcases (uf_partition state a b x y).mp known with old | crossed | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · exact contains x y old
  · exact trans x b y
      (trans x a b (lift x a crossed.1 (cross_supported state a b x y crossed).1) edge)
      (lift b y crossed.2 (Or.inr (Or.inr rfl)))
  · exact refl _ (Or.inr (Or.inl rfl))
  · exact refl _ (Or.inr (Or.inr rfl))

structure Snapshot (N : Type) where
  state : State N
  self : N → Prop
  self_supported : ∀ x, self x → state.active x

theorem strict_supported (snapshot : Snapshot N) (x y : N)
    (known : strictVisible snapshot.state snapshot.self x y) :
    snapshot.state.active x ∧ snapshot.state.active y := by
  rcases snapshot.state.supported x y known.1 with same | supported
  · subst y
    have loop := (strict_self_exact snapshot.state snapshot.self x).mp known
    exact ⟨snapshot.self_supported x loop, snapshot.self_supported x loop⟩
  · exact supported

def extendSnapshot (snapshot : Snapshot N) (a b : N) : Snapshot N where
  state := extendState snapshot.state a b
  self := selfAfter snapshot.self a b
  self_supported := by
    intro x present
    rcases present with old | ⟨atA, _⟩
    · exact Or.inl (snapshot.self_supported x old)
    · exact Or.inr (Or.inl atA)

def injectMany (snapshot : Snapshot N) : List (N × N) → Snapshot N
  | [] => snapshot
  | (a, b) :: tail => injectMany (extendSnapshot snapshot a b) tail

theorem injectMany_least (edges : List (N × N)) (snapshot : Snapshot N)
    (other : N → N → Prop)
    (contains : ∀ x y, snapshot.state.reach x y → other x y)
    (inputs : ∀ edge ∈ edges, other edge.1 edge.2)
    (trans : ∀ x y z, other x y → other y z → other x z) :
    ∀ x y, (injectMany snapshot edges).state.reach x y → other x y := by
  induction edges generalizing snapshot with
  | nil => exact contains
  | cons edge tail ih =>
    apply ih (extendSnapshot snapshot edge.1 edge.2)
    · exact TransitiveComponents.insertion_least snapshot.state.reach other
        edge.1 edge.2 contains (inputs edge (by simp)) trans
    · intro member present
      exact inputs member (by simp [present])

theorem injectMany_monotone (edges : List (N × N)) (snapshot : Snapshot N) :
    ∀ x y, snapshot.state.reach x y → (injectMany snapshot edges).state.reach x y := by
  induction edges generalizing snapshot with
  | nil => exact fun _ _ known => known
  | cons edge tail ih =>
    intro x y known
    exact ih (extendSnapshot snapshot edge.1 edge.2) x y (Or.inl known)

theorem injectMany_inputs (edges : List (N × N)) (snapshot : Snapshot N) :
    ∀ edge ∈ edges, (injectMany snapshot edges).state.reach edge.1 edge.2 := by
  induction edges generalizing snapshot with
  | nil => simp
  | cons first tail ih =>
    intro edge present
    rcases List.mem_cons.mp present with equal | remaining
    · subst edge
      exact injectMany_monotone tail (extendSnapshot snapshot first.1 first.2) _ _
        (TransitiveComponents.inserted_edge snapshot.state.reach first.1 first.2 snapshot.state.refl)
    · exact ih (extendSnapshot snapshot first.1 first.2) edge remaining

theorem injectMany_self_exact (edges : List (N × N)) (snapshot : Snapshot N) (x : N) :
    (injectMany snapshot edges).self x ↔ snapshot.self x ∨ (x, x) ∈ edges := by
  induction edges generalizing snapshot with
  | nil => simp [injectMany]
  | cons edge tail ih =>
    change (injectMany (extendSnapshot snapshot edge.1 edge.2) tail).self x ↔ _
    rw [ih]
    constructor
    · rintro ((old | ⟨xa, ab⟩) | present)
      · exact Or.inl old
      · exact Or.inr (List.mem_cons.mpr (Or.inl (Prod.ext xa (xa.trans ab))))
      · exact Or.inr (List.mem_cons_of_mem edge present)
    · rintro (old | present)
      · exact Or.inl (Or.inl old)
      · rcases List.mem_cons.mp present with same | remaining
        · have xa : x = edge.1 := congrArg Prod.fst same
          have xb : x = edge.2 := congrArg Prod.snd same
          exact Or.inl (Or.inr ⟨xa, xa.symm.trans xb⟩)
        · exact Or.inr remaining

theorem injectMany_active_exact (edges : List (N × N)) (snapshot : Snapshot N) (x : N) :
    (injectMany snapshot edges).state.active x ↔
      snapshot.state.active x ∨ ∃ edge ∈ edges, x = edge.1 ∨ x = edge.2 := by
  induction edges generalizing snapshot with
  | nil => simp [injectMany]
  | cons first tail ih =>
    change (injectMany (extendSnapshot snapshot first.1 first.2) tail).state.active x ↔ _
    rw [ih]
    constructor
    · rintro ((old | left | right) | ⟨edge, present, endpoint⟩)
      · exact Or.inl old
      · exact Or.inr ⟨first, by simp, Or.inl left⟩
      · exact Or.inr ⟨first, by simp, Or.inr right⟩
      · exact Or.inr ⟨edge, List.mem_cons_of_mem first present, endpoint⟩
    · rintro (old | ⟨edge, present, endpoint⟩)
      · exact Or.inl (Or.inl old)
      · rcases List.mem_cons.mp present with same | remaining
        · subst edge
          exact Or.inl (Or.inr endpoint)
        · exact Or.inr ⟨edge, remaining, endpoint⟩

def extendGroup {G : Type} [DecidableEq G] (snapshots : G → Snapshot N)
    (target : G) (a b : N) (group : G) : Snapshot N :=
  if group = target then extendSnapshot (snapshots group) a b else snapshots group

theorem other_group {G : Type} [DecidableEq G] (snapshots : G → Snapshot N)
    (target group : G) (a b : N) (other : group ≠ target) :
    extendGroup snapshots target a b group = snapshots group := by
  simp [extendGroup, other]

end Ascent.DirectedFrontier
