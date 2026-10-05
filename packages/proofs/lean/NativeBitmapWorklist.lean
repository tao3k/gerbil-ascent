-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import NativeGraphWorklist

/-!
A fixed-length Boolean vector model for the selected bitmap in
`gerbil-ascent-graph-close!`. The pending list keeps the native LIFO order.
This module relates vector-cell updates to the independently proved list
worklist machine. It does not extract Gerbil or justify unchecked raw IDs.
-/

namespace Ascent.NativeBitmapWorklist

structure Work (count : Nat) where
  selected : Vector Bool count
  pending : List (Fin count)

def marked {count : Nat} (work : Work count) (key : Fin count) : Prop :=
  work.selected[key.val] = true

def enqueue {count : Nat} (work : Work count) (target : Fin count) : Work count :=
  if work.selected[target.val] = true then work else
    { selected := work.selected.set target.val true target.isLt
      pending := target :: work.pending }

def scan {count : Nat} : List (Fin count) → Work count → Work count
  | [], work => work
  | target :: rest, work => scan rest (enqueue work target)

def pop {count : Nat} (adj : Fin count → List (Fin count))
    (work : Work count) : Work count :=
  match work.pending with
  | [] => work
  | source :: rest =>
      scan (adj source) { selected := work.selected, pending := rest }

def Corresponds {count : Nat} (bitmap : Work count)
    (list : NativeGraphWorklist.Work (Fin count)) : Prop :=
  (∀ key, marked bitmap key ↔ key ∈ list.selected) ∧
    bitmap.pending = list.pending

theorem marked_set {count : Nat} (selected : Vector Bool count)
    (target key : Fin count) :
    (selected.set target.val true target.isLt)[key.val] = true ↔
      selected[key.val] = true ∨ key = target := by
  rw [Vector.getElem_set target.isLt key.isLt]
  by_cases same : target.val = key.val
  · have eq : key = target := Fin.ext same.symm
    simp [same, eq]
  · have ne : key ≠ target := by
      intro eq
      exact same (congrArg Fin.val eq).symm
    simp [same, ne]

theorem enqueue_corresponds {count : Nat} (bitmap : Work count)
    (list : NativeGraphWorklist.Work (Fin count)) (target : Fin count)
    (rep : Corresponds bitmap list) :
    Corresponds (enqueue bitmap target)
      (NativeGraphWorklist.enqueue list target) := by
  rcases rep with ⟨selectedRep, pendingRep⟩
  by_cases hit : marked bitmap target
  · change bitmap.selected[target.val] = true at hit
    have listHit : target ∈ list.selected := (selectedRep target).mp hit
    simpa [enqueue, NativeGraphWorklist.enqueue, hit, listHit, Corresponds]
      using (show Corresponds bitmap list from ⟨selectedRep, pendingRep⟩)
  · change ¬ bitmap.selected[target.val] = true at hit
    have listMiss : target ∉ list.selected := by
      intro member
      exact hit ((selectedRep target).mpr member)
    simp only [enqueue, hit, ↓reduceIte,
      NativeGraphWorklist.enqueue, listMiss, Corresponds]
    constructor
    · intro key
      change (bitmap.selected.set target.val true target.isLt)[key.val] = true ↔
        key ∈ target :: list.selected
      rw [marked_set, List.mem_cons]
      have repKey : bitmap.selected[key.val] = true ↔ key ∈ list.selected :=
        selectedRep key
      simp [repKey, or_comm]
    · simp [pendingRep]

theorem scan_corresponds {count : Nat} (targets : List (Fin count))
    (bitmap : Work count) (list : NativeGraphWorklist.Work (Fin count))
    (rep : Corresponds bitmap list) :
    Corresponds (scan targets bitmap)
      (NativeGraphWorklist.scan targets list) := by
  induction targets generalizing bitmap list with
  | nil => exact rep
  | cons target rest ih =>
      exact ih (enqueue bitmap target)
        (NativeGraphWorklist.enqueue list target)
        (enqueue_corresponds bitmap list target rep)

theorem pop_corresponds {count : Nat}
    (adj : Fin count → List (Fin count))
    (bitmap : Work count) (list : NativeGraphWorklist.Work (Fin count))
    (rep : Corresponds bitmap list) :
    Corresponds (pop adj bitmap) (NativeGraphWorklist.pop adj list) := by
  rcases rep with ⟨selectedRep, pendingRep⟩
  cases entries : bitmap.pending with
  | nil =>
      have listEmpty : list.pending = [] := by simpa [entries] using pendingRep.symm
      simpa [pop, entries, NativeGraphWorklist.pop, listEmpty, Corresponds]
        using (show Corresponds bitmap list from ⟨selectedRep, pendingRep⟩)
  | cons source rest =>
      have listEntries : list.pending = source :: rest := by
        simpa [entries] using pendingRep.symm
      have base : Corresponds
          ({ selected := bitmap.selected, pending := rest } : Work count)
          ({ selected := list.selected, pending := rest } :
            NativeGraphWorklist.Work (Fin count)) :=
        ⟨selectedRep, rfl⟩
      simpa [pop, entries, NativeGraphWorklist.pop, listEntries]
        using scan_corresponds (adj source)
          { selected := bitmap.selected, pending := rest }
          { selected := list.selected, pending := rest } base

def initial {count : Nat} (seeds : List (Fin count)) : Work count :=
  { selected := Vector.ofFn (fun key => decide (key ∈ seeds))
    pending := seeds }

theorem initial_corresponds {count : Nat} (seeds : List (Fin count)) :
    Corresponds (initial seeds) (NativeGraphWorklist.initial seeds) := by
  constructor
  · intro key
    simp [initial, marked, NativeGraphWorklist.initial]
  · rfl

def runFuel {count : Nat} (adj : Fin count → List (Fin count)) :
    Nat → Work count → Work count
  | 0, work => work
  | _ + 1, ⟨selected, []⟩ => ⟨selected, []⟩
  | fuel + 1, ⟨selected, source :: rest⟩ =>
      runFuel adj fuel (pop adj ⟨selected, source :: rest⟩)

theorem runFuel_corresponds {count : Nat}
    (adj : Fin count → List (Fin count)) (fuel : Nat)
    (bitmap : Work count) (list : NativeGraphWorklist.Work (Fin count))
    (rep : Corresponds bitmap list) :
    Corresponds (runFuel adj fuel bitmap)
      (NativeGraphWorklist.runFuel adj fuel list) := by
  induction fuel generalizing bitmap list with
  | zero => exact rep
  | succ fuel ih =>
      cases bitmap with
      | mk selected pending =>
          cases list with
          | mk listSelected listPending =>
              cases pending with
              | nil =>
                  have listEmpty : listPending = [] := rep.2.symm
                  subst listPending
                  simpa [runFuel, NativeGraphWorklist.runFuel] using rep
              | cons source rest =>
                  have listEntries : listPending = source :: rest := rep.2.symm
                  subst listPending
                  simpa [runFuel, NativeGraphWorklist.runFuel] using ih
                    (pop adj ⟨selected, source :: rest⟩)
                    (NativeGraphWorklist.pop adj ⟨listSelected, source :: rest⟩)
                    (pop_corresponds adj ⟨selected, source :: rest⟩
                      ⟨listSelected, source :: rest⟩ rep)

/-- The fixed-length Boolean vector and native-order pending list produce
exactly the read closure of admitted rule plans under typed in-range IDs. -/
theorem runFuel_compiled_exact (count : Nat)
    (plans : List (RuleGraphClosure.Rule (Fin count)))
    (seeds : List (Fin count)) (noDup : seeds.Nodup)
    (key : Fin count) :
    marked (runFuel (RuleGraphClosure.ruleSuccessors plans)
      (count + 1) (initial seeds)) key ↔
      RuleGraphClosure.Reachable (RuleGraphClosure.ReadsInto plans)
        (fun k => k ∈ seeds) key := by
  have rep := runFuel_corresponds (RuleGraphClosure.ruleSuccessors plans)
    (count + 1) (initial seeds) (NativeGraphWorklist.initial seeds)
    (initial_corresponds seeds)
  exact (rep.1 key).trans
    (NativeGraphWorklist.runFuel_compiled_exact count plans seeds noDup key)

theorem runFuel_compiled_complete (count : Nat)
    (plans : List (RuleGraphClosure.Rule (Fin count)))
    (seeds : List (Fin count)) (noDup : seeds.Nodup) :
    (runFuel (RuleGraphClosure.ruleSuccessors plans)
      (count + 1) (initial seeds)).pending = [] := by
  have rep := runFuel_corresponds (RuleGraphClosure.ruleSuccessors plans)
    (count + 1) (initial seeds) (NativeGraphWorklist.initial seeds)
    (initial_corresponds seeds)
  rw [rep.2]
  exact NativeGraphWorklist.runFuel_complete count
    (RuleGraphClosure.ruleSuccessors plans)
    (NativeGraphWorklist.initial seeds)
    (NativeGraphWorklist.initial_wellformed seeds noDup)

/-- The vector model supplies the affected-set closure required by the
fixed-point frame theorem, with no assumed completion of its queue. -/
theorem runFuel_compiled_closed (count : Nat)
    (plans : List (RuleGraphClosure.Rule (Fin count)))
    (seeds : List (Fin count)) (noDup : seeds.Nodup) :
    DependencyInvalidation.Closed (RuleGraphClosure.ReadsInto plans)
      (fun key => marked (runFuel (RuleGraphClosure.ruleSuccessors plans)
        (count + 1) (initial seeds)) key) := by
  intro source target read sourceMarked
  have sourceReach := (runFuel_compiled_exact count plans seeds noDup source).mp
    sourceMarked
  exact (runFuel_compiled_exact count plans seeds noDup target).mpr
    (RuleGraphClosure.Reachable.follow sourceReach read)

end Ascent.NativeBitmapWorklist
