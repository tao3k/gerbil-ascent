/- Relational laws, not a theorem about natural-language factor extraction or
   the implementation's fidelity to this reference semantics. -/
namespace Ascent.AnchoredEvidenceSlice

def anchor {Factor Chain : Type} (exposed : Factor → Prop)
    (association : Factor → Chain → Prop) (applicable : Chain → Prop) (c : Chain) :=
  applicable c ∧ ∃ f, exposed f ∧ association f c

def slice {Factor Chain Witness : Type} (exposed : Factor → Prop)
    (association : Factor → Chain → Prop) (applicable : Chain → Prop)
    (belongs : Chain → Witness → Prop) (w : Witness) :=
  ∃ c, anchor exposed association applicable c ∧ belongs c w

structure Validity where
  sourceCurrent : Prop
  receiptBound : Prop
  conditionsSatisfied : Prop
  declarationValid : Prop
  evaluationComplete : Prop
  presentationSufficient : Prop

def Validity.ready (v : Validity) := v.sourceCurrent ∧ v.receiptBound ∧
  v.conditionsSatisfied ∧ v.declarationValid ∧ v.evaluationComplete ∧ v.presentationSufficient

def presented {Factor Chain Witness : Type} (v : Validity) (exposed : Factor → Prop)
    (association : Factor → Chain → Prop) (applicable : Chain → Prop)
    (belongs : Chain → Witness → Prop) (w : Witness) :=
  v.ready ∧ slice exposed association applicable belongs w

theorem first_query_returns_associated_witness {Factor Chain Witness : Type}
    (v : Validity) (exposed : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop)
    (f : Factor) (c : Chain) (w : Witness)
    (hv : v.ready) (hf : exposed f) (ha : association f c)
    (hc : applicable c) (hw : belongs c w) :
    presented v exposed association applicable belongs w :=
  ⟨hv, c, ⟨hc, f, hf, ha⟩, hw⟩

theorem returned_witness_has_trace {Factor Chain Witness : Type}
    (v : Validity) (exposed : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop) (w : Witness)
    (h : presented v exposed association applicable belongs w) :
    ∃ c f, applicable c ∧ exposed f ∧ association f c ∧ belongs c w := by
  obtain ⟨_, c, ⟨hc, f, hf, ha⟩, hw⟩ := h
  exact ⟨c, f, hc, hf, ha, hw⟩

theorem invalid_binding_cannot_present {Factor Chain Witness : Type}
    (v : Validity) (exposed : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop) (w : Witness)
    (invalid : ¬ v.ready) :
    ¬ presented v exposed association applicable belongs w := by
  intro h
  exact invalid h.1

theorem no_association_cannot_present {Factor Chain Witness : Type}
    (v : Validity) (exposed : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop) (w : Witness)
    (missing : ∀ f c, exposed f → ¬ association f c) :
    ¬ presented v exposed association applicable belongs w := by
  intro h
  obtain ⟨c, f, _, hf, ha, _⟩ :=
    returned_witness_has_trace v exposed association applicable belongs w h
  exact missing f c hf ha

theorem malformed_declaration_cannot_present {Factor Chain Witness : Type}
    (v : Validity) (exposed : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop) (w : Witness)
    (invalid : ¬ v.declarationValid) :
    ¬ presented v exposed association applicable belongs w := by
  intro h
  obtain ⟨_, _, _, declared, _, _⟩ := h.1
  exact invalid declared

theorem family_closure_keeps_counterwitness {Factor Chain Witness : Type}
    (exposed : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop)
    (c : Chain) (counter : Witness) (hc : anchor exposed association applicable c)
    (hw : belongs c counter) : slice exposed association applicable belongs counter :=
  ⟨c, hc, hw⟩

theorem widening_preserves_evidence {Factor Chain Witness : Type}
    (small large : Factor → Prop) (association : Factor → Chain → Prop)
    (applicable : Chain → Prop) (belongs : Chain → Witness → Prop)
    (includes : ∀ f, small f → large f) (w : Witness)
    (h : slice small association applicable belongs w) :
    slice large association applicable belongs w := by
  obtain ⟨c, ⟨hc, f, hf, ha⟩, hw⟩ := h
  exact ⟨c, ⟨hc, f, includes f hf, ha⟩, hw⟩

def added {α : Type} (before now : α → Prop) (x : α) := now x ∧ ¬ before x
def removed {α : Type} (before now : α → Prop) (x : α) := before x ∧ ¬ now x
def retained {α : Type} (before now : α → Prop) (x : α) := now x ∧ before x

theorem same_count_does_not_hide_replacement {α : Type} (before now : α → Prop)
    (old fresh : α) (ho : before old) (hn : ¬ now old)
    (hf : now fresh) (hb : ¬ before fresh) :
    removed before now old ∧ added before now fresh := ⟨⟨ho, hn⟩, ⟨hf, hb⟩⟩

theorem hidden_is_not_absent {α : Type} (facts visible : α → Prop)
    (existsFact : ∃ x, facts x) (_hidden : ∀ x, ¬ visible x) : ¬ (∀ x, ¬ facts x) := by
  obtain ⟨x, hx⟩ := existsFact
  intro absent
  exact absent x hx

def displayed {α : Type} (evidence : α → Prop)
    (fullBody summaryReference : Prop) (w : α) :=
  evidence w ∧ (fullBody ∨ summaryReference)

theorem honest_summary_preserves_hit {α : Type} (evidence : α → Prop)
    (fullBody summaryReference : Prop) (w : α)
    (hw : evidence w) (hs : summaryReference) :
    displayed evidence fullBody summaryReference w := ⟨hw, Or.inr hs⟩

def acknowledged (fullPresentation completeEvaluation : Prop) :=
  fullPresentation ∧ completeEvaluation

theorem collapsed_page_cannot_be_acknowledged (fullPresentation completeEvaluation : Prop)
    (collapsed : ¬ fullPresentation) : ¬ acknowledged fullPresentation completeEvaluation := by
  intro h
  exact collapsed h.1

/- Read acknowledgement is family-local, not an all-or-nothing page receipt.
   Changing scope does not change source-bound knowledge of displayed families. -/
def readSeen {α : Type} (before shown : α → Prop) (x : α) := before x ∨ shown x
def readPending {α : Type} (scope seen : α → Prop) (x : α) := scope x ∧ ¬ seen x

theorem fully_shown_family_is_acknowledged {α : Type} (before shown : α → Prop)
    (x : α) (h : shown x) : readSeen before shown x := Or.inr h

theorem hidden_family_is_not_newly_acknowledged {α : Type} (before shown : α → Prop)
    (x : α) (hb : ¬ before x) (hs : ¬ shown x) : ¬ readSeen before shown x := by
  intro h
  exact h.elim hb hs

theorem rescoping_does_not_replay_seen_family {α : Type} (scope seen : α → Prop)
    (x : α) (h : seen x) : ¬ readPending scope seen x := by
  intro pending
  exact pending.2 h

theorem read_progress_preserves_previous_families {α : Type} (before shown : α → Prop)
    (x : α) (h : before x) : readSeen before shown x := Or.inl h

theorem folded_unseen_family_remains_pending {α : Type} (scope before shown : α → Prop)
    (x : α) (hc : scope x) (hb : ¬ before x) (hs : ¬ shown x) :
    readPending scope (readSeen before shown) x :=
  ⟨hc, hidden_family_is_not_newly_acknowledged before shown x hb hs⟩

theorem outside_scope_is_not_a_pending_removal {α : Type} (scope before now : α → Prop)
    (x : α) (h : ¬ scope x) : ¬ (scope x ∧ removed before now x) := by
  intro r
  exact h r.1

end Ascent.AnchoredEvidenceSlice
