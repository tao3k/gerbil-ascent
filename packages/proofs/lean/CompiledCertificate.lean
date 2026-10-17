-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import IndexedPositiveTraversal
import PhysicalBuckets

/-! Translation validation of decoded positive descriptors. accept is decidable
and compares compiler output with independent first-occurrence lowering. Scheme
checks actual descriptors before caching them. Symbol identity, decoding and
the host matcher implementation remain explicit trusted representation edges. -/
namespace Ascent.CompiledCertificate
open AtomicBinding PositiveSlots IndexedPositiveTraversal
variable {Value Output : Type} [DecidableEq Value]

structure Descriptor (Value : Type) where
  actions : List (Action Value)
  keys : List (Action Value)
  names : List Nat
  deriving DecidableEq

def expected (terms : List (Term Value)) (columns names : List Nat) : Descriptor Value :=
  let compiled := compile terms names
  ⟨compiled.1, columns.filterMap (fun column => compiled.1[column]?), compiled.2⟩

def accept (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) : Bool :=
  decide (actual = expected terms columns names) &&
    columns.all (fun column => match terms[column]? with
      | none => false
      | some term => match term with
        | .literal _ => true
        | .wildcard => false
        | .variable name => (slot name names).isSome)

theorem accepted_descriptor (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true) :
    actual = expected terms columns names := by
  simp only [accept, Bool.and_eq_true, decide_eq_true_eq] at accepted
  exact accepted.1

theorem accepted_vector_refines (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true)
    {n : Nat} (row : List Value) (frame : Frame Value) (vector : Vector Value n)
    (rep : VectorRep frame vector) (extent : actual.names.length ≤ n) :
    ∃ result, runVector actual.actions row vector = some result ∧
      result.1 = (run (compile terms names).1 row frame).1 ∧
      VectorRep (run (compile terms names).1 row frame).2 result.2 := by
  have descriptor := accepted_descriptor terms columns names actual accepted
  subst actual
  exact compiled_vector_refines terms names row frame vector rep extent

theorem accepted_keys (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true) :
    ∀ column ∈ columns, ∃ term, terms[column]? = some term ∧ Indexable names term := by
  intro column member
  have checkedAll : columns.all (fun column => match terms[column]? with
      | none => false
      | some term => match term with
        | .literal _ => true
        | .wildcard => false
        | .variable name => (slot name names).isSome) = true := by
    simp only [accept, Bool.and_eq_true] at accepted
    exact accepted.2
  have checked := List.all_eq_true.mp checkedAll column member
  cases found : terms[column]? with
  | none => simp [found] at checked
  | some term =>
      refine ⟨term, rfl, ?_⟩
      cases term <;> simp_all [Indexable]

theorem accepted_source_binding (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true)
    {n : Nat} (row : List Value) (env : Env Value) (frame : Frame Value)
    (vector : Vector Value n) (rep : VectorRep frame vector)
    (represented : Represents names env frame) (arity : terms.length = row.length)
    (extent : actual.names.length ≤ n) :
    ∃ result, runVector actual.actions row vector = some result ∧
      result.1 = (AtomicBinding.bind terms row env).isSome := by
  obtain ⟨result, executed, same, _⟩ :=
    accepted_vector_refines terms columns names actual accepted row frame vector rep extent
  exact ⟨result, executed, same.trans (compiled_binding terms row names env frame arity represented).1⟩

theorem accepted_known_columns (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true)
    (env : Env Value) (frame : Frame Value) (represented : Represents names env frame) :
    KnownColumns terms columns env := by
  intro column member
  obtain ⟨term, located, readable⟩ := accepted_keys terms columns names actual accepted column member
  cases term with
  | literal value => exact ⟨.literal value, value, located, rfl⟩
  | wildcard => simp [Indexable] at readable
  | «variable» name =>
      cases found : slot name names with
      | none => simp [Indexable, found] at readable
      | some index =>
          refine ⟨.variable name, frame index, located, ?_⟩
          simpa [wanted, found] using represented name

/-- Constructed hash buckets preserve the complete ordinary source binder,
including row order and duplicate occurrences. No IndexExact premise occurs. -/
theorem constructed_bucket_binding (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true)
    (rows : List (List Value)) (env : Env Value) (frame : Frame Value)
    (represented : Represents names env frame)
    (arity : ∀ row ∈ rows, terms.length = row.length) (emit : Env Value → List Output) :
    (PhysicalBuckets.extend (PhysicalBuckets.append (projectedKey columns)) (fun _ => []) rows
      (compiledKey terms columns names frame)).flatMap (fun row =>
        match AtomicBinding.bind terms row env with | none => [] | some output => emit output) =
    rows.flatMap (fun row => match AtomicBinding.bind terms row env with
      | none => [] | some output => emit output) := by
  have known := accepted_known_columns terms columns names actual accepted env frame represented
  rw [PhysicalBuckets.rust_build_exact]
  apply filter_binding
  intro row member output success
  simp only [decide_eq_true_eq]
  rw [compiled_key_refines terms columns names env frame represented known]
  exact (bind_columns terms columns row env output (arity row member) known success).symm

theorem constructed_scheme_bucket_binding (terms : List (Term Value)) (columns names : List Nat)
    (actual : Descriptor Value) (accepted : accept terms columns names actual = true)
    (rows : List (List Value)) (env : Env Value) (frame : Frame Value)
    (represented : Represents names env frame)
    (arity : ∀ row ∈ rows, terms.length = row.length) (emit : Env Value → List Output) :
    (PhysicalBuckets.extend (PhysicalBuckets.prepend (projectedKey columns)) (fun _ => []) rows
      (compiledKey terms columns names frame)).reverse.flatMap (fun row =>
        match AtomicBinding.bind terms row env with | none => [] | some output => emit output) =
    rows.flatMap (fun row => match AtomicBinding.bind terms row env with
      | none => [] | some output => emit output) := by
  rw [PhysicalBuckets.scheme_build_exact]
  have appendProof := constructed_bucket_binding terms columns names actual accepted
    rows env frame represented arity emit
  rw [PhysicalBuckets.rust_build_exact] at appendProof
  exact appendProof

end Ascent.CompiledCertificate
