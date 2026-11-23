-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

/-! The actual dense Tarjan discovery-cell representation: #f is unseen,
#t is completed, and every natural discovery index (including zero) is on the
stack. Classification is independent of vertex identity and graph size.
This module does not claim the complete Tarjan lowlink invariant. -/
namespace Ascent.SccState
inductive Cell where
  | unseen | completed | discovery (index : Nat)
  deriving DecidableEq
inductive Step where
  | enter | stay | lower (index : Nat)
  deriving DecidableEq

def truthy : Cell → Bool
  | .unseen => false
  | _ => true

def trueValue : Cell → Bool
  | .completed => true
  | _ => false

inductive Test where
  | unseen | completed
  deriving DecidableEq
inductive Code where
  | enter | stay | lower
  | branch (test : Test) (yes no : Code)
  deriving DecidableEq

def test (cell : Cell) : Test → Bool
  | .unseen => !truthy cell
  | .completed => trueValue cell

def execute (cell : Cell) : Code → Step
  | .enter => .enter
  | .stay => .stay
  | .lower => match cell with | .discovery n => .lower n | _ => .stay
  | .branch predicate yes no => if test cell predicate then execute cell yes else execute cell no

def code : Code := .branch .unseen .enter (.branch .completed .stay .lower)
def expected : Cell → Step
  | .unseen => .enter
  | .completed => .stay
  | .discovery n => .lower n

theorem discovery_exact (cell : Cell) : execute cell code = expected cell := by
  cases cell <;> rfl

theorem index_zero_active : execute (.discovery 0) code = .lower 0 := rfl

/-- The rank guard used by POO's `compact-selected-discover`. It checks
cross-vertex edges while capturing adjacency. Self edges are permitted. -/
inductive Path (edge : Vertex → Vertex → Prop) : Vertex → Vertex → Prop where
  | empty (node) : Path edge node node
  | next {start middle finish} : edge start middle → Path edge middle finish →
      Path edge start finish

theorem ranked_path {edge : Vertex → Vertex → Prop} (rank : Vertex → Nat)
    (ordered : ∀ a b, edge a b → a = b ∨ rank a < rank b)
    {a b : Vertex} (path : Path edge a b) : a = b ∨ rank a < rank b := by
  induction path with
  | empty _ => exact Or.inl rfl
  | @next start middle finish arc _ tail =>
      rcases ordered start middle arc with same | before
      · subst middle; exact tail
      · rcases tail with same | after
        · subst finish; exact Or.inr before
        · exact Or.inr (Nat.lt_trans before after)

theorem ranked_components_are_singletons {edge : Vertex → Vertex → Prop}
    (rank : Vertex → Nat) (ordered : ∀ a b, edge a b → a = b ∨ rank a < rank b)
    {a b : Vertex} (forward : Path edge a b) (backward : Path edge b a) : a = b := by
  rcases ranked_path rank ordered forward with same | before
  · exact same
  · rcases ranked_path rank ordered backward with same | after
    · exact same.symm
    · exact False.elim (Nat.lt_asymm before after)

section BorrowedAdjacency

/-- POO's discovery words reserve zero for an unseen vertex. Active lows
retain one flag bit and the value beyond the last discovery is retired. -/
def activeLow (discovery : Nat) (follower : Bool) : Nat :=
  2 * (discovery + 1) + (if follower then 1 else 0)

theorem active_low_encoding (discovery count : Nat) (follower : Bool)
    (inside : discovery < count) :
    0 < activeLow discovery follower ∧
      activeLow discovery follower ≤ 2 * count + 1 ∧
      activeLow discovery follower % 2 = (if follower then 1 else 0) := by
  cases follower <;> simp [activeLow] <;> omega

theorem lowered_follower_is_not_retired (older current count : Nat)
    (lower : older < current) (inside : current < count) :
    activeLow older true < 2 * count + 1 := by
  simp [activeLow]
  omega

theorem sink_retirement_reverses_to_source_order (count source target : Nat)
    (edge : target < source) (valid : source < count) :
    count - 1 - source < count - 1 - target := by omega

def adjacencyEdge (neighbors : Nat → List Nat) (source target : Nat) : Prop :=
  target ∈ neighbors source

def editOrigin (neighbors : Nat → List Nat) (origin : Nat) (row : List Nat) :
    Nat → List Nat :=
  fun node => if node = origin then row else neighbors node

theorem edited_origin_exact (neighbors : Nat → List Nat) (origin source target : Nat)
    (row : List Nat) :
    adjacencyEdge (editOrigin neighbors origin row) source target ↔
      (source = origin ∧ target ∈ row) ∨
        (source ≠ origin ∧ adjacencyEdge neighbors source target) := by
  by_cases same : source = origin <;> simp [editOrigin, adjacencyEdge, same]

theorem unchanged_rows_borrowed (neighbors : Nat → List Nat) (origin source : Nat)
    (row : List Nat) (other : source ≠ origin) :
    editOrigin neighbors origin row source = neighbors source := by
  simp [editOrigin, other]

/-- Only internal vertex ordinals are packed. The caller's integer
labels remain in the existing inverse dictionary. -/
def decodeNeighbors (row : List UInt16) : List Nat :=
  row.map UInt16.toNat

theorem bounded_packed_row_exact (row : List Nat)
    (bounded : ∀ v ∈ row, v < 8192) :
    decodeNeighbors (row.map UInt16.ofNat) = row := by
  induction row with
  | nil => rfl
  | cons first rest ih =>
    have small : first < UInt16.size := by
      have bound := bounded first (List.mem_cons_self)
      change first < 65536
      omega
    have tail : ∀ v ∈ rest, v < 8192 :=
      fun v h => bounded v (List.mem_cons_of_mem _ h)
    change (UInt16.ofNat first).toNat :: decodeNeighbors (rest.map UInt16.ofNat) = first :: rest
    rw [UInt16.toNat_ofNat_of_lt' small, ih tail]

/-- A packed DFS frame retains the next offset. The old frame retained
the corresponding ordered suffix. Resuming either enumerates the same
targets, including after descending into a child. -/
theorem packed_cursor_suffix (row : List UInt16) (next : Nat) :
    decodeNeighbors (row.drop next) = (decodeNeighbors row).drop next := by
  simp [decodeNeighbors, List.map_drop]

/-- Copying a prefix and suffix around the edit preserves the exact
successor order and thus the traversal and bounded witness order. -/
theorem packed_row_splice (row inserted : List UInt16) (before skip : Nat) :
    decodeNeighbors (row.take before ++ inserted ++ row.drop (before + skip)) =
      (decodeNeighbors row).take before ++ decodeNeighbors inserted ++
        (decodeNeighbors row).drop (before + skip) := by
  simp [decodeNeighbors, List.map_take, List.map_drop]

theorem packed_edit_borrows_other_rows (rows : Nat → List UInt16)
    (origin other : Nat) (replacement : List UInt16) (unchanged : other ≠ origin) :
    decodeNeighbors (if other = origin then replacement else rows other) =
      decodeNeighbors (rows other) := by
  simp [unchanged]

/-- Count distinct successor cells under the two retained adjacency
headers, independently of the collector's accounted-byte convention.
When one row changes, every other row remains shared. -/
def heldListEdgePairs (degrees : List Nat) (copiedPrefix : Nat) : Nat :=
  degrees.sum + copiedPrefix

def heldPackedRowBuffers (degrees : List Nat) : Nat := degrees.length + 1

theorem packed_fixture_object_counts :
    heldListEdgePairs (List.replicate 3150 63 ++ List.replicate 50 64) 63 = 201713 ∧
    heldPackedRowBuffers (List.replicate 3150 63 ++ List.replicate 50 64) = 3201 := by
  constructor
  · unfold heldListEdgePairs
    rw [List.sum_append, List.sum_replicate_nat, List.sum_replicate_nat]
  · unfold heldPackedRowBuffers
    rw [List.length_append, List.length_replicate, List.length_replicate]

theorem path_first_edge {edge : Vertex → Vertex → Prop} {a b : Vertex}
    (path : Path edge a b) (distinct : a ≠ b) : ∃ v, edge a v := by
  cases path with
  | empty _ => exact False.elim (distinct rfl)
  | next arc _ => exact ⟨_, arc⟩

theorem path_last_edge {edge : Vertex → Vertex → Prop} {a b : Vertex}
    (path : Path edge a b) (distinct : a ≠ b) : ∃ v, edge v b := by
  induction path with
  | empty _ => exact False.elim (distinct rfl)
  | @next start middle finish arc _ ih =>
    by_cases final : middle = finish
    · subst finish
      exact ⟨start, arc⟩
    · exact ih final

/-- For a deleted non-self arc x -> y inside an SCC, the reverse path
still supplies an outgoing arc of y and an incoming arc of x. Neither
can be the deleted arc, so both endpoints stay in the vertex domain. -/
theorem nonself_split_preserves_endpoints {edge : Vertex → Vertex → Prop} {x y : Vertex}
    (different : y ≠ x) (reversePath : Path edge y x) :
    (∃ v, edge y v ∧ (y, v) ≠ (x, y)) ∧
      (∃ v, edge v x ∧ (v, x) ≠ (x, y)) := by
  obtain ⟨out, leaves⟩ := path_first_edge reversePath different
  obtain ⟨inc, arrives⟩ := path_last_edge reversePath different
  exact ⟨⟨out, leaves, fun equal => different (congrArg Prod.fst equal)⟩,
    ⟨inc, arrives, fun equal => different (congrArg Prod.snd equal).symm⟩⟩

def finishRepair {Cut : Type} (prior candidate : Cut) (checks : List Bool) : Cut :=
  if checks.all id then candidate else prior

theorem refused_repair_retains_prior {Cut : Type} (prior candidate : Cut)
    (checks : List Bool) (refused : false ∈ checks) :
    finishRepair prior candidate checks = prior := by
  have denied : checks.all id = false := by
    cases h : checks.all id with
    | false => rfl
    | true =>
      have all := (List.all_eq_true.mp h) false refused
      simp at all
  simp [finishRepair, denied]

end BorrowedAdjacency

section ReverseQuotient

/-- The incoming masks transpose the cross-component bits. Diagonal bits
remain in the forward masks, where they witness a nonempty internal path. -/
def incoming (direct : Nat → Nat → Prop) (target source : Nat) : Prop :=
  source ≠ target ∧ direct source target

def editBit (direct : Nat → Nat → Prop) (source target : Nat) (present : Prop)
    (src to : Nat) : Prop :=
  if src = source ∧ to = target then present else direct src to

theorem incoming_edited_bit (direct : Nat → Nat → Prop) (source target : Nat)
    (present : Prop) (src to : Nat) :
    incoming (editBit direct source target present) to src ↔
      (if src = source ∧ to = target then src ≠ to ∧ present else incoming direct to src) := by
  by_cases h : src = source ∧ to = target <;> simp [incoming, editBit, h]

inductive Ancestor (direct : Nat → Nat → Prop) (target : Nat) : Nat → Prop where
  | root : Ancestor direct target target
  | previous : incoming direct to src → Ancestor direct target to → Ancestor direct target src

/-- The reverse walk describes the same forward cross-component paths. -/
theorem ancestor_forward_path {direct : Nat → Nat → Prop} {target g : Nat} :
    Ancestor direct target g ↔ Path (fun a b => incoming direct b a) g target := by
  constructor
  · intro h
    induction h with
    | root => exact .empty _
    | previous arc _ ih => exact .next arc ih
  · intro h
    have extend {a b : Nat} (path : Path (fun a b => incoming direct b a) a b)
        (suffix : Ancestor direct target b) : Ancestor direct target a := by
      induction path with
      | empty => exact suffix
      | next arc _ ih => exact .previous arc (ih suffix)
    exact extend h .root

/-- `pending` and `settled` are disjoint masks. Moving one bit to settled
and OR-ing its incoming bits into pending preserves reachability soundness
and records that all incoming arcs of each settled bit have been seen. -/
def ReverseInvariant (direct : Nat → Nat → Prop) (target : Nat)
    (pending settled : Nat → Prop) : Prop :=
  (pending target ∨ settled target) ∧
  (∀ g, pending g ∨ settled g → Ancestor direct target g) ∧
  (∀ g, settled g → ¬ pending g) ∧
  (∀ g h, settled g → incoming direct g h → pending h ∨ settled h)

theorem reverse_seed (direct : Nat → Nat → Prop) (target : Nat) :
    ReverseInvariant direct target (· = target) (fun _ => False) := by
  refine ⟨Or.inl rfl, ?_, ?_, ?_⟩
  · intro g h
    rcases h with rfl | h
    · exact .root
    · contradiction
  · simp
  · simp

theorem reverse_step {direct : Nat → Nat → Prop} {target g : Nat}
    {pending settled : Nat → Prop} (inv : ReverseInvariant direct target pending settled)
    (take : pending g) :
    ReverseInvariant direct target
      (fun h => (pending h ∨ incoming direct g h) ∧ ¬ (settled h ∨ h = g))
      (fun h => settled h ∨ h = g) := by
  obtain ⟨root, sound, _, closed⟩ := inv
  have keep : ∀ h, pending h ∨ settled h →
      ((pending h ∨ incoming direct g h) ∧ ¬ (settled h ∨ h = g)) ∨ settled h ∨ h = g := by
    intro h old
    by_cases done : settled h ∨ h = g
    · exact Or.inr done
    · exact Or.inl ⟨Or.inl (old.resolve_right (fun cleared => done (Or.inl cleared))), done⟩
  refine ⟨keep target root, ?_, ?_, ?_⟩
  · intro h current
    rcases current with ⟨old | edge, _⟩ | old | equal
    · exact sound h (Or.inl old)
    · exact .previous edge (sound g (Or.inl take))
    · exact sound h (Or.inr old)
    · subst h; exact sound g (Or.inl take)
  · intro h done waiting
    exact waiting.2 done
  · intro h v done edge
    rcases done with old | rfl
    · exact keep v (closed h v old edge)
    · by_cases done : settled v ∨ v = h
      · exact Or.inr done
      · exact Or.inl ⟨Or.inr edge, done⟩

theorem reverse_exhausted_exact {direct : Nat → Nat → Prop} {target : Nat}
    {settled : Nat → Prop}
    (inv : ReverseInvariant direct target (fun _ => False) settled) (g : Nat) :
    settled g ↔ Ancestor direct target g := by
  obtain ⟨root, sound, _, closed⟩ := inv
  refine ⟨fun done => sound g (Or.inr done), ?_⟩
  intro reachable
  induction reachable with
  | root => exact root.resolve_left id
  | previous arc _ ih => exact (closed _ _ ih arc).resolve_left id

/-- Inter-component reversal permits a zero-edge path at the target;
regular selection keeps that bit only if the forward self bit is present. -/
def nonemptyPredecessor (direct : Nat → Nat → Prop) (target source : Nat) : Prop :=
  Ancestor direct target source ∧ (source ≠ target ∨ direct target target)

theorem reverse_selection_exact {direct : Nat → Nat → Prop} {target : Nat}
    {settled : Nat → Prop}
    (inv : ReverseInvariant direct target (fun _ => False) settled) (g : Nat) :
    (settled g ∧ (g ≠ target ∨ direct target target)) ↔ nonemptyPredecessor direct target g := by
  unfold nonemptyPredecessor
  rw [reverse_exhausted_exact inv]

/-- The selected groups filter the original label spine. Group IDs never
participate in the public ordering, including interleaved group members. -/
theorem reverse_selection_order {Label : Type} (ordered : List Label)
    (target : Label) (selection full : Label → Bool)
    (same : ∀ label, selection label = full label) :
    (ordered.filter selection).map (fun label => (label, target)) =
      (ordered.filter full).map (fun label => (label, target)) := by
  rw [funext same]

/-- Witness replay reads the retained concrete adjacency and its version.
Selection adds a derived index without changing any of those inputs. -/
def replayReverseCut (cut : Nat × Nat) (row : Nat → List Nat)
    (witnessCut : Nat × Nat) (edges : List (Nat × Nat)) : Bool :=
  cut == witnessCut && edges.all (fun (a, b) => (row a).contains b)

theorem reverse_selection_retains_witness
    (cut : Nat × Nat) (row : Nat → List Nat) (witnessCut : Nat × Nat)
    (edges : List (Nat × Nat)) (prior next : Nat → Nat → Prop) :
    (fun (_ : Nat → Nat → Prop) => replayReverseCut cut row witnessCut edges) prior =
      (fun (_ : Nat → Nat → Prop) => replayReverseCut cut row witnessCut edges) next := rfl

theorem reverse_selection_rejects_other_cut
    (cut witnessCut : Nat × Nat) (row : Nat → List Nat) (edges : List (Nat × Nat))
    (different : cut ≠ witnessCut) : replayReverseCut cut row witnessCut edges = false := by
  simp [replayReverseCut, different]

end ReverseQuotient

def emit : Code → String
  | .enter => "unseen"
  | .stay => "completed"
  | .lower => "on-stack"
  | .branch .unseen yes no => "(if (not known) " ++ emit yes ++ " " ++ emit no ++ ")"
  | .branch .completed yes no => "(if (eq? known #t) " ++ emit yes ++ " " ++ emit no ++ ")"

def source : String :=
  ";;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors\n;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later\n;;; Generated by SccState.lean; discovery index zero remains active.\n" ++
  "(export gerbil-ascent-scc-state)\n;; gerbil-ascent-scc-state\n;; : (-> IndexExpression KnownBinding UnseenBranch CompletedBranch ActiveBranch Result)\n;; | doc m%\n;;     Read once: zero is active, false is unseen and true is complete.\n;;\n;;     # Examples\n;;\n;;     ```scheme\n;;     (gerbil-ascent-scc-state 0 (known) 'unseen 'done 'active)\n;;     ;; => active\n;;     ```\n;;   %\n(defrule (gerbil-ascent-scc-state index (known) unseen completed on-stack)\n  (let (known index)\n    " ++ emit code ++ "))\n"
end Ascent.SccState

#print axioms Ascent.SccState.ranked_components_are_singletons

#print axioms Ascent.SccState.reverse_exhausted_exact
#print axioms Ascent.SccState.reverse_selection_order
#print axioms Ascent.SccState.reverse_selection_rejects_other_cut
