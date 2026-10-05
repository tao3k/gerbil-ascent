-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import AscentProof

/-! Compile-time qualification for LeanPoo source patches, invalidation,
certificate reuse and atomic ASCENT publication. -/

namespace Ascent.ProofTests

open LeanPoo.Proof
open Ascent.SourceCertificates

def sampleUpdates : List (Sigma fun _ : Bool => Nat) := [⟨true, 7⟩]
def sampleSource : State Bool (fun _ => Nat) := fun _ => 0

example : (Patch.setMany sampleUpdates).touched = [true] := by
  simpa [sampleUpdates] using Patch.setMany_touched sampleUpdates []

example : (Patch.setMany sampleUpdates).apply sampleSource false = 0 := by
  exact (Patch.setMany sampleUpdates).frame sampleSource false
    (by simp [Patch.setMany_touched, sampleUpdates])

example : (Patch.setMany sampleUpdates).apply sampleSource true = 7 := by
  simpa [sampleUpdates] using
    Patch.setMany_last ([] : List (Sigma fun _ : Bool => Nat)) true 7 sampleSource

def falseObligation : Obligation Bool (fun _ => Nat) :=
  resultObligation [false] (fun source => source false) (fun _ => 0) (by
    intro before after same
    exact ⟨same false (by simp), rfl⟩)

def certifiedSource : ProofObject Bool (fun _ => Nat) :=
  ⟨sampleSource, [falseObligation]⟩

theorem certifiedSource_ok : Certificate certifiedSource := by
  intro obligation member
  have h : obligation = falseObligation := by
    simpa [certifiedSource] using member
  subst obligation
  rfl

example : falseObligation.holds
    (append certifiedSource (Patch.setMany sampleUpdates)).state := by
  apply reuse_after_batch certifiedSource certifiedSource_ok falseObligation
  · simp [certifiedSource]
  · intro key member touched
    have h : key = false := by simpa [falseObligation, resultObligation] using member
    subst key
    simp [sampleUpdates] at touched

example : falseObligation ∉
    pending certifiedSource (Patch.setMany sampleUpdates) := by
  intro membership
  have selected := (pending_after_batch certifiedSource sampleUpdates [] falseObligation).mp membership
  rcases selected with ⟨_, key, depends, touched⟩ | added
  · have h : key = false := by simpa [falseObligation, resultObligation] using depends
    subst key
    simp [sampleUpdates] at touched
  · simp at added

/-- A changed source and its cached result are patched together. The old
    correctness obligation becomes pending and is proved for the new cut. -/
def pairedObligation : Obligation Bool (fun _ => Nat) :=
  resultObligation [true, false]
    (fun source => source true) (fun source => source false) (by
      intro before after same
      exact ⟨same true (by simp), same false (by simp)⟩)

def pairedSource : ProofObject Bool (fun _ => Nat) :=
  ⟨sampleSource, [pairedObligation]⟩

theorem pairedSource_ok : Certificate pairedSource := by
  intro obligation member
  have h : obligation = pairedObligation := by
    simpa [pairedSource] using member
  subst obligation
  rfl

def pairedUpdates : List (Sigma fun _ : Bool => Nat) :=
  [⟨true, 7⟩, ⟨false, 7⟩]

example : pairedObligation ∈
    pending pairedSource (Patch.setMany pairedUpdates) := by
  apply (pending_after_batch pairedSource pairedUpdates [] pairedObligation).mpr
  left
  refine ⟨by simp [pairedSource], true, ?_, ?_⟩
  · simp [pairedObligation, resultObligation]
  · simp [pairedUpdates]

theorem pairedSource_updated :
    pairedObligation.holds
      (append pairedSource (Patch.setMany pairedUpdates)).state := by
  simp [pairedObligation, resultObligation, append, pairedSource,
    pairedUpdates, Patch.setMany, Patch.composeAll, Patch.empty,
    Patch.then, Patch.set, sampleSource]

example : Certificate (append pairedSource (Patch.setMany pairedUpdates)) := by
  apply close_after_batch pairedSource pairedSource_ok pairedUpdates []
  intro obligation selected
  have owned : obligation ∈ pairedSource.obligations := by
    rcases (pending_after_batch pairedSource pairedUpdates [] obligation).mp selected with
      ⟨member, _, _, _⟩ | fresh
    · exact member
    · simp at fresh
  have same : obligation = pairedObligation := by
    simpa [pairedSource] using owned
  subst obligation
  exact pairedSource_updated

def fullAndBucket : State Bool (fun _ => List Nat) := fun _ => [1, 2]
def bindAny (_ : Unit) (_ : Nat) : Option Unit := some ()
def exactIndex : Obligation Bool (fun _ => List Nat) :=
  indexExactObligation bindAny ()
def indexObject : ProofObject Bool (fun _ => List Nat) :=
  ⟨fullAndBucket, [exactIndex]⟩

theorem indexObject_ok : Certificate indexObject := by
  intro obligation member
  have same : obligation = exactIndex := by
    simpa [indexObject] using member
  subst obligation
  constructor
  · intro value present
    exact present
  · intro value output present _
    exact present

example : StratifiedNegation.ClauseHolds
      (.negation (indexObject.state false) bindAny) () () ↔
    StratifiedNegation.ClauseHolds
      (.negation (indexObject.state true) bindAny) () () :=
  certified_indexed_negation bindAny () () indexObject indexObject_ok
    (by simp [indexObject, exactIndex])

def sourceOnly : List (Sigma fun _ : Bool => List Nat) :=
  [⟨true, [1, 2, 3]⟩]

example : exactIndex ∈ pending indexObject (Patch.setMany sourceOnly) := by
  apply (pending_after_batch indexObject sourceOnly [] exactIndex).mpr
  left
  refine ⟨by simp [indexObject], true, ?_, ?_⟩
  · simp [exactIndex, indexExactObligation]
  · simp [sourceOnly]

example : ¬ NativePublication.Good NativePublication.symbolicResult
    (NativePublication.sourceAlias
      (NativePublication.initial NativePublication.symbolicResult
        NativePublication.emptyCut)
      NativePublication.viaCut) :=
  NativePublication.mutable_source_counterexample

end Ascent.ProofTests
