-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import GraphWorklist

namespace Ascent.BoundReachability

variable {Vertex : Type}
abbrev Adjacency (Vertex : Type) := Vertex → List Vertex

inductive Positive (edge : Vertex → Vertex → Prop) (origin : Vertex) : Vertex → Prop where
  | first : edge origin target → Positive edge origin target
  | extend : Positive edge origin parent → edge parent target → Positive edge origin target

/-- The bound seed is the successor bucket, so even a self-query needs an edge. -/
theorem seed_iff (adj : Adjacency Vertex) (origin target : Vertex) :
    RuleGraphClosure.Reachable (GraphWorklist.edge adj) (fun v => v ∈ adj origin) target ↔
      Positive (GraphWorklist.edge adj) origin target := by
  constructor
  · intro reached
    induction reached with
    | seed h => exact .first h
    | follow _ edge ih => exact .extend ih edge
  · intro positive
    induction positive with
    | first h => exact .seed h
    | extend _ edge ih => exact .follow ih edge

theorem prepend {edge : Vertex → Vertex → Prop} {origin next target : Vertex}
    (first : edge origin next) (path : Positive edge next target) : Positive edge origin target := by
  induction path with
  | first edge => exact .extend (.first first) edge
  | extend _ edge ih => exact .extend ih edge

theorem reverse_positive {edge : Vertex → Vertex → Prop} {origin target : Vertex}
    (path : Positive edge origin target) : Positive (fun a b => edge b a) target origin := by
  induction path with
  | first edge => exact .first edge
  | extend _ edge ih => exact prepend edge ih

theorem reversed_index_exact (forward incoming : Adjacency Vertex)
    (mirror : ∀ a b, a ∈ incoming b ↔ b ∈ forward a) (origin target : Vertex) :
    Positive (GraphWorklist.edge incoming) target origin ↔
      Positive (GraphWorklist.edge forward) origin target := by
  have reversed : (fun a b => GraphWorklist.edge incoming b a) = GraphWorklist.edge forward := by
    funext a b
    exact propext (mirror a b)
  constructor
  · intro found
    simpa only [reversed] using reverse_positive found
  · intro found
    rw [← reversed] at found
    exact reverse_positive found

theorem no_incoming_is_miss (adj : Adjacency Vertex) (origin target : Vertex)
    (noIncoming : ∀ v, target ∉ adj v) : ¬ Positive (GraphWorklist.edge adj) origin target := by
  intro found
  cases found with
  | first edge => exact noIncoming _ edge
  | extend _ edge => exact noIncoming _ edge

theorem exhausted_iff [DecidableEq Vertex] (adj : Adjacency Vertex) (origin target : Vertex)
    (unique : (adj origin).Nodup) (state : GraphWorklist.Work Vertex)
    (run : GraphWorklist.Run adj (GraphWorklist.initial (adj origin)) state)
    (empty : state.pending = []) :
    target ∈ state.selected ↔ Positive (GraphWorklist.edge adj) origin target :=
  (GraphWorklist.completed_exact adj _ unique state run empty target).trans
    (seed_iff adj origin target)

/-- The native FIFO needs only the set-valued transition, independent of
which pending vertex the worklist removes next. -/
theorem exhausted_fifo_iff (adj : Adjacency Vertex) (origin target : Vertex)
    (state : RuleGraphClosure.Work Vertex)
    (run : RuleGraphClosure.Run (GraphWorklist.edge adj)
      (RuleGraphClosure.initial (fun v => v ∈ adj origin)) state)
    (empty : ∀ v, ¬ state.pending v) :
    state.selected target ↔ Positive (GraphWorklist.edge adj) origin target :=
  (RuleGraphClosure.completed_exact (GraphWorklist.edge adj) _ state
    (RuleGraphClosure.run_invariant _ _ run (RuleGraphClosure.initial_invariant _ _))
    empty target).trans (seed_iff adj origin target)

def bucket (base : Adjacency Vertex) (changed : Vertex → Option (List Vertex))
    (source : Vertex) : List Vertex := (changed source).getD (base source)

section Edit
variable [DecidableEq Vertex]

def setBucket (adj : Adjacency Vertex) (source : Vertex) (row : List Vertex) : Adjacency Vertex :=
  fun v => if v = source then row else adj v

def setEdge (adj : Adjacency Vertex) (source target : Vertex) (present : Bool) : Adjacency Vertex :=
  setBucket adj source
    (if present then (if target ∈ adj source then adj source else target :: adj source)
     else (adj source).filter (· != target))

theorem index_write_exact (base : Adjacency Vertex) (changed : Vertex → Option (List Vertex))
    (source : Vertex) (row : List Vertex) :
    bucket base (fun v => if v = source then some row else changed v) =
      setBucket (bucket base changed) source row := by
  funext v
  by_cases h : v = source <;> simp [bucket, setBucket, h]

theorem set_edge_exact (adj : Adjacency Vertex) (source target start to : Vertex) (present : Bool) :
    to ∈ setEdge adj source target present start ↔
      if start = source ∧ to = target then present = true else to ∈ adj start := by
  by_cases hfrom : start = source
  · subst start
    by_cases hto : to = target
    · subst to
      cases present <;> simp [setEdge, setBucket]
      split <;> simp_all
    · cases present <;> simp [setEdge, setBucket, hto]
      split <;> simp [hto]
  · simp [setEdge, setBucket, hfrom]

theorem edit_preserves_mirror (forward incoming : Adjacency Vertex)
    (mirror : ∀ a b, a ∈ incoming b ↔ b ∈ forward a)
    (origin target : Vertex) (present : Bool) (a b : Vertex) :
    a ∈ setEdge incoming target origin present b ↔ b ∈ setEdge forward origin target present a := by
  rw [set_edge_exact, set_edge_exact]
  by_cases left : a = origin <;> by_cases right : b = target <;> simp [left, right, mirror]

end Edit

/-- The runtime constructs reverse chains using one `cons` per discovery. -/
inductive Chain (edge : Vertex → Vertex → Prop) (origin : Vertex) : Vertex → List Vertex → Prop where
  | first : edge origin target → Chain edge origin target [target, origin]
  | extend : Chain edge origin parent path → edge parent target →
      Chain edge origin target (target :: path)

theorem chain_positive {edge : Vertex → Vertex → Prop} {origin target : Vertex} {path : List Vertex}
    (chain : Chain edge origin target path) : Positive edge origin target := by
  induction chain with
  | first h => exact .first h
  | extend _ h ih => exact .extend ih h

def checkReverse (adj : Adjacency Vertex) (origin : Vertex) : List Vertex → Prop
  | [] => False
  | [vertex] => vertex = origin
  | target :: parent :: rest => target ∈ adj parent ∧ checkReverse adj origin (parent :: rest)

theorem check_nonempty (adj : Adjacency Vertex) (origin head : Vertex) (rest : List Vertex)
    (checked : checkReverse adj origin (head :: rest)) :
    (rest = [] ∧ head = origin) ∨ Chain (GraphWorklist.edge adj) origin head (head :: rest) := by
  induction rest generalizing head with
  | nil => exact .inl ⟨rfl, checked⟩
  | cons parent tail ih =>
    change head ∈ adj parent ∧ checkReverse adj origin (parent :: tail) at checked
    rcases ih parent checked.2 with ⟨empty, start⟩ | path
    · subst tail
      subst parent
      exact .inr (.first checked.1)
    · exact .inr (.extend path checked.1)

theorem check_positive (adj : Adjacency Vertex) (origin target next : Vertex) (rest : List Vertex)
    (checked : checkReverse adj origin (target :: next :: rest)) :
    Chain (GraphWorklist.edge adj) origin target (target :: next :: rest) := by
  rcases check_nonempty adj origin target (next :: rest) checked with ⟨empty, _⟩ | chain
  · contradiction
  · exact chain

theorem check_append (adj : Adjacency Vertex) (origin newOrigin : Vertex) (path : List Vertex)
    (checked : checkReverse adj origin path) (step : origin ∈ adj newOrigin) :
    checkReverse adj newOrigin (path ++ [newOrigin]) := by
  induction path with
  | nil => exact False.elim checked
  | cons head rest ih =>
    cases rest with
    | nil =>
      change head = origin at checked
      subst head
      exact ⟨step, rfl⟩
    | cons next tail =>
      change head ∈ adj next ∧ checkReverse adj origin (next :: tail) at checked
      exact ⟨checked.1, ih checked.2⟩

theorem reverse_chain_checks (adj : Adjacency Vertex) {target origin : Vertex} {path : List Vertex}
    (chain : Chain (fun a b => a ∈ adj b) target origin path) :
    checkReverse adj origin path.reverse := by
  induction chain with
  | first edge => exact ⟨edge, rfl⟩
  | extend _ edge ih =>
    rw [List.reverse_cons]
    exact check_append adj _ _ _ ih edge

section TwoFrontiers

inductive SearchEntry (Vertex : Type) where
  | forward (chain : List Vertex)
  | backward (chain : List Vertex)

/-- The native query uses one hash lookup. Forward and backward chains have
disjoint tags, so a completed scan cannot silently admit an intersection. -/
theorem shared_seen_disjoint (seen : Vertex → Option (SearchEntry Vertex)) (v : Vertex)
    (left : ∃ trail, seen v = some (.forward trail))
    (right : ∃ trail, seen v = some (.backward trail)) : False := by
  obtain ⟨_, l⟩ := left
  obtain ⟨_, r⟩ := right
  rw [l] at r
  simp at r

/-- The two queues are seeded at their roots for distinct endpoint queries. -/
theorem positive_reachable {edge : Vertex → Vertex → Prop} {root target : Vertex}
    (path : Positive edge root target) : RuleGraphClosure.Reachable edge (· = root) target := by
  induction path with
  | first edge => exact .follow (.seed rfl) edge
  | extend _ edge ih => exact .follow ih edge

theorem join_positive {edge : Vertex → Vertex → Prop} {origin meeting target : Vertex}
    (front : Positive edge origin meeting) (suffix : Positive edge meeting target) :
    Positive edge origin target := by
  induction suffix with
  | first edge => exact .extend front edge
  | extend _ edge ih => exact .extend ih edge

/-- A meeting edge supplies positive length, even if one of the stored
chains consists only of a root. The reverse side is read in original order. -/
theorem meeting_positive {edge : Vertex → Vertex → Prop} {origin a b target : Vertex}
    (left : a = origin ∨ Positive edge origin a) (link : edge a b)
    (right : b = target ∨ Positive (fun u v => edge v u) target b) :
    Positive edge origin target := by
  have front : Positive edge origin b := by
    rcases left with same | left
    · subst a
      exact .first link
    · exact .extend left link
  rcases right with same | right
  · subst b
    exact front
  · exact join_positive front (reverse_positive right)

/-- Each full bucket scan preserves its ordinary rooted worklist invariant.
If the seen sets never met and either queue is drained, a path would place
the other root in the drained search's selected set, a contradiction. -/
theorem exhausted_disjoint_miss (edge : Vertex → Vertex → Prop) (origin target : Vertex)
    (left right : RuleGraphClosure.Work Vertex)
    (leftRun : RuleGraphClosure.Run edge (RuleGraphClosure.initial (· = origin)) left)
    (rightRun : RuleGraphClosure.Run (fun u v => edge v u)
      (RuleGraphClosure.initial (· = target)) right)
    (disjoint : ∀ v, left.selected v → right.selected v → False)
    (empty : (∀ v, ¬ left.pending v) ∨ (∀ v, ¬ right.pending v)) :
    ¬ Positive edge origin target := by
  have li := RuleGraphClosure.run_invariant _ _ leftRun (RuleGraphClosure.initial_invariant _ _)
  have ri := RuleGraphClosure.run_invariant _ _ rightRun (RuleGraphClosure.initial_invariant _ _)
  intro found
  rcases empty with le | re
  · have selected := (RuleGraphClosure.completed_exact _ _ _ li le target).mpr
      (positive_reachable found)
    exact disjoint target selected (ri.2.1 target rfl)
  · have selected := (RuleGraphClosure.completed_exact _ _ _ ri re origin).mpr
      (positive_reachable (reverse_positive found))
    exact disjoint origin (li.2.1 origin rfl) selected

/-- A backward stored chain lists successors in original edge direction.
The list argument omits its meeting vertex, which is the head of the front. -/
inductive ForwardTail (adj : Adjacency Vertex) : Vertex → Vertex → List Vertex → Prop where
  | done : ForwardTail adj v v []
  | next : successor ∈ adj current → ForwardTail adj successor target rest →
      ForwardTail adj current target (successor :: rest)

def stitch (front suffix : List Vertex) : List Vertex :=
  suffix.foldl (fun path next => next :: path) front

theorem stitch_checked (adj : Adjacency Vertex) (origin : Vertex)
    {meeting target : Vertex} {suffix front : List Vertex}
    (tail : ForwardTail adj meeting target suffix)
    (valid : checkReverse adj origin (meeting :: front)) :
    ∃ rest, stitch (meeting :: front) suffix = target :: rest ∧
      checkReverse adj origin (target :: rest) := by
  induction tail generalizing front with
  | done => exact ⟨front, rfl, valid⟩
  | next link _ ih =>
    exact ih (front := _ :: front) ⟨link, valid⟩

end TwoFrontiers

structure Witness (Version Vertex : Type) where
  version : Version
  origin : Vertex
  target : Vertex
  reversePath : List Vertex

def Accept {Version : Type} (version : Version) (adj : Adjacency Vertex)
    (witness : Witness Version Vertex) : Prop :=
  witness.version = version ∧
    Chain (GraphWorklist.edge adj) witness.origin witness.target witness.reversePath

theorem witness_sound {Version : Type} (version : Version) (adj : Adjacency Vertex)
    (witness : Witness Version Vertex) (accepted : Accept version adj witness) :
    Positive (GraphWorklist.edge adj) witness.origin witness.target :=
  chain_positive accepted.2

theorem other_version_rejected {Version : Type} {version : Version} (adj : Adjacency Vertex)
    (witness : Witness Version Vertex) (different : witness.version ≠ version) :
    ¬ Accept version adj witness := fun accepted => different accepted.1

inductive Outcome where
  | pending | hit | miss | exhausted | canceled
  deriving DecidableEq

def finish (fuel cost : Nat) (live : Bool) (answer : Outcome) : Outcome :=
  if !live then .canceled else if cost > fuel then .exhausted else answer

theorem failed_not_miss (fuel cost : Nat) (live : Bool) (result : Outcome)
    (failed : live = false ∨ cost > fuel) : finish fuel cost live result ≠ .miss := by
  rcases failed with down | limit
  · simp [finish, down]
  · cases live <;> simp [finish, limit]

end Ascent.BoundReachability
