/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
Initial ground rule coverage remains sufficient under positive source subcuts.
Native grounding, scalar primitives and token decoding remain obligations.
-/
import ComponentClosure
import SourceOccurrences
namespace Ascent.StableSourceSupport
open ComponentClosure
variable {Fact : Type}
theorem source_subset (rules : List (Rule Fact)) (initial current : Database Fact)
    (subset : ∀ fact, current fact → initial fact) (fact : Fact)
    (derived : Derivable rules current fact) : Derivable rules initial fact := by
  induction derived with
  | seed present => exact Derivable.seed (subset _ present)
  | fire rule member body ih => exact Derivable.fire rule member ih
/-- An initial ground graph need only cover rules whose premises are initially
founded. Every future subcut derivation uses one of those same instances. -/
theorem initial_coverage (rules graph : List (Rule Fact)) (initial current : Database Fact)
    (subset : ∀ fact, current fact → initial fact)
    (coverage : ∀ rule ∈ rules,
      (∀ premise ∈ rule.body, Derivable rules initial premise) → rule ∈ graph)
    (sound : ∀ rule ∈ graph, rule ∈ rules) (fact : Fact) :
    Derivable graph current fact ↔ Derivable rules current fact := by
  constructor
  · intro derived
    induction derived with
    | seed present => exact Derivable.seed present
    | fire rule member body ih => exact Derivable.fire rule (sound rule member) ih
  · intro derived
    induction derived with
    | seed present => exact Derivable.seed present
    | fire rule member body ih =>
      apply Derivable.fire rule (coverage rule member (fun premise read =>
        source_subset rules initial current subset premise (body premise read)))
      exact ih
/-- Filtering occurrences retains their stable tokens; values can coincide. -/
def keep {Row Token : Type} [DecidableEq Token]
    (entries : List (Row × Token)) (removed : List Token) : List (Row × Token) :=
  entries.filter (fun entry => decide (entry.2 ∉ removed))
theorem retained_token {Row Token : Type} [DecidableEq Token]
    (entries : List (Row × Token)) (removed : List Token) (entry : Row × Token) :
    entry ∈ keep entries removed ↔ entry ∈ entries ∧ entry.2 ∉ removed := by
  simp [keep]
theorem cumulative_cuts {Row Token : Type} [DecidableEq Token]
    (entries : List (Row × Token)) (first second : List Token) :
    keep (keep entries first) second = keep entries (first ++ second) := by
  simp only [keep, List.filter_filter]
  congr 1
  funext entry
  simp [List.mem_append, Bool.and_comm]

/-- A representation restriction at the current founded closure. This is a
semantic rule filter; native row IDs and the mutable loop are separate. -/
noncomputable def restrict (rules : List (Rule Fact)) (live : Database Fact) : List (Rule Fact) :=
  by
    classical
    exact rules.filter (fun rule => decide (live rule.head ∧ Holds live rule.body))

/-- Once sources only decrease, rules with currently unfounded heads or
premises cannot contribute to any later derivation. -/
theorem restriction_preserves (rules : List (Rule Fact)) (current future live : Database Fact)
    (exactLive : ∀ fact, live fact ↔ Derivable rules current fact)
    (subset : ∀ fact, future fact → current fact) (fact : Fact) :
    Derivable (restrict rules live) future fact ↔ Derivable rules future fact := by
  classical
  apply initial_coverage rules (restrict rules live) current future subset
  · intro rule member body
    simp only [restrict, List.mem_filter, decide_eq_true_eq]
    exact ⟨member, (exactLive rule.head).mpr (Derivable.fire rule member body),
      fun premise present => (exactLive premise).mpr (body premise present)⟩
  · intro rule member
    exact (List.mem_filter.mp (show rule ∈ rules.filter
      (fun rule => decide (live rule.head ∧ Holds live rule.body)) from member)).1
end Ascent.StableSourceSupport
