-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

import Std

/-!
After the missing rectangles are installed, the root relation contains the
new closure. `cycle` selects precisely the roots to identify. The winner's
forward and reverse rows then locate every surviving row that loses a key.
The model concerns root adjacency and ordered roster retirement. The storage
invariant for the mutable forward/reverse tables is a Scheme obligation.
-/

namespace Ascent.UfMergeFootprint

/-! The directory retains retired endpoint identities. Adjacency queries
resolve those identities before reading a live owner's row. -/
theorem retired_adjacency_unobserved {Key Owner Row : Type}
    (resolve : Key → Owner) (before after : Owner → Row)
    (sameLive : ∀ key, after (resolve key) = before (resolve key)) :
    (fun key => after (resolve key)) = (fun key => before (resolve key)) :=
  funext sameLive

/-- In a whole-group collapse of singleton roots the new cut is a square.
Each old row contains the implicit diagonal plus its stored forward degree.
Adding its missing cells to those old cells recovers the full row width. -/
theorem singleton_collapse_counts (width : Nat) (degrees : List Nat)
    (valid : ∀ degree ∈ degrees, degree + 1 ≤ width) :
    (degrees.map (fun degree => width - (degree + 1))).sum +
      (degrees.map (fun degree => degree + 1)).sum = degrees.length * width := by
  induction degrees with
  | nil => simp
  | cons degree rest ih =>
    have bound := valid degree (by simp)
    have tail := ih (fun d present => valid d (by simp [present]))
    simp only [List.map_cons, List.sum_cons, List.length_cons, Nat.succ_mul]
    omega

theorem singleton_collapse_mass (width : Nat) (degrees : List Nat)
    (complete : degrees.length = width)
    (valid : ∀ degree ∈ degrees, degree + 1 ≤ width) :
    (degrees.map (fun degree => width - (degree + 1))).sum =
      width * width - (degrees.map (fun degree => degree + 1)).sum := by
  have mass := singleton_collapse_counts width degrees valid
  rw [complete] at mass
  omega

variable {Root : Type} (edge : Root → Root → Prop) (cycle : Root → Prop)

def Losing (winner root : Root) : Prop := cycle root ∧ root ≠ winner

def affectedForward (winner owner : Root) : Prop :=
  owner = winner ∨ edge owner winner

def affectedReverse (winner owner : Root) : Prop :=
  owner = winner ∨ edge winner owner

theorem forward_retirement (winner owner key : Root)
    (closed : ∀ a b c, a ≠ c → edge a b → edge b c → edge a c)
    (toWinner : ∀ x, Losing cycle winner x → edge x winner) :
    (edge owner key ∧ ¬ (affectedForward edge winner owner ∧ Losing cycle winner key)) ↔
      edge owner key ∧ ¬ Losing cycle winner key := by
  constructor
  · rintro ⟨present, kept⟩
    refine ⟨present, fun lost => kept ⟨?_, lost⟩⟩
    by_cases same : owner = winner
    · exact Or.inl same
    · exact Or.inr (closed _ _ _ same present (toWinner key lost))
  · rintro ⟨present, kept⟩
    exact ⟨present, fun retired => kept retired.2⟩

theorem reverse_retirement (winner owner key : Root)
    (closed : ∀ a b c, a ≠ c → edge a b → edge b c → edge a c)
    (fromWinner : ∀ x, Losing cycle winner x → edge winner x) :
    (edge key owner ∧ ¬ (affectedReverse edge winner owner ∧ Losing cycle winner key)) ↔
      edge key owner ∧ ¬ Losing cycle winner key := by
  constructor
  · rintro ⟨present, kept⟩
    refine ⟨present, fun lost => kept ⟨?_, lost⟩⟩
    by_cases same : owner = winner
    · exact Or.inl same
    · exact Or.inr (closed _ _ _ (Ne.symm same) (fromWinner key lost) present)
  · rintro ⟨present, kept⟩
    exact ⟨present, fun retired => kept retired.2⟩

theorem external_forward_owner (winner owner : Root)
    (closed : ∀ a b c, a ≠ c → edge a b → edge b c → edge a c)
    (toWinner : ∀ x, Losing cycle winner x → edge x winner)
    (fromWinner : ∀ x, Losing cycle winner x → edge winner x)
    (loser : ∃ key, Losing cycle winner key)
    (external : ¬ cycle owner) (different : owner ≠ winner) :
    (∃ key, Losing cycle winner key ∧ edge owner key) ↔ edge owner winner := by
  constructor
  · rintro ⟨key, lost, present⟩
    exact closed _ _ _ different present (toWinner key lost)
  · intro present
    obtain ⟨key, lost⟩ := loser
    refine ⟨key, lost, closed _ _ _ ?_ present (fromWinner key lost)⟩
    intro same
    exact external (same.symm ▸ lost.1)

theorem external_reverse_owner (winner owner : Root)
    (closed : ∀ a b c, a ≠ c → edge a b → edge b c → edge a c)
    (toWinner : ∀ x, Losing cycle winner x → edge x winner)
    (fromWinner : ∀ x, Losing cycle winner x → edge winner x)
    (loser : ∃ key, Losing cycle winner key)
    (external : ¬ cycle owner) (different : owner ≠ winner) :
    (∃ key, Losing cycle winner key ∧ edge key owner) ↔ edge winner owner := by
  exact external_forward_owner (fun a b => edge b a) cycle winner owner
    (fun a b c different ab bc => closed c b a (Ne.symm different) bc ab)
    fromWinner toWinner loser external different

variable (order : Root → Nat) (retire : Root → Bool)

/-- Roots are newest first. Stop when the remaining IDs precede every loser. -/
def prune (oldest : Nat) : List Root → List Root
  | [] => []
  | x :: rest =>
    if order x < oldest then x :: rest
    else if retire x then prune oldest rest else x :: prune oldest rest

theorem prune_eq_filter (oldest : Nat) (roots : List Root)
    (ordered : roots.Pairwise (fun a b => order b ≤ order a))
    (bound : ∀ x, retire x = true → oldest ≤ order x) :
    prune order retire oldest roots = roots.filter (fun x => !retire x) := by
  induction roots with
  | nil => rfl
  | cons head tail ih =>
    have ⟨before, sorted⟩ := List.pairwise_cons.mp ordered
    rw [prune]
    split
    · rename_i older
      apply Eq.symm
      apply List.filter_eq_self.mpr
      intro x member
      have below : order x < oldest := by
        rcases List.mem_cons.mp member with rfl | inTail
        · exact older
        · exact Nat.lt_of_le_of_lt (before x inTail) older
      cases retired : retire x
      · rfl
      · exact (Nat.not_le_of_gt below (bound x retired)).elim
    · cases retired : retire head <;> simp [retired, ih sorted]

def pruneLoop (oldest : Nat) (kept : List Root) : List Root → List Root
  | [] => kept.reverse
  | x :: rest =>
    if order x < oldest then kept.reverse ++ x :: rest
    else pruneLoop oldest (if retire x then kept else x :: kept) rest

theorem pruneLoop_eq_prune (oldest : Nat) (kept roots : List Root) :
    pruneLoop order retire oldest kept roots = kept.reverse ++ prune order retire oldest roots := by
  induction roots generalizing kept with
  | nil => simp [pruneLoop, prune]
  | cons head tail ih =>
    simp only [pruneLoop, prune]
    split
    · simp_all
    · rw [ih]
      cases retire head <;> simp [List.reverse_cons, List.append_assoc]

/-- The two winner rows are opened once. Each external bucket is opened once
per direction. Roster, sparse keys and packed words have their own charges. -/
def ownerVisits (predecessors successors : Nat) : Nat := 2 + predecessors + successors

theorem ownerVisits_lt_two_sweeps (predecessors successors unrelated : Nat)
    (nonempty : 0 < predecessors + successors + unrelated) :
    ownerVisits predecessors successors < 2 * (1 + predecessors + successors + unrelated) := by
  unfold ownerVisits
  omega

/-- A packed axis and a roster projection agree when they select the same
live birth IDs in the same direction. Strict order rules out duplicates,
including a duplicated implicit diagonal. -/
theorem ordered_axis_exact (roster packed : List Nat)
    (rosterOrder : roster.Pairwise (· < ·)) (packedOrder : packed.Pairwise (· < ·))
    (sameMembers : ∀ id, id ∈ roster ↔ id ∈ packed) : roster = packed := by
  have permutation : roster.Perm packed :=
    (List.perm_ext_iff_of_nodup
      (rosterOrder.imp Nat.ne_of_lt) (packedOrder.imp Nat.ne_of_lt)).2 sameMembers
  exact List.Perm.eq_of_pairwise (le := (· ≤ ·))
    (fun a b _ _ ab ba => Nat.le_antisymm ab ba)
    (rosterOrder.imp Nat.le_of_lt) (packedOrder.imp Nat.le_of_lt) permutation

theorem ordered_axis_both_directions (roster packed : List Nat)
    (rosterOrder : roster.Pairwise (· < ·)) (packedOrder : packed.Pairwise (· < ·))
    (sameMembers : ∀ id, id ∈ roster ↔ id ∈ packed) :
    roster = packed ∧ roster.reverse = packed.reverse := by
  have exact := ordered_axis_exact roster packed rosterOrder packedOrder sameMembers
  exact ⟨exact, congrArg List.reverse exact⟩

/-- The guarded packed traversal opens each backing word once and performs
one registry read per set bit. Self insertion takes one visit. This counts
visits only, apart from constructing the output list in the chosen direction. -/
theorem packed_axis_visit_bound (words degree : Nat) (fits : words ≤ degree) :
    words + degree + 1 ≤ 2 * degree + 1 := by omega

theorem packed_axis_skips_unrelated_roots (words degree population : Nat)
    (fits : words ≤ degree) (selective : 2 * degree + 1 < population) :
    words + degree + 1 < population :=
  Nat.lt_of_le_of_lt (packed_axis_visit_bound words degree fits) selective

end Ascent.UfMergeFootprint
