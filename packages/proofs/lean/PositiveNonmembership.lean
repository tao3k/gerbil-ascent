/-!
Finite positive-rule nonmembership at the abstract relation-set level.
This file proves the certificate theorem, not that Gerbil implements its
premises. The executable verifier and its tests remain separate evidence.
-/

namespace Ascent

universe u

abbrev Relation (α : Type u) := α → Prop

def Included {α : Type u} (left right : Relation α) : Prop :=
  ∀ row, left row → right row

def Monotone {α : Type u}
    (step : Relation α → Relation α) : Prop :=
  ∀ {left right}, Included left right →
    Included (step left) (step right)

def Inputs {α : Type u}
    (source candidate : Relation α) : Relation α :=
  fun row => source row ∨ candidate row

def Closed {α : Type u}
    (input : Relation α) (step : Relation α → Relation α)
    (candidate : Relation α) : Prop :=
  Included input candidate ∧ Included (step candidate) candidate

/-- The least relation containing inputs and closed under rule instances. -/
def LeastClosure {α : Type u}
    (input : Relation α) (step : Relation α → Relation α) :
    Relation α :=
  fun row => ∀ candidate, Closed input step candidate → candidate row

theorem least_included_in_closed {α : Type u}
    {input : Relation α} {step : Relation α → Relation α}
    {candidate : Relation α}
    (hc : Closed input step candidate) :
    Included (LeastClosure input step) candidate := by
  intro row hrow
  exact hrow candidate hc

theorem input_in_least {α : Type u}
    {input : Relation α} {step : Relation α → Relation α} :
    Included input (LeastClosure input step) := by
  intro row hrow candidate hc
  exact hc.1 row hrow

theorem least_closed_under_rules {α : Type u}
    {input : Relation α} {step : Relation α → Relation α}
    (mono : Monotone step) :
    Included (step (LeastClosure input step))
      (LeastClosure input step) := by
  intro row hrow candidate hc
  have sub : Included (LeastClosure input step) candidate :=
    least_included_in_closed hc
  exact hc.2 row (mono sub row hrow)

theorem least_is_fixed {α : Type u}
    {input : Relation α} {step : Relation α → Relation α}
    (mono : Monotone step) (row : α) :
    LeastClosure input step row ↔
      input row ∨ step (LeastClosure input step) row := by
  let least := LeastClosure input step
  let next : Relation α := fun x => input x ∨ step least x
  have next_le_least : Included next least := by
    intro x hx
    rcases hx with hinput | hstep
    · exact input_in_least x hinput
    · exact least_closed_under_rules mono x hstep
  have next_closed : Closed input step next := by
    constructor
    · intro x hx
      exact Or.inl hx
    · intro x hx
      exact Or.inr (mono next_le_least x hx)
  constructor
  · intro h
    exact h next next_closed
  · intro h
    exact next_le_least row h

/--
A valid finite checker result supplies a relation-tagged candidate C
containing source and hypothetical facts and closed under every rule.
If a ground target is absent from C, it is absent from the least closure.
Finiteness is needed for the executable checker, not this implication.
-/
theorem ground_why_not_sound {α : Type u}
    {source hypothesis candidate : Relation α}
    {step : Relation α → Relation α} {target : α}
    (inputCovered : Included (Inputs source hypothesis) candidate)
    (ruleClosed : Included (step candidate) candidate)
    (targetAbsent : ¬ candidate target) :
    ¬ LeastClosure (Inputs source hypothesis) step target := by
  intro derived
  exact targetAbsent
    (least_included_in_closed ⟨inputCovered, ruleClosed⟩ target derived)

/-- After deleting inputs, restricting rule outputs to an old closed model
    preserves the new least closure. Grounded support maintenance relies on
    complete rule instances and founded iteration, not circular support counts. -/
theorem deletion_restricted_model {α : Type u}
    (input old : Relation α) (step : Relation α → Relation α)
    (mono : Monotone step) (covered : Included input old)
    (oldClosed : Included (step old) old) (row : α) :
    LeastClosure input step row ↔
      LeastClosure input (fun r x => old x ∧ step r x) row := by
  let restricted : Relation α → Relation α := fun r x => old x ∧ step r x
  have restrictedMono : Monotone restricted := by
    intro a b hab x hx
    exact ⟨hx.1, mono hab x hx.2⟩
  have fullOld : Included (LeastClosure input step) old :=
    least_included_in_closed ⟨covered, oldClosed⟩
  have restrictedFull : Included (LeastClosure input restricted)
      (LeastClosure input step) := by
    apply least_included_in_closed
    constructor
    · exact input_in_least
    · intro x hx
      exact least_closed_under_rules mono x hx.2
  have restrictedClosed : Closed input step (LeastClosure input restricted) := by
    constructor
    · exact input_in_least
    · intro x hx
      have inOld : old x := oldClosed x (mono
        (fun y hy => fullOld y (restrictedFull y hy)) x hx)
      exact least_closed_under_rules restrictedMono x ⟨inOld, hx⟩
  constructor
  · intro hx
    exact least_included_in_closed restrictedClosed row hx
  · intro hx
    exact restrictedFull row hx

end Ascent
