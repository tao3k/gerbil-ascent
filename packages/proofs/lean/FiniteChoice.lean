-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import FiniteHeight
import IndexedIteration

/-! Ground fact-set semantics from Finite-Choice Logic Programming, §2.1.
Attributes and ground values use natural-number identities. The database is a
partial function, so each attribute has at most one value by construction. -/
namespace Ascent.FiniteChoice

abbrev Database := Nat → Option Nat
abbrev Fact := Nat × Nat

inductive Head where
  | closed (keyId : Nat) (values : List Nat)
  | openOffer (keyId value : Nat)

structure Rule where
  body : List Fact
  head : Head

def enabled (database : Database) (rule : Rule) : Prop :=
  ∀ fact ∈ rule.body, database fact.1 = some fact.2

def assign (database : Database) (keyId value : Nat) : Database :=
  fun key => if key = keyId then some value else database key

def choose (database : Database) (keyId value : Nat) : List Database :=
  match database keyId with
  | none => [assign database keyId value]
  | some prior => if prior = value then [database] else []

def evolve (database : Database) (head : Head) : List Database :=
  match head with
  | .closed keyId values => values.flatMap (choose database keyId)
  | .openOffer keyId value => database :: choose database keyId value

/-- Rule successors are interpreted as a set. Duplicate offers may repeat a
successor in the representation without changing saturation. -/
def saturatesHead (database : Database) (head : Head) : Prop :=
  database ∈ evolve database head ∧
    ∀ successor ∈ evolve database head, successor = database

def saturated (rules : List Rule) (database : Database) : Prop :=
  ∀ rule ∈ rules, enabled database rule → saturatesHead database rule.head

inductive Reachable (rules : List Rule) : Database → Prop where
  | empty : Reachable rules (fun _ => none)
  | step {database successor : Database} {rule : Rule} :
      Reachable rules database → rule ∈ rules → enabled database rule →
      successor ∈ evolve database rule.head → Reachable rules successor

def solution (rules : List Rule) (database : Database) : Prop :=
  Reachable rules database ∧ saturated rules database

theorem assigned_distinct (database : Database) (keyId value : Nat)
    (unset : database keyId = none) :
    assign database keyId value ≠ database := by
  intro h
  have atKey := congrFun h keyId
  simp [assign, unset] at atKey

theorem open_saturated_iff (database : Database) (keyId value : Nat) :
    saturatesHead database (.openOffer keyId value) ↔
      database keyId ≠ none := by
  cases h : database keyId with
  | none =>
    have differs := assigned_distinct database keyId value h
    simp [saturatesHead, evolve, choose, h, differs]
  | some prior =>
    by_cases same : prior = value <;> simp [saturatesHead, evolve, choose, h, same]

theorem closed_saturated_iff (database : Database) (keyId : Nat) (values : List Nat) :
    saturatesHead database (.closed keyId values) ↔
      ∃ prior ∈ values, database keyId = some prior := by
  cases h : database keyId with
  | none =>
    have differs (value : Nat) := assigned_distinct database keyId value h
    have absent : database ∉ values.flatMap (choose database keyId) := by
      simp only [List.mem_flatMap, choose, h, List.mem_singleton, not_exists, not_and]
      intro value _ equal
      exact differs value equal.symm
    simp [saturatesHead, evolve, absent]
  | some prior =>
    have member (candidate : Database) :
        candidate ∈ values.flatMap (choose database keyId) ↔
          prior ∈ values ∧ candidate = database := by
      simp only [List.mem_flatMap, choose, h]
      constructor
      · rintro ⟨value, inValues, inside⟩
        split at inside
        · rename_i same
          subst value
          exact ⟨inValues, List.mem_singleton.mp inside⟩
        · simp at inside
      · rintro ⟨inValues, rfl⟩
        exact ⟨prior, inValues, by simp⟩
    simp [saturatesHead, evolve, member]

/-- A fact-set step preserves every assigned value. In particular, siblings
cannot overwrite a value already present in their common parent. -/
theorem step_preserves_assignment (database successor : Database)
    (head : Head) (key value : Nat) (present : database key = some value)
    (step : successor ∈ evolve database head) : successor key = some value := by
  have preserves (keyId offer : Nat) (inside : successor ∈ choose database keyId offer) :
      successor key = some value := by
    cases h : database keyId with
    | none =>
      have distinct : key ≠ keyId := by
        intro same
        subst key
        simp [h] at present
      have equal : successor = assign database keyId offer := by
        simpa [choose, h] using inside
      simpa [equal, assign, distinct] using present
    | some prior =>
      by_cases same : prior = offer
      · have equal : successor = database := by simpa [choose, h, same] using inside
        simpa [equal] using present
      · simp [choose, h, same] at inside
  cases head with
  | closed keyId values =>
    obtain ⟨offer, _, inside⟩ := List.mem_flatMap.mp step
    exact preserves keyId offer inside
  | openOffer keyId offer =>
    rcases List.mem_cons.mp step with equal | inside
    · simpa [equal] using present
    · exact preserves keyId offer inside

/-- This is the branch decision in Scheme's offer scan, expressed in
terms of the assigned value and the grounded alternatives. -/
def acceptsHead (database : Database) : Head → Prop
  | .openOffer keyId _ => database keyId ≠ none
  | .closed keyId values => ∃ prior ∈ values, database keyId = some prior

theorem accepts_head_exact (database : Database) (head : Head) :
    acceptsHead database head ↔ saturatesHead database head := by
  cases head with
  | closed keyId values => exact (closed_saturated_iff database keyId values).symm
  | openOffer keyId value => exact (open_saturated_iff database keyId value).symm

/-- The Scheme scan can only introduce values for an unset key. Accepted
self steps are already represented by the current state. -/
def offersExtension (database successor : Database) : Head → Prop
  | .openOffer keyId value =>
      database keyId = none ∧ successor = assign database keyId value
  | .closed keyId values =>
      database keyId = none ∧ ∃ offer ∈ values, successor = assign database keyId offer

theorem offers_extension_exact (database successor : Database) (head : Head) :
    offersExtension database successor head ↔
      successor ≠ database ∧ successor ∈ evolve database head := by
  cases head with
  | openOffer keyId value =>
    cases h : database keyId with
    | none =>
      have differs := assigned_distinct database keyId value h
      simp [offersExtension, evolve, choose, h, and_or_left, and_comm]
      exact fun same => same ▸ differs
    | some prior =>
      by_cases own : prior = value <;> simp [offersExtension, evolve, choose, h, own]
  | closed keyId values =>
    cases h : database keyId with
    | none =>
      simp only [offersExtension, evolve, List.mem_flatMap, choose, h, List.mem_singleton,
        true_and]
      constructor
      · rintro ⟨offer, allowed, rfl⟩
        exact ⟨assigned_distinct database keyId offer h, offer, allowed, rfl⟩
      · exact And.right
    | some prior =>
      simp only [offersExtension, evolve, h, reduceCtorEq, false_and, List.mem_flatMap,
        choose]
      refine ⟨False.elim, ?_⟩
      rintro ⟨different, offer, _, chosen⟩
      split at chosen
      · exact different (List.mem_singleton.mp chosen)
      · simp at chosen

/-- Strict successors omit self steps before scheduling. -/
def StrictStep (rules : List Rule) (before after : Database) : Prop :=
  before ≠ after ∧ ∃ rule ∈ rules, enabled before rule ∧ after ∈ evolve before rule.head

/-- Closing the worklist establishes completeness. The initial empty database
was scheduled, each discovered database was processed, and each processed
database registered every strict successor. -/
theorem exhausted_worklist_complete (rules : List Rule) (processed : Database → Prop)
    (initial : processed (fun _ => none))
    (closed : ∀ before after, processed before → StrictStep rules before after → processed after)
    {database : Database} (reached : Reachable rules database) : processed database := by
  induction reached with
  | empty => exact initial
  | @step before successor rule _ hRule hEnabled hNext ih =>
    by_cases same : before = successor
    · simpa [← same] using ih
    · exact closed before successor ih ⟨same, rule, hRule, hEnabled, hNext⟩

theorem exhausted_answers_exact (rules : List Rule)
    (processed accepted : Database → Prop)
    (initial : processed (fun _ => none))
    (closed : ∀ before after, processed before → StrictStep rules before after → processed after)
    (sound : ∀ database, processed database → Reachable rules database)
    (publish : ∀ database, accepted database ↔ processed database ∧ saturated rules database)
    (database : Database) : accepted database ↔ solution rules database := by
  rw [publish]
  exact ⟨fun h => ⟨sound database h.1, h.2⟩,
         fun h => ⟨exhausted_worklist_complete rules processed initial closed h.1, h.2⟩⟩

/-- The Scheme state budget charges a distinct discovery, including the
empty database. The processed and pending keys together form seen. An
unseen successor cannot exhaust a budget that covers the finite universe. -/
theorem fresh_discovery_fits_budget {State : Type} [DecidableEq State]
    (states seen : List State) (budget : Nat) (next : State)
    (covered : states.length ≤ budget) (distinct : seen.Nodup)
    (inside : seen ⊆ states) (legal : next ∈ states) (fresh : next ∉ seen) :
    seen.length < budget := by
  have sub : next :: seen ⊆ states := by
    intro value member
    rcases List.mem_cons.mp member with rfl | previous
    · exact legal
    · exact inside previous
  have length := List.Nodup.length_le_of_subset (List.nodup_cons.mpr ⟨fresh, distinct⟩) sub
  exact Nat.lt_of_succ_le (Nat.le_trans length covered)

/-- The Scheme worklist marks a state as seen before putting it on the
pending list. After popping the active state, every outgoing strict edge
is covered either by an earlier discovery or by an entry added now. -/
theorem register_successors_closes_cut {State : Type}
    (seen discoveries : State → Prop) (edge : State → State → Prop) (active : State)
    (recorded : ∀ next, edge active next → ¬ seen next → discoveries next) :
    ∀ next, edge active next → seen next ∨ discoveries next := by
  intro next reachable
  by_cases known : seen next
  · exact Or.inl known
  · exact Or.inr (recorded next reachable known)

theorem worklist_drain_covers_discovery {State : Type}
    (seen queued processed : State → Prop)
    (partition : ∀ state, seen state ↔ queued state ∨ processed state)
    (done : ∀ state, ¬ queued state) :
    ∀ state, seen state ↔ processed state := by
  intro state
  rw [partition]
  exact ⟨fun h => h.resolve_left (done state), Or.inr⟩

/-- Each coordinate is unset or one of the admitted values. -/
def finiteDatabases (attributes values : Nat) :
    List (Fin attributes → Fin (values + 1)) :=
  Ascent.enumerateTables (List.finRange (values + 1)) attributes

theorem finite_databases_count (attributes values : Nat) :
    (finiteDatabases attributes values).length = (values + 1) ^ attributes := by
  simp [finiteDatabases, Ascent.enumerate_tables_length]

theorem finite_databases_complete (attributes values : Nat)
    (database : Fin attributes → Fin (values + 1)) :
    database ∈ finiteDatabases attributes values :=
  Ascent.enumerate_tables_complete _ List.mem_finRange _ database

/-- Abstract a single Scheme search iteration as removing the active
entry and appending previously unseen strict successors. Seen includes
both processed and pending entries. -/
structure Worklist where
  seen : Nat
  pending : Nat
  processed : Nat

def Worklist.counts (state : Worklist) : Prop :=
  state.seen = state.pending + state.processed

def Worklist.advance (state : Worklist) (discoveries : Nat) : Worklist :=
  ⟨state.seen + discoveries, state.pending - 1 + discoveries, state.processed + 1⟩

theorem worklist_counts_preserved (state : Worklist) (discoveries : Nat)
    (counts : state.counts) (pending : 0 < state.pending) :
    (state.advance discoveries).counts := by
  simp only [Worklist.counts, Worklist.advance] at *
  omega

/-- Processing increases the count exactly once even if it adds many
successors. Together with the finite discovery bound this excludes an
infinite loop of successful iterations. -/
theorem worklist_budget_decreases (state : Worklist) (discoveries budget : Nat)
    (counts : state.counts) (pending : 0 < state.pending)
    (covered : state.seen ≤ budget) :
    budget - (state.advance discoveries).processed < budget - state.processed := by
  simp only [Worklist.counts, Worklist.advance] at *
  omega

/-- A private relation identifies the rule, and its leading columns carry
every named binding (including occurrence-local wildcard bindings). -/
def groundingRow {Value : Type} (bindings keys offers : List Value) : List Value :=
  bindings ++ keys ++ offers

theorem grounding_bindings_preserved {Value : Type} (bindings keys offers : List Value) :
    (groundingRow bindings keys offers).take bindings.length = bindings := by
  simp [groundingRow]

theorem grounding_distinguishes_instances {Value : Type}
    (left right leftKeys rightKeys leftOffers rightOffers : List Value)
    (width : left.length = right.length)
    (same : groundingRow left leftKeys leftOffers = groundingRow right rightKeys rightOffers) :
    left = right := by
  calc
    left = (groundingRow left leftKeys leftOffers).take left.length :=
      (grounding_bindings_preserved _ _ _).symm
    _ = (groundingRow right rightKeys rightOffers).take left.length :=
      congrArg (List.take left.length) same
    _ = right := by rw [width, grounding_bindings_preserved]

/-- Specialize the compiled indexed and pivot paths to relational grounding
rows. Membership combines the previously published cut with the delta run. -/
theorem grounding_delta_exact {Key Value : Type} [DecidableEq Value]
    (rule : IndexedIteration.Rule Key Value (List Value))
    (rows : IndexedIteration.Rows Key Value (List Value))
    (domain : Key → List Value → Prop)
    (valid : IndexedIteration.Valid domain rule)
    (covered : IndexedIteration.RowsAdmitted domain rows)
    (old next : SemiNaive.Database (List Value))
    (grows : ∀ item, old item → next item)
    (monotone : IndexedIteration.RowsMonotone rows)
    (priorSound : ∀ item, IndexedIteration.consequence rule rows old item →
      IndexedIteration.consequence rule rows next item)
    (item : List Value) :
    (item ∈ IndexedIteration.fullRun rule rows old ∨
      item ∈ IndexedIteration.pivotRun rule rows old next) ↔
      IndexedIteration.consequence rule rows next item := by
  constructor
  · rintro (prior | fresh)
    · exact priorSound item ((IndexedIteration.full_run_exact rule rows domain valid covered old item).mp prior)
    · exact IndexedIteration.pivot_run_sound rule rows domain valid covered old next grows monotone item fresh
  · intro consequence
    by_cases prior : IndexedIteration.consequence rule rows old item
    · exact Or.inl ((IndexedIteration.full_run_exact rule rows domain valid covered old item).mpr prior)
    · exact Or.inr (IndexedIteration.pivot_run_complete rule rows domain valid covered old next grows monotone item consequence prior)

def constrainedValues (seed : List Nat) (restrictions : List (List Nat)) : List Nat :=
  seed.filter fun value => restrictions.all fun allowed => allowed.contains value

theorem constrained_values_exact (seed : List Nat) (restrictions : List (List Nat)) (value : Nat) :
    value ∈ constrainedValues seed restrictions ↔
      value ∈ seed ∧ ∀ allowed ∈ restrictions, value ∈ allowed := by
  simp [constrainedValues, List.all_eq_true]

/-- A compatible model extending the current database must satisfy each
currently enabled closed head. Positive bodies persist under extension. -/
theorem closed_intersection_forced (database model : Database) (key value : Nat)
    (seed : List Nat) (restrictions : List (List Nat))
    (rules : List Rule)
    (seedRule : ∃ r ∈ rules, enabled database r ∧ r.head = .closed key seed)
    (otherRules : ∀ allowed ∈ restrictions,
      ∃ r ∈ rules, enabled database r ∧ r.head = .closed key allowed)
    (preserves : ∀ atKey atValue, database atKey = some atValue → model atKey = some atValue)
    (complete : saturated rules model)
    (singleton : constrainedValues seed restrictions = [value]) :
    model key = some value := by
  have satisfies (allowed : List Nat)
      (rule : ∃ r ∈ rules, enabled database r ∧ r.head = .closed key allowed) :
      ∃ prior ∈ allowed, model key = some prior := by
    obtain ⟨r, inRules, body, head⟩ := rule
    have saturatedHead := complete r inRules (fun fact inBody => preserves fact.1 fact.2 (body fact inBody))
    rw [head] at saturatedHead
    exact (closed_saturated_iff model key allowed).mp saturatedHead
  obtain ⟨prior, inSeed, assigned⟩ := satisfies seed seedRule
  have inOthers : ∀ allowed ∈ restrictions, prior ∈ allowed := by
    intro allowed member
    obtain ⟨other, inside, also⟩ := satisfies allowed (otherRules allowed member)
    have same : prior = other := Option.some.inj (assigned.symm.trans also)
    simpa [same] using inside
  have inAll := (constrained_values_exact seed restrictions prior).mpr ⟨inSeed, inOthers⟩
  rw [singleton, List.mem_singleton] at inAll
  simpa [inAll] using assigned

/-- The first assignment in a model's derivation that is missing from the
current state has an enabled rule. This remains true when the current
state already contains facts from later in that derivation. -/
theorem missing_assignment_has_offer (rules : List Rule) (current model upper : Database)
    (reached : Reachable rules model)
    (modelFits : ∀ key value, model key = some value → upper key = some value)
    (currentFits : ∀ key value, current key = some value → upper key = some value)
    (missing : ∃ key value, model key = some value ∧ current key ≠ some value) :
    ∃ rule ∈ rules, enabled current rule ∧
      ∃ successor, offersExtension current successor rule.head ∧
        ∀ key value, successor key = some value → upper key = some value := by
  induction reached with
  | empty =>
    obtain ⟨_, _, impossible, _⟩ := missing
    simp at impossible
  | @step before after rule _ member active step ih =>
    have beforeFits : ∀ key value, before key = some value → upper key = some value :=
      fun key value present =>
        modelFits key value (step_preserves_assignment before after rule.head key value present step)
    by_cases earlier : ∃ key value, before key = some value ∧ current key ≠ some value
    · exact ih beforeFits earlier
    · have included : ∀ key value, before key = some value → current key = some value := by
        intro key value present
        by_cases presentNow : current key = some value
        · exact presentNow
        · exact False.elim (earlier ⟨key, value, present, presentNow⟩)
      have strict : after ≠ before := by
        intro same
        apply earlier
        simpa [same] using missing
      have extension := (offers_extension_exact before after rule.head).mpr ⟨strict, step⟩
      have lift (key value : Nat) (afterEq : after = assign before key value) :
          current key = none ∧
            ∀ k v, assign current key value k = some v → upper k = some v := by
        have target := modelFits key value (by simp [afterEq, assign])
        have absent : current key = none := by
          cases h : current key with
          | none => rfl
          | some prior =>
            have agrees := Option.some.inj ((currentFits key prior h).symm.trans target)
            obtain ⟨k, v, found, absent⟩ := missing
            exfalso
            apply absent
            by_cases same : k = key
            · subst k
              simp [afterEq, assign] at found
              simpa [agrees, found] using h
            · exact included k v (by simpa [afterEq, assign, same] using found)
        refine ⟨absent, ?_⟩
        intro k v found
        by_cases same : k = key
        · subst k
          simp [assign] at found
          simpa [found] using target
        · exact currentFits k v (by simpa [assign, same] using found)
      refine ⟨rule, member, fun fact inBody => included fact.1 fact.2 (active fact inBody), ?_⟩
      cases head : rule.head with
      | openOffer key value =>
        rw [head] at extension
        obtain ⟨unset, fits⟩ := lift key value extension.2
        exact ⟨assign current key value, ⟨unset, rfl⟩, fits⟩
      | closed key values =>
        rw [head] at extension
        obtain ⟨value, allowed, equal⟩ := extension.2
        obtain ⟨unset, fits⟩ := lift key value equal
        exact ⟨assign current key value, ⟨unset, value, allowed, rfl⟩, fits⟩

/-- A model-compatible value has grounded support on the selected key:
a closed seed offers every value in the intersection. The prioritized
edge is therefore still a fact-set step. -/
theorem forced_step_reachable (rules : List Rule) (current : Database)
    (reached : Reachable rules current) (key value : Nat)
    (seed : List Nat) (restrictions : List (List Nat))
    (source : ∃ rule ∈ rules, enabled current rule ∧ rule.head = .closed key seed)
    (unset : current key = none)
    (singleton : constrainedValues seed restrictions = [value]) :
    Reachable rules (assign current key value) := by
  have included : value ∈ constrainedValues seed restrictions := by simp [singleton]
  have offered := ((constrained_values_exact seed restrictions value).mp included).1
  obtain ⟨rule, belongs, active, head⟩ := source
  apply Reachable.step reached belongs active
  rw [head]
  exact ((offers_extension_exact current (assign current key value) (.closed key seed)).mp
    ⟨unset, value, offered, rfl⟩).2

/-- A compatible model survives a deduction-first step, even if its original
derivation used a different order. -/
theorem forced_step_preserves_model (current model : Database)
    (key value : Nat) (compatible : ∀ k v, current k = some v → model k = some v)
    (forced : model key = some value) :
    ∀ k v, assign current key value k = some v → model k = some v := by
  intro k v assigned
  by_cases same : k = key
  · subst k
    simp [assign] at assigned
    simpa [assigned] using forced
  · exact compatible k v (by simpa [assign, same] using assigned)

/-- A retained branch agrees with every currently enabled closed offer. -/
def allowed (rules : List Rule) (current : Database) (key value : Nat) : Prop :=
  ∀ values, (∃ rule ∈ rules, enabled current rule ∧ rule.head = .closed key values) →
    value ∈ values

/-- A scheduler may pick any justified singleton. With none selected it
retains every supported assignment that satisfies all enabled closed offers. -/
def Scheduled (rules : List Rule) (forced : Database → Option Fact)
    (current : Database) (key value : Nat) : Prop :=
  match forced current with
  | some choice => (key, value) = choice
  | none => allowed rules current key value ∧
      ∃ rule ∈ rules, enabled current rule ∧
        offersExtension current (assign current key value) rule.head

theorem compatible_model_has_scheduled_step (rules : List Rule)
    (forced : Database → Option Fact)
    (justified : ∀ current key value, forced current = some (key, value) →
      current key = none ∧ ∃ seed restrictions,
        (∃ rule ∈ rules, enabled current rule ∧ rule.head = .closed key seed) ∧
        (∀ values ∈ restrictions,
          ∃ rule ∈ rules, enabled current rule ∧ rule.head = .closed key values) ∧
        constrainedValues seed restrictions = [value])
    (current model : Database) (target : solution rules model)
    (fits : ∀ key value, current key = some value → model key = some value)
    (different : current ≠ model) :
    ∃ key value, current key = none ∧ model key = some value ∧
      Scheduled rules forced current key value := by
  cases decision : forced current with
  | some pair =>
    obtain ⟨key, value⟩ := pair
    obtain ⟨unset, seed, restrictions, source, others, singleton⟩ :=
      justified current key value decision
    exact ⟨key, value, unset,
      closed_intersection_forced current model key value seed restrictions
        rules source others fits target.2 singleton, by simp [Scheduled, decision]⟩
  | none =>
    have missing : ∃ key value, model key = some value ∧ current key ≠ some value := by
      by_cases existsMissing : ∃ key value, model key = some value ∧ current key ≠ some value
      · exact existsMissing
      exfalso
      apply different
      funext key
      cases assigned : model key with
      | some value =>
        by_cases present : current key = some value
        · exact present
        · exact False.elim (existsMissing ⟨key, value, assigned, present⟩)
      | none =>
        cases value : current key with
        | none => rfl
        | some prior =>
          have impossible := fits key prior value
          simp [assigned] at impossible
    obtain ⟨rule, member, active, successor, extension, preserves⟩ :=
      missing_assignment_has_offer rules current model model target.1
        (fun _ _ h => h) fits missing
    have recordStep (key value : Nat) (unset : current key = none)
        (same : successor = assign current key value) :
        ∃ key value, current key = none ∧ model key = some value ∧
          Scheduled rules forced current key value := by
      have assigned := preserves key value (by simp [same, assign])
      refine ⟨key, value, unset, assigned, ?_⟩
      simp only [Scheduled, decision]
      refine ⟨?_, rule, member, active, same ▸ extension⟩
      rintro values ⟨closedRule, inRules, enabledNow, head⟩
      have result := target.2 closedRule inRules
        (fun fact inBody => fits fact.1 fact.2 (enabledNow fact inBody))
      rw [head] at result
      obtain ⟨prior, inValues, found⟩ := (closed_saturated_iff model key values).mp result
      have equal := Option.some.inj (found.symm.trans assigned)
      simpa [equal] using inValues
    cases head : rule.head with
    | openOffer key value =>
      rw [head] at extension
      exact recordStep key value extension.1 extension.2
    | closed key values =>
      rw [head] at extension
      obtain ⟨value, _, same⟩ := extension.2
      exact recordStep key value extension.1 same

/-- Exhausting a deduction-first worklist publishes exactly the reachable
saturated models on a finite support. Each compatible scheduled extension
removes a missing key, even when deduction changes the derivation order. -/
theorem exhausted_deduction_answers_exact (rules : List Rule)
    (forced : Database → Option Fact) (processed accepted : Database → Prop)
    (justified : ∀ current key value, forced current = some (key, value) →
      current key = none ∧ ∃ seed restrictions,
        (∃ rule ∈ rules, enabled current rule ∧ rule.head = .closed key seed) ∧
        (∀ values ∈ restrictions,
          ∃ rule ∈ rules, enabled current rule ∧ rule.head = .closed key values) ∧
        constrainedValues seed restrictions = [value])
    (initial : processed (fun _ => none))
    (closed : ∀ current key value, processed current →
      Scheduled rules forced current key value → processed (assign current key value))
    (sound : ∀ current, processed current → Reachable rules current)
    (publish : ∀ current, accepted current ↔ processed current ∧ saturated rules current)
    (model : Database) (keys : List Nat)
    (support : ∀ key value, model key = some value → key ∈ keys) :
    accepted model ↔ solution rules model := by
  rw [publish]
  refine ⟨fun h => ⟨sound model h.1, h.2⟩, fun target => ⟨?_, target.2⟩⟩
  have enumerate (n : Nat) : ∀ (todo : List Nat) (current : Database), todo.length = n →
      processed current →
      (∀ key value, current key = some value → model key = some value) →
      (∀ key value, model key = some value → current key ≠ some value → key ∈ todo) →
      processed model := by
    induction n using Nat.strongRecOn
    rename_i n ih
    intro todo current size done fits missing
    by_cases same : current = model
    · exact same ▸ done
    · obtain ⟨key, value, unset, assigned, scheduled⟩ :=
        compatible_model_has_scheduled_step rules forced justified current model target fits same
      have member := missing key value assigned (by simp [unset])
      have smaller : (todo.erase key).length < n := by
        have nonempty := List.length_pos_of_mem member
        rw [List.length_erase_of_mem member, ← size]
        omega
      apply ih _ smaller (todo.erase key) (assign current key value) rfl
        (closed current key value done scheduled)
        (forced_step_preserves_model current model key value fits assigned)
      intro k v present absent
      have other : k ≠ key := by
        intro sameKey
        subst k
        have agrees := Option.some.inj (present.symm.trans assigned)
        simp [assign, agrees] at absent
      exact (List.mem_erase_of_ne other).mpr (missing k v present (by simpa [assign, other] using absent))
  exact enumerate keys.length keys (fun _ => none) rfl initial (by simp) (fun k v h _ => support k v h)

end Ascent.FiniteChoice
