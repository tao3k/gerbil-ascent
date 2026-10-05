/-
SPDX-FileCopyrightText: 2026 tao3k team and Contributors
SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

Source replacement and derived-result certificates use LeanPoo's typed
states, patches, obligation dependencies, pending filter and closure rule.
The locality premise must be justified for each admitted ASCENT rule graph;
the native dependency planner is not proved by this module.
-/
import LeanPoo.Proof.Batch
import LeanPoo.Proof.Invalidation
import NativeSessionPublication
import StratifiedNegation

namespace Ascent.SourceCertificates

open LeanPoo.Proof

universe u v w

/-- A derived value is stable when every source on which it depends agrees.
    `locality` is the semantic dependency-closure obligation. -/
def resultObligation {Key : Type u} {Value : Key → Type v}
    {Result : Type w} (dependencies : List Key)
    (derive observed : State Key Value → Result)
    (locality : ∀ before after : State Key Value,
      (∀ key, key ∈ dependencies → before key = after key) →
      derive before = derive after ∧
      observed before = observed after) : Obligation Key Value where
  dependencies := dependencies
  holds := fun source => derive source = observed source
  stable := by
    intro before after equal certified
    obtain ⟨sameDerivation, sameObserved⟩ := locality before after equal
    exact sameDerivation.symm.trans (certified.trans sameObserved)

/-- A disjoint batch retains an already certified result. The frame and
    reuse theorem are LeanPoo's, including repeated-key batch semantics. -/
theorem reuse_after_batch [DecidableEq Key]
    (object : ProofObject Key Value) (certificate : Certificate object)
    (obligation : Obligation Key Value)
    (owned : obligation ∈ object.obligations)
    (updates : List (Sigma Value))
    (disjoint : ∀ key, key ∈ obligation.dependencies →
      key ∉ updates.map Sigma.fst) :
    obligation.holds (append object (Patch.setMany updates)).state := by
  exact reuse object (Patch.setMany updates) certificate obligation owned
    ((unaffected_setMany_iff obligation updates).mpr disjoint)

/-- The executable invalidation filter selects exactly affected old
    certificates and any newly attached certificates. -/
theorem pending_after_batch [DecidableEq Key]
    (object : ProofObject Key Value) (updates : List (Sigma Value))
    (added : List (Obligation Key Value))
    (obligation : Obligation Key Value) :
    obligation ∈ pending object (Patch.setMany updates added) ↔
      (obligation ∈ object.obligations ∧
        ∃ key, key ∈ obligation.dependencies ∧
          key ∈ updates.map Sigma.fst) ∨
      obligation ∈ added := by
  rw [mem_pending_iff]
  simp only [unaffected_setMany_iff]
  constructor
  · rintro (⟨owned, affected⟩ | fresh)
    · left
      have witness : ∃ key, key ∈ obligation.dependencies ∧
          key ∈ updates.map Sigma.fst := by
        classical
        apply Classical.byContradiction
        intro absent
        apply affected
        intro key dependency touched
        exact absent ⟨key, dependency, touched⟩
      obtain ⟨key, dependency, touched⟩ := witness
      exact ⟨owned, key, dependency, touched⟩
    · exact Or.inr (by simpa [Patch.setMany] using fresh)
  · rintro (⟨owned, key, dependency, touched⟩ | fresh)
    · exact Or.inl ⟨owned, by intro safe; exact (safe key dependency) touched⟩
    · exact Or.inr (by simpa [Patch.setMany] using fresh)

/-- Rechecking every selected obligation closes the complete certificate.
    No source/result proof is silently reused after a dependency change. -/
theorem close_after_batch [DecidableEq Key]
    (object : ProofObject Key Value) (certificate : Certificate object)
    (updates : List (Sigma Value))
    (added : List (Obligation Key Value))
    (discharged : ∀ obligation,
      obligation ∈ pending object (Patch.setMany updates added) →
      obligation.holds (append object (Patch.setMany updates added)).state) :
    Certificate (append object (Patch.setMany updates added)) :=
  closePending object (Patch.setMany updates added) certificate discharged

/-- An atomic Session publication of a typed LeanPoo source patch installs
    the derived result for the new cut, while every untouched source keeps
    its old value. A completed solve is an explicit premise in `resultOf`. -/
theorem published_batch_frame [DecidableEq Key]
    (resultOf : State Key Value → Result)
    (session : NativePublication.State (State Key Value) Result)
    (updates : List (Sigma Value)) :
    let next := NativePublication.batchComplete resultOf session
      ((Patch.setMany updates).apply session.committed)
    next.published = resultOf next.committed ∧
      (∀ key, key ∉ updates.map Sigma.fst →
        next.committed key = session.committed key) := by
  constructor
  · rfl
  · intro key untouched
    exact (Patch.setMany updates).frame session.committed key
      (by simpa [Patch.setMany_touched] using untouched)

/-- The index-exactness premise from the negation proof is a LeanPoo
    obligation over two typed slots: the frozen full relation and the
    candidate bucket. Updating either slot selects it for revalidation. -/
def indexExactObligation {env row : Type}
    (bind : env → row → Option env) (input : env) :
    Obligation Bool (fun _ => List row) where
  dependencies := [true, false]
  holds := fun state => StratifiedNegation.IndexExact
    (state true) (state false) bind input
  stable := by
    intro before after same valid
    have full : before true = after true := same true (by simp)
    have candidates : before false = after false := same false (by simp)
    simpa [full, candidates] using valid

/-- A current LeanPoo certificate discharges the exact-index premise of
    branch-local negation. It does not establish native hash-bucket fidelity. -/
theorem certified_indexed_negation {env row : Type}
    (bind : env → row → Option env) (input output : env)
    (object : ProofObject Bool (fun _ => List row))
    (certificate : Certificate object)
    (owned : indexExactObligation bind input ∈ object.obligations) :
    StratifiedNegation.ClauseHolds
        (.negation (object.state false) bind) input output ↔
      StratifiedNegation.ClauseHolds
        (.negation (object.state true) bind) input output := by
  exact StratifiedNegation.negation_indexed_iff
    (object.state true) (object.state false) bind input output
    (certificate (indexExactObligation bind input) owned)

end Ascent.SourceCertificates
