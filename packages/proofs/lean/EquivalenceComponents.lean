-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import ProviderFrontier

/-! Equivalence Provider insertion with an explicit active-node domain. Unknown
nodes are not reflexive until admitted. Native component identities, hash
representation, budget arithmetic and row order remain separate bridges. -/
namespace Ascent.EquivalenceComponents
variable {N : Type}

structure State (N : Type) where
  active : N → Prop
  rel : N → N → Prop
  supported : ∀ x y, rel x y → active x ∧ active y
  refl : ∀ x, active x → rel x x
  symm : ∀ x y, rel x y → rel y x
  trans : ∀ x y z, rel x y → rel y z → rel x z

def base (state : State N) (a b x y : N) : Prop :=
  state.rel x y ∨ (x = a ∧ y = a) ∨ (x = b ∧ y = b)

theorem base_symm (state : State N) (a b x y : N) (xy : base state a b x y) :
    base state a b y x := by
  rcases xy with old | ⟨xa, ya⟩ | ⟨xb, yb⟩
  · exact Or.inl (state.symm x y old)
  · exact Or.inr (Or.inl ⟨ya, xa⟩)
  · exact Or.inr (Or.inr ⟨yb, xb⟩)

theorem base_trans (state : State N) (a b x y z : N)
    (xy : base state a b x y) (yz : base state a b y z) : base state a b x z := by
  rcases xy with old | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · rcases yz with tail | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact Or.inl (state.trans x y z old tail)
    · exact Or.inl old
    · exact Or.inl old
  · exact yz
  · exact yz

def cross (state : State N) (a b x y : N) : Prop :=
  (base state a b x a ∧ base state a b b y) ∨
  (base state a b x b ∧ base state a b a y)
def insert (state : State N) (a b x y : N) : Prop :=
  base state a b x y ∨ cross state a b x y

theorem insert_symm (state : State N) (a b x y : N) (xy : insert state a b x y) :
    insert state a b y x := by
  rcases xy with old | ⟨xa, by'⟩ | ⟨xb, ay⟩
  · exact Or.inl (base_symm state a b x y old)
  · exact Or.inr (Or.inr ⟨base_symm state a b b y by', base_symm state a b x a xa⟩)
  · exact Or.inr (Or.inl ⟨base_symm state a b a y ay, base_symm state a b x b xb⟩)

theorem insert_trans (state : State N) (a b x y z : N)
    (xy : insert state a b x y) (yz : insert state a b y z) : insert state a b x z := by
  rcases xy with old | ⟨xa, by'⟩ | ⟨xb, ay⟩
  · rcases yz with tail | ⟨ya, bz⟩ | ⟨yb, az⟩
    · exact Or.inl (base_trans state a b x y z old tail)
    · exact Or.inr (Or.inl ⟨base_trans state a b x y a old ya, bz⟩)
    · exact Or.inr (Or.inr ⟨base_trans state a b x y b old yb, az⟩)
  · rcases yz with tail | ⟨_, bz⟩ | ⟨_, az⟩
    · exact Or.inr (Or.inl ⟨xa, base_trans state a b b y z by' tail⟩)
    · exact Or.inr (Or.inl ⟨xa, bz⟩)
    · exact Or.inl (base_trans state a b x a z xa az)
  · rcases yz with tail | ⟨_, bz⟩ | ⟨_, az⟩
    · exact Or.inr (Or.inr ⟨xb, base_trans state a b a y z ay tail⟩)
    · exact Or.inl (base_trans state a b x b z xb bz)
    · exact Or.inr (Or.inr ⟨xb, az⟩)

theorem inserted_edge (state : State N) (a b : N) : insert state a b a b :=
  Or.inr (Or.inl ⟨Or.inr (Or.inl ⟨rfl, rfl⟩), Or.inr (Or.inr ⟨rfl, rfl⟩)⟩)

theorem insert_least (state : State N) (a b : N) (other : N → N → Prop)
    (contains : ∀ x y, state.rel x y → other x y) (edge : other a b)
    (symm : ∀ x y, other x y → other y x)
    (trans : ∀ x y z, other x y → other y z → other x z)
    (x y : N) (xy : insert state a b x y) : other x y := by
  have aa := trans a b a edge (symm a b edge)
  have bb := trans b a b (symm a b edge) edge
  have lift : ∀ x y, base state a b x y → other x y := by
    intro x y known
    rcases known with old | ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
    · exact contains x y old
    · exact aa
    · exact bb
  rcases xy with old | ⟨xa, by'⟩ | ⟨xb, ay⟩
  · exact lift x y old
  · exact trans x b y (trans x a b (lift x a xa) edge) (lift b y by')
  · exact trans x a y (trans x b a (lift x b xb) (symm a b edge)) (lift a y ay)

/-- Native emission: new-node diagonals, then both cross products only when
resolved components differ. The second diagonal excludes a repeated node. -/
def emitted (state : State N) (a b x y : N) : Prop :=
  (x = a ∧ y = a ∧ ¬ state.active a) ∨
  (x = b ∧ y = b ∧ ¬ state.active b ∧ b ≠ a) ∨
  (¬ base state a b a b ∧ cross state a b x y)

theorem base_fresh (state : State N) (a b x y : N)
    (known : base state a b x y) (fresh : ¬ state.rel x y) : emitted state a b x y := by
  classical
  rcases known with old | aa | bb
  · exact False.elim (fresh old)
  · rcases aa with ⟨hx, hy⟩
    subst x; subst y
    exact Or.inl ⟨rfl, rfl, fun present => fresh (state.refl _ present)⟩
  · rcases bb with ⟨hx, hy⟩
    subst x; subst y
    by_cases same : b = a
    · subst b
      exact Or.inl ⟨rfl, rfl, fun present => fresh (state.refl _ present)⟩
    · exact Or.inr (Or.inl ⟨rfl, rfl, fun present => fresh (state.refl _ present), same⟩)

theorem emitted_exact (state : State N) (a b x y : N) :
    emitted state a b x y ↔ insert state a b x y ∧ ¬ state.rel x y := by
  classical
  constructor
  · rintro (⟨rfl, rfl, unseen⟩ | ⟨rfl, rfl, unseen, _⟩ | ⟨different, crossed⟩)
    · exact ⟨Or.inl (Or.inr (Or.inl ⟨rfl, rfl⟩)), fun old => unseen (state.supported _ _ old).1⟩
    · exact ⟨Or.inl (Or.inr (Or.inr ⟨rfl, rfl⟩)), fun old => unseen (state.supported _ _ old).1⟩
    · refine ⟨Or.inr crossed, ?_⟩
      intro old
      rcases crossed with ⟨xa, by'⟩ | ⟨xb, ay⟩
      · exact different (base_trans state a b a y b
          (base_trans state a b a x y (base_symm state a b x a xa) (Or.inl old))
          (base_symm state a b b y by'))
      · exact different (base_symm state a b b a
          (base_trans state a b b y a
            (base_trans state a b b x y (base_symm state a b x b xb) (Or.inl old))
            (base_symm state a b a y ay)))
  · rintro ⟨known, fresh⟩
    rcases known with diagonal | crossed
    · exact base_fresh state a b x y diagonal fresh
    · by_cases same : base state a b a b
      · apply base_fresh state a b x y _ fresh
        rcases crossed with ⟨xa, by'⟩ | ⟨xb, ay⟩
        · exact base_trans state a b x b y (base_trans state a b x a b xa same) by'
        · exact base_trans state a b x a y
            (base_trans state a b x b a xb (base_symm state a b a b same)) ay
      · exact Or.inr (Or.inr ⟨same, crossed⟩)

theorem total_delta (state : State N) (a b x y : N) :
    insert state a b x y ↔ state.rel x y ∨ emitted state a b x y := by
  classical
  rw [emitted_exact]
  have grows : state.rel x y → insert state a b x y := fun old => Or.inl (Or.inl old)
  by_cases old : state.rel x y <;> simp_all

def activeAfter (state : State N) (a b x : N) : Prop :=
  state.active x ∨ x = a ∨ x = b

theorem base_supported (state : State N) (a b x y : N)
    (known : base state a b x y) : activeAfter state a b x ∧ activeAfter state a b y := by
  rcases known with old | ⟨hx, hy⟩ | ⟨hx, hy⟩
  · exact ⟨Or.inl (state.supported x y old).1, Or.inl (state.supported x y old).2⟩
  · exact ⟨Or.inr (Or.inl hx), Or.inr (Or.inl hy)⟩
  · exact ⟨Or.inr (Or.inr hx), Or.inr (Or.inr hy)⟩

theorem insert_supported (state : State N) (a b x y : N)
    (known : insert state a b x y) : activeAfter state a b x ∧ activeAfter state a b y := by
  rcases known with old | ⟨xa, by'⟩ | ⟨xb, ay⟩
  · exact base_supported state a b x y old
  · exact ⟨(base_supported state a b x a xa).1, (base_supported state a b b y by').2⟩
  · exact ⟨(base_supported state a b x b xb).1, (base_supported state a b a y ay).2⟩

theorem insert_refl (state : State N) (a b x : N)
    (present : activeAfter state a b x) : insert state a b x x := by
  rcases present with old | rfl | rfl
  · exact Or.inl (Or.inl (state.refl x old))
  · exact Or.inl (Or.inr (Or.inl ⟨rfl, rfl⟩))
  · exact Or.inl (Or.inr (Or.inr ⟨rfl, rfl⟩))

/-- Every insertion returns a valid state reusable by the next insertion. -/
def extendState (state : State N) (a b : N) : State N where
  active := activeAfter state a b
  rel := insert state a b
  supported := insert_supported state a b
  refl := insert_refl state a b
  symm := insert_symm state a b
  trans := insert_trans state a b

def extendGroup {G : Type} [DecidableEq G] (states : G → State N)
    (target : G) (a b : N) (group : G) : State N :=
  if group = target then extendState (states group) a b else states group

theorem other_group {G : Type} [DecidableEq G] (states : G → State N)
    (target group : G) (a b : N) (other : group ≠ target) :
    extendGroup states target a b group = states group := by
  simp [extendGroup, other]

def injectMany (state : State N) : List (N × N) → State N
  | [] => state
  | (a, b) :: tail => injectMany (extendState state a b) tail

theorem injectMany_least (edges : List (N × N)) (state : State N)
    (other : N → N → Prop)
    (contains : ∀ x y, state.rel x y → other x y)
    (inputs : ∀ edge ∈ edges, other edge.1 edge.2)
    (symm : ∀ x y, other x y → other y x)
    (trans : ∀ x y z, other x y → other y z → other x z) :
    ∀ x y, (injectMany state edges).rel x y → other x y := by
  induction edges generalizing state with
  | nil => exact contains
  | cons edge tail ih =>
    apply ih (extendState state edge.1 edge.2)
    · exact insert_least state edge.1 edge.2 other contains
        (inputs edge (by simp)) symm trans
    · intro member present
      exact inputs member (by simp [present])

theorem injectMany_monotone (edges : List (N × N)) (state : State N) :
    ∀ x y, state.rel x y → (injectMany state edges).rel x y := by
  induction edges generalizing state with
  | nil => exact fun _ _ known => known
  | cons edge tail ih =>
    intro x y known
    exact ih (extendState state edge.1 edge.2) x y (Or.inl (Or.inl known))

theorem injectMany_inputs (edges : List (N × N)) (state : State N) :
    ∀ edge ∈ edges, (injectMany state edges).rel edge.1 edge.2 := by
  induction edges generalizing state with
  | nil => simp
  | cons first tail ih =>
    intro edge present
    rcases List.mem_cons.mp present with equal | remaining
    · subst edge
      exact injectMany_monotone tail (extendState state first.1 first.2) _ _
        (inserted_edge state first.1 first.2)
    · exact ih (extendState state first.1 first.2) edge remaining

end Ascent.EquivalenceComponents
