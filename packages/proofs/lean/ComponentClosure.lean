-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import SemiNaive
import FiniteHeight
import MillionQueryWorkload

/-! Ground positive rules, component-local saturation and least closure.
This is semantic decomposition, not a scheduler state machine. Grounding,
native SCC projection and general non-ground termination are separate obligations. -/
namespace Ascent.ComponentClosure

section BoundSelection

/-- For one already bound origin, a unique target list yields zero or
one row. The bit test is on that same published cut. -/
theorem bound_target_filter {Vertex : Type} [DecidableEq Vertex]
    (targets : List Vertex) (unique : targets.Nodup) (target : Vertex) :
    targets.filter (fun v => decide (v = target)) =
      if target ∈ targets then [target] else [] := by
  induction targets with
  | nil => simp
  | cons first rest ih =>
    obtain ⟨absent, uniqueRest⟩ := List.nodup_cons.mp unique
    by_cases same : first = target
    · subst first
      simp [ih uniqueRest, absent]
    · simp [same, Ne.symm same, ih uniqueRest]

theorem bound_pair_bit_test {Vertex : Type} [DecidableEq Vertex]
    (targets : List Vertex) (unique : targets.Nodup) (origin target : Vertex)
    (reachable : Bool) (exact : reachable = true ↔ target ∈ targets) :
    (targets.filter (fun v => decide (v = target))).map (fun v => (origin, v)) =
      if reachable then [(origin, target)] else [] := by
  rw [bound_target_filter targets unique]
  simp [← exact]
  split <;> rfl

/-- After the singleton callback, a changed caller-owned key or column
list must resume the original walk after the row already consumed. -/
theorem bound_pair_callback_suffix (before after : List Int) (target : Int)
    (earlier : ∀ v ∈ before, v < target) (later : ∀ v ∈ after, target < v) :
    (before ++ target :: after).filter (fun v => decide (target < v)) = after := by
  have skip : before.filter (fun v => decide (target < v)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro v present
    simp [Int.not_lt.mpr (Int.le_of_lt (earlier v present))]
  have keep : after.filter (fun v => decide (target < v)) = after := by
    apply List.filter_eq_self.mpr
    intro v present
    simp [later v present]
  simp [skip, keep]

end BoundSelection

/-- A completion changes readiness only on its outgoing edges. A successor
becomes newly ready exactly when that completion consumes its last credit. -/
theorem completion_unlocks_last_predecessor (remaining : Nat) (hasEdge : Bool)
    (credit : hasEdge = true → 0 < remaining) :
    (0 < remaining ∧ (if hasEdge then remaining - 1 else remaining) = 0) ↔
      (hasEdge = true ∧ remaining = 1) := by
  cases hasEdge with
  | false => simp; omega
  | true => simp; omega

/-- On the original increasing task order, the first ready task is the
minimum ready ordinal. An ordered ready queue may make the same choice. -/
theorem first_ready_is_minimum (ready : Nat → Bool) (pending : List Nat)
    (ordered : pending.Pairwise (· < ·)) (task : Nat)
    (first : pending.find? ready = some task) :
    ready task = true ∧ ∀ other ∈ pending, ready other = true → task ≤ other := by
  induction pending with
  | nil => simp at first
  | cons head tail ih =>
    rw [List.pairwise_cons] at ordered
    by_cases isReady : ready head = true
    · have same : head = task := by simpa [List.find?, isReady] using first
      subst task
      refine ⟨isReady, ?_⟩
      intro other present _
      simp only [List.mem_cons] at present
      rcases present with rfl | inTail
      · exact Nat.le_refl _
      · exact Nat.le_of_lt (ordered.1 other inTail)
    · have tailFirst : tail.find? ready = some task := by
        simpa [List.find?, isReady] using first
      obtain ⟨selected, minimum⟩ := ih ordered.2 tailFirst
      refine ⟨selected, ?_⟩
      intro other present available
      simp only [List.mem_cons] at present
      rcases present with rfl | inTail
      · exact (isReady available).elim
      · exact minimum other inTail available

/-- Nonempty data-graph reachability. Rule SCCs are independent of this
relation, which may be used only by a recognized transitive rule. -/
inductive EdgePath {Vertex : Type} (edge : Vertex → Vertex → Prop) : Vertex → Vertex → Prop
  | step {source target} : edge source target → EdgePath edge source target
  | append {source middle target} :
      EdgePath edge source middle → EdgePath edge middle target → EdgePath edge source target

def CrossEdge {Vertex Group : Type} (edge : Vertex → Vertex → Prop) (owner : Vertex → Group)
    (origin destination : Group) : Prop :=
  origin ≠ destination ∧
    ∃ source target, edge source target ∧ owner source = origin ∧ owner target = destination

private theorem cross_path_target_owner {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    {owner : Vertex → Group} {origin destination : Group}
    (path : EdgePath (CrossEdge edge owner) origin destination) :
    ∃ vertex, owner vertex = destination := by
  induction path with
  | step cross =>
    obtain ⟨_, _, target, _, _, targetOwner⟩ := cross
    exact ⟨target, targetOwner⟩
  | append _ _ _ next => exact next

/-- A quotient path lifts for every representative at either endpoint.
Each cross edge has a concrete witness, and paths inside a component
connect consecutive witnesses. The lifted path is necessarily nonempty. -/
theorem lift_cross_component_path {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    {owner : Vertex → Group}
    (connect : ∀ source target, owner source = owner target → source = target ∨ EdgePath edge source target)
    {origin destination : Group} (path : EdgePath (CrossEdge edge owner) origin destination) :
    ∀ source target, owner source = origin → owner target = destination → EdgePath edge source target := by
  induction path with
  | step cross =>
    intro source target sourceOwner targetOwner
    obtain ⟨_, entry, exit, witness, entryOwner, exitOwner⟩ := cross
    have enter : EdgePath edge source exit := by
      rcases connect source entry (sourceOwner.trans entryOwner.symm) with same | before
      · subst entry
        exact .step witness
      · exact .append before (.step witness)
    rcases connect exit target (exitOwner.trans targetOwner.symm) with same | after
    · subst target
      exact enter
    · exact .append enter after
  | append firstPath _ prior next =>
    intro source target sourceOwner targetOwner
    -- Every group appearing between two steps has a representative,
    -- since each quotient edge is witnessed by a concrete input edge.
    obtain ⟨vertex, vertexOwner⟩ := cross_path_target_owner firstPath
    exact .append (prior source vertex sourceOwner vertexOwner)
      (next vertex target vertexOwner targetOwner)

/-- Each concrete step stays in its group or contributes one quotient
edge. Removing the internal steps preserves every cross-group path. -/
theorem collapse_cross_component_path {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    (owner : Vertex → Group) {source target : Vertex} (path : EdgePath edge source target) :
    owner source = owner target ∨ EdgePath (CrossEdge edge owner) (owner source) (owner target) := by
  induction path with
  | @step a b witness =>
    by_cases internal : owner a = owner b
    · exact Or.inl internal
    · exact Or.inr (.step ⟨internal, _, _, witness, rfl, rfl⟩)
  | append _ _ prior next =>
    rcases prior with samePrior | crossPrior <;> rcases next with sameNext | crossNext
    · exact Or.inl (samePrior.trans sameNext)
    · exact Or.inr (by rwa [samePrior])
    · exact Or.inr (by rwa [← sameNext])
    · exact Or.inr (.append crossPrior crossNext)

theorem cross_component_path_exact {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    {owner : Vertex → Group}
    (connect : ∀ source target, owner source = owner target → source = target ∨ EdgePath edge source target)
    {source target : Vertex} (distinct : owner source ≠ owner target) :
    EdgePath edge source target ↔ EdgePath (CrossEdge edge owner) (owner source) (owner target) := by
  constructor
  · intro path
    exact (collapse_cross_component_path owner path).resolve_left distinct
  · intro path
    exact lift_cross_component_path connect path source target rfl rfl

/-- A diagonal output requires a nonempty cycle. A singleton without
an internal edge cannot justify a reflexive tuple by its membership. -/
theorem nonempty_component_cycle {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    {owner : Vertex → Group}
    (connect : ∀ source target, owner source = owner target → source = target ∨ EdgePath edge source target)
    {source target : Vertex} (internal : owner target = owner source) (first : edge source target) :
    EdgePath edge source source := by
  rcases connect target source internal with same | back
  · subst target
    exact .step first
  · exact .append (.step first) back

private theorem path_first_step {Vertex : Type} {edge : Vertex → Vertex → Prop}
    {source target : Vertex} (path : EdgePath edge source target) :
    ∃ first, edge source first ∧ (first = target ∨ EdgePath edge first target) := by
  induction path with
  | step witness => exact ⟨_, witness, Or.inl rfl⟩
  | append _ tail head _ =>
    obtain ⟨first, witness, rest⟩ := head
    refine ⟨first, witness, Or.inr ?_⟩
    rcases rest with equal | onward
    · exact equal.symm ▸ tail
    · exact .append onward tail

/-- The diagonal case has its own criterion. This rules out spurious
reflexive results for an isolated singleton or a singleton with only
external successors. -/
theorem component_self_path_exact {Vertex Group : Type} {edge : Vertex → Vertex → Prop}
    {owner : Vertex → Group}
    (connect : ∀ source target, owner source = owner target → source = target ∨ EdgePath edge source target)
    (separate : ∀ source target, EdgePath edge source target →
      EdgePath edge target source → owner source = owner target)
    (source : Vertex) :
    EdgePath edge source source ↔ ∃ target, edge source target ∧ owner target = owner source := by
  constructor
  · intro cycle
    obtain ⟨first, witness, rest⟩ := path_first_step cycle
    refine ⟨first, witness, ?_⟩
    rcases rest with same | back
    · rw [same]
    · exact separate first source back (.step witness)
  · rintro ⟨first, witness, internal⟩
    exact nonempty_component_cycle connect internal witness

/-- One source group has one target set. A group product can be charged
before any pair in it is expanded. Uniqueness of the admitted member
and target lists is a separate obligation of the partition. -/
theorem factored_group_row_count {Vertex : Type} (origins targets : List Vertex) :
    (origins.flatMap fun source => targets.map fun target => (source, target)).length =
      origins.length * targets.length := by
  induction origins with
  | nil => simp
  | cons source rest count =>
    simp [count, Nat.succ_mul, Nat.add_comm]

private def ReachOrSame {V : Type} (edge : V → V → Prop) (a b : V) : Prop :=
  a = b ∨ EdgePath edge a b

/-- The packed-source reader advances matching rows and checks the entire
suffix after its one skipped row. The model stores pairs as single rows. -/
def orderedExtra {Row : Type} [DecidableEq Row] : List Row → List Row → Option Row
  | [], _ => none
  | row :: tail, [] => if tail = [] then some row else none
  | row :: tail, next :: rest =>
    if row = next then orderedExtra tail rest
    else if tail = next :: rest then some row else none

theorem ordered_extra_exact {Row : Type} [DecidableEq Row]
    (long short : List Row) (added : Row) (accepted : orderedExtra long short = some added) :
    ∃ before after, long = before ++ added :: after ∧ short = before ++ after := by
  induction long generalizing short with
  | nil => simp [orderedExtra] at accepted
  | cons row tail ih =>
    cases short with
    | nil =>
      by_cases empty : tail = []
      · have same : row = added := by simpa [orderedExtra, empty] using accepted
        exact ⟨[], [], by simp [empty, same], rfl⟩
      · simp [orderedExtra, empty] at accepted
    | cons next rest =>
      by_cases same : row = next
      · subst next
        have acceptedTail : orderedExtra tail rest = some added := by
          simpa [orderedExtra] using accepted
        obtain ⟨before, after, lt, st⟩ := ih rest acceptedTail
        exact ⟨row :: before, after, by simp [lt], by simp [st]⟩
      · by_cases aligned : tail = next :: rest
        · have picked : row = added := by
            simpa [orderedExtra, same, aligned] using accepted
          exact ⟨[], next :: rest, by simp [picked, aligned], by simp⟩
        · simp [orderedExtra, same, aligned] at accepted

def DeleteEdge {V : Type} (edge : V → V → Prop) (x y a b : V) : Prop :=
  edge a b ∧ (a ≠ x ∨ b ≠ y)

/-- The packed splice inserts the edge at its original position in the
origin's adjacency. A fresh rebuild projects the very same sequence. -/
theorem ordered_adjacency_splice {V : Type} [DecidableEq V]
    (before after : List (V × V)) (origin target : V) :
    (((before ++ (origin, target) :: after).filter
        (fun row => decide (row.1 = origin))).map Prod.snd) =
      ((before.filter (fun row => decide (row.1 = origin))).map Prod.snd) ++
        target :: ((after.filter (fun row => decide (row.1 = origin))).map Prod.snd) := by
  simp [List.filter_append]

/-- A deleted cross edge leaves the internal edges of every SCC unchanged.
The quotient cannot gain a return path by deletion. -/
theorem cross_delete_keeps_internal {V Group : Type} (owner : V → Group)
    (edge : V → V → Prop) (x y a b : V)
    (cross : owner x ≠ owner y) (internal : owner a = owner b) :
    DeleteEdge edge x y a b ↔ edge a b := by
  constructor
  · exact And.left
  · intro old
    refine ⟨old, ?_⟩
    by_cases origin : a = x
    · right
      intro dest
      exact cross (by simpa [origin, dest] using internal)
    · exact .inl origin

/-- A row outside the old predecessor cone of the deleted edge cannot
have used that edge. Its old closure row remains exact. -/
theorem delete_unaffected_path {V : Type} {edge : V → V → Prop} {start finish : V}
    (path : EdgePath edge start finish) (x y : V)
    (noAccess : ¬ ReachOrSame edge start x) :
    EdgePath (DeleteEdge edge x y) start finish := by
  induction path with
  | step one =>
    exact .step ⟨one, .inl (fun h => noAccess (.inl h))⟩
  | append leading trailing first second =>
    apply EdgePath.append (first noAccess)
    apply second
    intro fromMiddle
    exact noAccess (.inr (by
      rcases fromMiddle with h | reach
      · simpa [h] using leading
      · exact .append leading reach))

/-- For a fixed published mask, evaluating a group on demand enumerates
the same ordered result as the eager group table. -/
theorem deferred_group_selection {Group Row : Type} (groups : List Group)
    (orderedRows : Group → List Row) :
    ((groups.map (fun g => fun () => orderedRows g)).map (fun build => build ())).flatten =
      (groups.map orderedRows).flatten := by
  simp [List.map_map, Function.comp_def]

/-- A run is a consecutive portion of the numerically ordered vertex
sequence. Its labels all belong to the run's fixed SCC. Only the mask
changes while the published partition remains the same. -/
theorem ordered_runs_select_exact {Group Vertex : Type}
    (runs : List (Group × List Vertex)) (owner : Vertex → Group)
    (allowed : Group → Bool)
    (oneOwner : ∀ run ∈ runs, ∀ v ∈ run.2, owner v = run.1) :
    runs.flatMap (fun (group, labels) => if allowed group then labels else []) =
      (runs.flatMap Prod.snd).filter (fun v => allowed (owner v)) := by
  induction runs with
  | nil => rfl
  | cons first rest ih =>
    have onRest : ∀ run ∈ rest, ∀ v ∈ run.2, owner v = run.1 := by
      intro run inRest v inRun
      exact oneOwner run (List.mem_cons_of_mem _ inRest) v inRun
    have onFirst : ∀ v ∈ first.2, owner v = first.1 :=
      oneOwner first List.mem_cons_self
    simp only [List.flatMap_cons, List.filter_append, ih onRest]
    congr 1
    cases selected : allowed first.1 with
    | false =>
      simp only [Bool.false_eq_true, ite_false]
      symm
      apply List.filter_eq_nil_iff.mpr
      intro v present
      simp [onFirst v present, selected]
    | true =>
      simp only [ite_true]
      symm
      apply List.filter_eq_self.mpr
      intro v present
      simp [onFirst v present, selected]

private theorem extend_path {V : Type} {edge : V → V → Prop}
    {a b c : V} (prefixPath : ReachOrSame edge a b) (suffixPath : EdgePath edge b c) :
    EdgePath edge a c := by
  rcases prefixPath with rfl | prior
  · exact suffixPath
  · exact .append prior suffixPath

private theorem restrict_path {V : Type} {edge : V → V → Prop}
    {a b c : V} (prefixPath : EdgePath edge a b) (suffixPath : ReachOrSame edge b c) :
    EdgePath edge a c := by
  rcases suffixPath with rfl | rest
  · exact prefixPath
  · exact .append prefixPath rest

private def InsertEdge {V : Type} (edge : V → V → Prop) (x y a b : V) : Prop :=
  edge a b ∨ (a = x ∧ b = y)

private theorem unchanged_path_after_insert {V : Type} {edge : V → V → Prop}
    {a b : V} (path : EdgePath edge a b) (x y : V) :
    EdgePath (InsertEdge edge x y) a b := by
  induction path with
  | step witness => exact .step (.inl witness)
  | append _ _ before after => exact .append before after

/-- The delta of one admitted edge is the product of old predecessors of
its origin and old successors of its target, including the endpoints.
Even a path using the new edge more than once needs it only once. -/
theorem insert_edge_exact {V : Type} {edge : V → V → Prop} (x y a b : V) :
    EdgePath (InsertEdge edge x y) a b ↔
      EdgePath edge a b ∨ (ReachOrSame edge a x ∧ ReachOrSame edge y b) := by
  constructor
  · intro path
    induction path with
    | step one =>
      rcases one with old | ⟨rfl, rfl⟩
      · exact .inl (.step old)
      · exact .inr ⟨.inl rfl, .inl rfl⟩
    | append _ _ left right =>
      rcases left with oldLeft | ⟨fromLeft, toMiddle⟩ <;>
        rcases right with oldRight | ⟨fromMiddle, toRight⟩
      · exact .inl (.append oldLeft oldRight)
      · exact .inr ⟨.inr (restrict_path oldLeft fromMiddle), toRight⟩
      · exact .inr ⟨fromLeft, .inr (extend_path toMiddle oldRight)⟩
      · exact .inr ⟨fromLeft, toRight⟩
  · rintro (old | ⟨fromLeft, toRight⟩)
    · exact unchanged_path_after_insert old x y
    · have newEdge : EdgePath (InsertEdge edge x y) x y := .step (.inr ⟨rfl, rfl⟩)
      have leading : ReachOrSame (InsertEdge edge x y) a x :=
        fromLeft.imp id (fun p => unchanged_path_after_insert p x y)
      have trailing : ReachOrSame (InsertEdge edge x y) y b :=
        toRight.imp id (fun p => unchanged_path_after_insert p x y)
      exact restrict_path (extend_path leading newEdge) trailing

/-- The native group-mask assignment keeps every old bit and installs
the delta targets only for a group that can reach the new edge's origin. -/
theorem append_mask_member (old successors target column : Nat) (affected : Bool) :
    (if affected then old ||| (successors ||| 2 ^ target) else old).testBit column =
      (old.testBit column || (affected && (successors.testBit column || decide (target = column)))) := by
  cases affected <;> simp [Nat.testBit_two_pow]

/-- A dense lookup may narrow the visitor only when the inverse map
recovers the selected key. Missing keys and aliased ordinals establish
no membership. -/
theorem dense_key_match {Key : Type} [BEq Key] [LawfulBEq Key]
    (labels : List Key) (distinct : labels.Nodup) (key : Key) (ordinal : Nat)
    (inBounds : ordinal < labels.length) (index : Key → Option Nat)
    [Decidable (key ∈ labels)]
    (lookup : index key = if key ∈ labels then some (labels.idxOf key) else none) :
    index key = some ordinal ↔ labels[ordinal] = key := by
  rw [lookup]
  by_cases found : key ∈ labels
  · simp [found]
    constructor
    · intro located
      have valid : labels.idxOf key < labels.length := located.symm ▸ inBounds
      have recovered := List.getElem_idxOf valid
      subst ordinal
      exact recovered
    · intro recovered
      rw [← recovered]
      exact distinct.idxOf_getElem ordinal inBounds
  · simp [found]
    exact fun same => found (same ▸ List.getElem_mem inBounds)

/-- Replacing a source by a cut that deletes edges can invalidate old
reachability. Rebuilding from the new adjacency cannot invent an edge
path outside the old graph when the whole update consists of deletes. -/
theorem reach_after_delete {V : Type} {old new : V → V → Prop}
    (subset : ∀ a b, new a b → old a b) {source target : V}
    (path : EdgePath new source target) : EdgePath old source target := by
  induction path with
  | step edge => exact .step (subset _ _ edge)
  | append _ _ before after => exact .append before after

/-- The native source slot is an owned identity. A revision is attached
on successful publication. Proof replay requires both coordinates and
checks every concrete edge in that same version. -/
def ReplaysCut {V Cut : Type} (read : Cut → V → V → Prop)
    (expected captured : Cut × Nat) (a b : V) : Prop :=
  expected = captured ∧ EdgePath (read captured.1) a b

theorem replay_rejects_other_cut {V Cut : Type} {read : Cut → V → V → Prop}
    {expected captured : Cut × Nat} {a b : V} (different : expected ≠ captured) :
    ¬ ReplaysCut read expected captured a b := fun h => different h.1

theorem replay_uses_published_edges {V Cut : Type} {read : Cut → V → V → Prop}
    {expected captured : Cut × Nat} {a b : V} (replays : ReplaysCut read expected captured a b) :
    EdgePath (read expected.1) a b := by
  rw [replays.1]
  exact replays.2

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

/-- When no rule reads a local output, a completed first pass already proves
closure. Every premise in the enlarged cut came from the original input. -/
theorem one_pass_closed (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact)
    (noFeedback : ¬ Depends rules owner component component) :
    ClosedAt rules owner component (step rules owner component database) := by
  intro rule member owned body
  refine Or.inr ⟨rule, member, owned, ?_, rfl⟩
  intro fact present
  have foreign : owner fact ≠ component := fun same =>
    noFeedback ⟨rule, member, owned, fact, present, same⟩
  exact (iterate_frame rules owner component database 1 fact foreign).mp (body fact present)

theorem no_second_pass (rules : List (Rule Fact)) (owner : Fact → Component)
    (component : Component) (database : Database Fact)
    (noFeedback : ¬ Depends rules owner component component) (fact : Fact) :
    step rules owner component (step rules owner component database) fact ↔
      step rules owner component database fact := by
  constructor
  · rintro (old | ⟨rule, member, owned, body, rfl⟩)
    · exact old
    · exact one_pass_closed rules owner component database noFeedback rule member owned body
  · exact Or.inl

def commitPrivateOutput [DecidableEq Relation]
    (retain : Bool) (members reads : List Relation) : Bool :=
  retain || reads.any (fun relation => members.contains relation)

theorem skipped_private_output [DecidableEq Relation]
    (retain : Bool) (members reads : List Relation)
    (skip : commitPrivateOutput retain members reads = false) :
    retain = false ∧ ∀ relation ∈ reads, relation ∉ members := by
  simpa [commitPrivateOutput] using skip

inductive SlotRole where
  | fresh | bound | other
  deriving DecidableEq

abbrev SlotTerm := SlotRole × Nat

def consecutiveSlots (role : SlotRole) (start : Nat) : Nat → List SlotTerm
  | 0 => []
  | width + 1 => (role, start) :: consecutiveSlots role (start + 1) width

/-- Compiled terms from the two descriptors are checked before any row read. -/
def checkIdentitySlots (start : Nat) : List SlotTerm → List SlotTerm → Bool
  | [], [] => true
  | input :: more, output :: rest =>
      decide (input = (.fresh, start) ∧ output = (.bound, start)) &&
        checkIdentitySlots (start + 1) more rest
  | _, _ => false

theorem checked_identity_slots (start : Nat) (input output : List SlotTerm)
    (checked : checkIdentitySlots start input output = true) :
    input = consecutiveSlots .fresh start input.length ∧
      output = consecutiveSlots .bound start input.length := by
  induction input generalizing start output with
  | nil => cases output <;> simp_all [checkIdentitySlots, consecutiveSlots]
  | cons term remaining ih =>
      cases output with
      | nil => simp [checkIdentitySlots] at checked
      | cons head more =>
          simp only [checkIdentitySlots, Bool.and_eq_true, decide_eq_true_eq] at checked
          obtain ⟨⟨source, target⟩, rest⟩ := checked
          obtain ⟨inputTail, outputTail⟩ := ih (start + 1) more rest
          simpa only [List.length_cons, consecutiveSlots, source, target, List.cons.injEq,
            true_and] using And.intro inputTail outputTail

inductive ScanEvent (Row : Type) where
  | checkpoint
  | emit (row : Row)

/-- Seeded membership suppresses repeated heads, while every occurrence
still yields a checkpoint before novelty and owner budget charging. -/
def scanIdentity [DecidableEq Cell] (project : List Cell → List Cell)
    (known : List (List Cell)) : List (List Cell) → List (ScanEvent (List Cell))
  | [] => []
  | row :: rest =>
      let head := project row
      .checkpoint :: if head ∈ known then scanIdentity project known rest
                     else .emit head :: scanIdentity project (head :: known) rest

theorem borrowed_scan_keeps_order [DecidableEq Cell] (known rows : List (List Cell)) :
    scanIdentity Ascent.RowRepresentation.projectIdentity known rows = scanIdentity id known rows := by
  have equal : Ascent.RowRepresentation.projectIdentity = (id : List Cell → List Cell) :=
    funext Ascent.RowRepresentation.identity_projection_preserves_tuple
  rw [equal]

abbrev PairRadix : Nat := 2 ^ 24

/-- The worker may normalize a pair only inside its exact fixnum domain.
The fallback stores the original row in a separate membership table. -/
def workerPairKey (left right : Nat) : Nat :=
  Ascent.MillionQueryWorkload.bitmapIndex PairRadix left right

theorem worker_pair_key_exact (left right otherLeft otherRight : Nat)
    (rightBound : right < PairRadix) (otherBound : otherRight < PairRadix) :
    workerPairKey left right = workerPairKey otherLeft otherRight ↔
      left = otherLeft ∧ right = otherRight := by
  constructor
  · exact Ascent.MillionQueryWorkload.bitmap_index_injective _ _ _ _ _ rightBound otherBound
  · rintro ⟨rfl, rfl⟩
    rfl

theorem worker_pair_fits_word (left right : Nat)
    (leftBound : left < PairRadix) (rightBound : right < PairRadix) :
    workerPairKey left right ≤ 2 ^ 48 - 1 := by
  simp only [workerPairKey, Ascent.MillionQueryWorkload.bitmapIndex, PairRadix] at *
  omega

/-- Gerbil's table hashes inspect only the low bits of a fixnum. Move the
left coordinate into the low radix digit, leaving the high digit intact. -/
def mixedWorkerPairKey (left right : Nat) : Nat :=
  workerPairKey left ((right + (left * 331804471) % PairRadix) % PairRadix)

theorem mixed_worker_pair_key_exact (left right otherLeft otherRight : Nat)
    (rightBound : right < PairRadix) (otherBound : otherRight < PairRadix) :
    mixedWorkerPairKey left right = mixedWorkerPairKey otherLeft otherRight ↔
      left = otherLeft ∧ right = otherRight := by
  constructor
  · intro equal
    have positive : 0 < PairRadix := by decide
    have encoded := (worker_pair_key_exact left _ otherLeft _
      (Nat.mod_lt _ positive) (Nat.mod_lt _ positive)).mp equal
    rcases encoded with ⟨sameLeft, mixed⟩
    subst otherLeft
    generalize saltEq : (left * 331804471) % PairRadix = salt at mixed
    have saltBound : salt < PairRadix := saltEq ▸ Nat.mod_lt _ positive
    change (right + salt) % 16777216 = (otherRight + salt) % 16777216 at mixed
    change right < 16777216 at rightBound
    change otherRight < 16777216 at otherBound
    change salt < 16777216 at saltBound
    exact ⟨rfl, by omega⟩
  · rintro ⟨rfl, rfl⟩
    rfl

theorem mixed_worker_pair_fits_word (left right : Nat) (bound : left < PairRadix) :
    mixedWorkerPairKey left right ≤ 2 ^ 48 - 1 :=
  worker_pair_fits_word _ _ bound (Nat.mod_lt _ (by decide))

theorem mixed_worker_intermediate_fits (left right : Nat)
    (leftBound : left < PairRadix) (rightBound : right < PairRadix) :
    left * 331804471 + right ≤ 2 ^ 53 - 1 := by
  change left < 16777216 at leftBound
  change right < 16777216 at rightBound
  change left * 331804471 + right ≤ 9007199254740991
  omega

/-- A coordinator's extra frontier is read at later ready admission or
through a borrow of a source-only slot. Its merge targets are output slots. -/
def updateFrontier {Slot Row : Type} [DecidableEq Slot]
    (rows : Slot → List Row) (target : Slot) (row : Row) (read : Slot) : List Row :=
  if read = target then row :: rows read else rows read

theorem sole_assignment_frontier_readers {Slot Task Row : Type} [DecidableEq Slot]
    (rows : Slot → List Row) (target : Slot) (row : Row) (admitted : Task)
    (inputs : Task → List Slot) (sourceOnly : List Slot) (foreign : target ∉ sourceOnly) :
    ∀ read ∈ ([admitted].tail.flatMap inputs ++ sourceOnly),
      updateFrontier rows target row read = rows read := by
  intro read live
  have source : read ∈ sourceOnly := by simpa using live
  have different : read ≠ target := fun same => foreign (same ▸ source)
  simp [updateFrontier, different]

/-- The closing loop writes a delta root and count only for its members.
The initialization of the other slots is independent of their total roots. -/
def installDeltaRoots {Slot Row : Type} [DecidableEq Slot] (roots : Slot → List Row)
    (writes : List (Slot × List Row)) : Slot → List Row :=
  writes.foldl (fun prior (target, batch) read => if read = target then batch else prior read) roots

theorem external_delta_stays_empty {Slot Row : Type} [DecidableEq Slot]
    (roots : Slot → List Row) (writes : List (Slot × List Row))
    (members : List Slot) (external : Slot) (missing : external ∉ members)
    (owned : ∀ write ∈ writes, write.1 ∈ members) (empty : roots external = []) :
    installDeltaRoots roots writes external = [] := by
  induction writes generalizing roots with
  | nil => exact empty
  | cons write rest ih =>
      have distinct : external ≠ write.1 := fun same => missing (same ▸ owned write (by simp))
      simp only [installDeltaRoots, List.foldl_cons]
      exact ih _ (fun row inside => owned row (by simp [inside])) (by simp [distinct, empty])

inductive ClosureRead where
  | memberTotal | memberDelta | externalTotal
  deriving DecidableEq

def readClosure (memberTotal memberDelta externalTotal : List Row) : ClosureRead → List Row
  | .memberTotal => memberTotal
  | .memberDelta => memberDelta
  | .externalTotal => externalTotal

/-- After the full traversal, an exact linear pivot reads member delta and
external total. Other rules with only external pivots have no later visits. -/
theorem dead_member_total_preserves_reads (total delta external : List Row)
    (reads : List ClosureRead) (noTotal : .memberTotal ∉ reads) :
    reads.map (readClosure (delta ++ total) delta external) =
      reads.map (readClosure total delta external) := by
  induction reads with
  | nil => rfl
  | cons head tail ih =>
    have different : head ≠ .memberTotal := fun same => noTotal (by simp [same])
    have rest := ih (fun present => noTotal (by simp [present]))
    cases head <;> simp_all [readClosure]

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
/-! Founded recovery after source withdrawal. A dependency-closed overdeletion
set may be coarse (whole affected components) or fine (ground support nodes).
No transaction/scheduler protocol or counter optimization is modeled here. -/
namespace SourceWithdrawal

def DependencyClosed (rules : List (Rule Fact)) (affected : Database Fact) : Prop :=
  ∀ rule ∈ rules, ∀ premise ∈ rule.body, affected premise → affected rule.head

theorem unaffected_remains (rules : List (Rule Fact))
    (oldSeed newSeed affected : Database Fact)
    (sources : ∀ fact, oldSeed fact → ¬affected fact → newSeed fact)
    (closed : DependencyClosed rules affected) (fact : Fact)
    (derived : Derivable rules oldSeed fact) (outside : ¬affected fact) :
    Derivable rules newSeed fact := by
  revert outside
  induction derived with
  | seed present => intro outside; exact Derivable.seed (sources _ present outside)
  | fire rule member body ih =>
      intro outside
      apply Derivable.fire rule member
      intro premise read
      apply ih premise read
      intro affectedPremise
      exact outside (closed rule member premise read affectedPremise)

/-- Ground overdeletion uses one dependency edge for each rule premise, not
an AND rule. Any changed premise invalidates the head conservatively. -/
def dependencyRules (rules : List (Rule Fact)) : List (Rule Fact) :=
  rules.flatMap (fun rule => rule.body.map (fun premise => ⟨[premise], rule.head⟩))

def withdrawnSeeds (oldSeed newSeed : Database Fact) : Database Fact :=
  fun fact => oldSeed fact ∧ ¬newSeed fact

def affectedFromSources (rules : List (Rule Fact))
    (oldSeed newSeed : Database Fact) : Database Fact :=
  Derivable (dependencyRules rules) (withdrawnSeeds oldSeed newSeed)

theorem dependency_member (rules : List (Rule Fact)) (rule : Rule Fact)
    (member : rule ∈ rules) (premise : Fact) (read : premise ∈ rule.body) :
    (⟨[premise], rule.head⟩ : Rule Fact) ∈ dependencyRules rules := by
  exact List.mem_flatMap.mpr ⟨rule, member, List.mem_map.mpr ⟨premise, read, rfl⟩⟩

/-- Dependency closure follows from the constructed graph; it is no longer a
caller-supplied stability/closure assumption. -/
theorem constructed_closed (rules : List (Rule Fact)) (oldSeed newSeed : Database Fact) :
    DependencyClosed rules (affectedFromSources rules oldSeed newSeed) := by
  intro rule member premise read affected
  apply Derivable.fire ⟨[premise], rule.head⟩ (dependency_member rules rule member premise read)
  intro fact present
  have same : fact = premise := by simpa using present
  subst fact
  exact affected

theorem constructed_sources (rules : List (Rule Fact)) (oldSeed newSeed : Database Fact)
    (fact : Fact) (old : oldSeed fact) (outside : ¬affectedFromSources rules oldSeed newSeed fact) :
    newSeed fact := by
  exact Classical.byContradiction (fun absent => outside (Derivable.seed ⟨old, absent⟩))

/-- Completed unaffected facts are founded in the remaining sources. Cyclic
support alone cannot be used as a seed in this argument. -/
def retained (rules : List (Rule Fact)) (oldSeed affected : Database Fact) : Database Fact :=
  fun fact => Derivable rules oldSeed fact ∧ ¬affected fact

theorem recovery_exact (rules : List (Rule Fact))
    (oldSeed newSeed affected : Database Fact)
    (sources : ∀ fact, oldSeed fact → ¬affected fact → newSeed fact)
    (closed : DependencyClosed rules affected) (fact : Fact) :
    Derivable rules (fun f => newSeed f ∨ retained rules oldSeed affected f) fact ↔
      Derivable rules newSeed fact := by
  constructor
  · intro derived
    induction derived with
    | seed present =>
        rcases present with current | ⟨previous, outside⟩
        · exact Derivable.seed current
        · exact unaffected_remains rules oldSeed newSeed affected sources closed _ previous outside
    | fire rule member body ih => exact Derivable.fire rule member ih
  · intro derived
    induction derived with
    | seed present => exact Derivable.seed (Or.inl present)
    | fire rule member body ih => exact Derivable.fire rule member ih

/-- Concrete ground dependency propagation supplies both recovery premises.
The support graph must still represent every admitted ground rule/seed. -/
theorem constructed_recovery (rules : List (Rule Fact))
    (oldSeed newSeed : Database Fact) (fact : Fact) :
    Derivable rules
      (fun f => newSeed f ∨ retained rules oldSeed (affectedFromSources rules oldSeed newSeed) f) fact ↔
      Derivable rules newSeed fact :=
  recovery_exact rules oldSeed newSeed _ (constructed_sources rules oldSeed newSeed)
    (constructed_closed rules oldSeed newSeed) fact

/-- Every rule having a premise forbids source-free derivations. Empty-body
rules are deliberately excluded: those are independently founded constants. -/
theorem source_free_absent (rules : List (Rule Fact))
    (nonempty : ∀ rule ∈ rules, rule.body ≠ []) (fact : Fact) :
    ¬Derivable rules (fun _ => False) fact := by
  intro derived
  induction derived with
  | seed present => exact present
  | fire rule member body ih =>
      cases shape : rule.body with
      | nil => exact (nonempty rule member) shape
      | cons first rest => exact ih first (by simp [shape])

/-- Two source occurrences may denote the same fact. Withdrawing an occurrence
removes its support, rather than deleting the fact's other source occurrences. -/
def sourceFacts {Occurrence : Type} (value : Occurrence → Fact)
    (active : Occurrence → Prop) : Database Fact :=
  fun fact => ∃ occurrence, active occurrence ∧ value occurrence = fact

theorem remaining_occurrence {Occurrence : Type} (value : Occurrence → Fact)
    (active : Occurrence → Prop) (occurrence : Occurrence)
    (present : active occurrence) : sourceFacts value active (value occurrence) :=
  ⟨occurrence, present, rfl⟩
end SourceWithdrawal

end Ascent.ComponentClosure
