-- SPDX-FileCopyrightText: 2026 tao3k team and Contributors
-- SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
import Std

namespace Ascent.LookupCost

-- Both branches use the same read-only schema. Admission remains before work.
def repeatedAdmission (admitted : Bool) (body fallback : α) : α :=
  if admitted then (if admitted then body else fallback) else fallback

def admittedOnce (admitted : Bool) (body fallback : α) : α :=
  if admitted then body else fallback

theorem admission_deduplication (admitted : Bool) (body fallback : α) :
    repeatedAdmission admitted body fallback = admittedOnce admitted body fallback := by
  cases admitted <;> rfl

theorem canonical_columns_in_range (width column : Nat) (member : column ∈ List.range width) :
    column < width := List.mem_range.mp member

-- The SDK's tiny selected path returns the original blocks after checking this
-- canonical range. No gathering, equality-class merging or reordering is added.
def tinySelection (withinRange : Bool) (blocks : List α) : Option (List α) :=
  if withinRange then some blocks else none

theorem admitted_tiny_keeps_order_and_multiplicity (blocks : List α) :
    tinySelection true blocks = some blocks := rfl

structure Cost where
  schemas : Nat
  ranges : Nat
  deriving DecidableEq

def before (width : Nat) : Cost := ⟨2, width⟩
def after : Cost := ⟨1, 0⟩

theorem one_schema_comparison_removed (width : Nat) :
    (before width).schemas = after.schemas + 1 := rfl

theorem canonical_range_work_removed (width : Nat) :
    (before width).ranges = after.ranges + width := by simp [before, after]

-- Exact source binding is separate from the SDK evaluator/compiler premises.
def admissionSchemeSource : String :=
  "  (def (visit-admitted-complete-key columns key point)\n    (let* ((offset (- (vector-length routes) 2))\n           (endpoints (list-tail key offset)))\n      (for-each (lambda (block)\n        (with (((rectangle prefix left right) block))\n          (when (matches-prefix? key prefix)\n            ;; Return the candidate's stored values directly, without\n            ;; allocating selected singleton spines or product collectors.\n            (let ((a (captured-point-member routes left offset (car endpoints)))\n                  (b (captured-point-member routes right (+ offset 1) (cadr endpoints))))\n              (when (and a b) (point prefix (car a) (car b))))))) (if small? blocks (selected columns key)))\n      #t))\n  (def (visit-complete-key columns key point)\n    (and complete-columns (equal? columns complete-columns)\n       (visit-admitted-complete-key columns key point)))\n"

def studyProfileSchemeSource : String :=
  "(def (study-build-spec module)\n  (normalize-spec\n    (if (member module gerbil-ascent-library-modules) module\n      [gxc: module [extra-inputs: [(path-expand \"build-modules.ss\") (path-expand \"t/performance/run.ss\")]]])\n    gerbil-ascent-compiler-options))\n\n"

-- Two valid allocator histories have identical observed snapshots but
-- different heap-event allocation. A net counter is not a heap-event decoder.
def snapshot (heap stack : Nat) : Nat := heap + stack

theorem heap_events_not_identified_by_net_snapshots :
    snapshot 0 8 = snapshot 0 8 ∧ snapshot 10 0 = snapshot 2 8 ∧ (10 : Nat) ≠ 2 := by decide

def materializationSchemeSource : String :=
  "  (def (materialize-selected columns key)\n    (defrule (with-product-collector collect! collect-product body ...)\n      (with-list-builder (collect!)\n        (def (collect-product prefix lefts rights _consume)\n          (match prefix\n            ([] (collect-rectangle-product a b lefts rights collect! (list a b)))\n            ([g] (collect-rectangle-product a b lefts rights collect! (list g a b)))\n            (else (collect-rectangle-product a b lefts rights collect! (append prefix (list a b))))))\n        body ...))\n    (defrule (materialize compact? group left right)\n      (with-product-collector collect! collect-product\n        ;; Select the publisher once from the captured schema; no match\n        ;; continuation is constructed for each emitted scalar pair.\n        (def collect-point\n          (and compact?\n            (if (= (vector-length routes) 2)\n              (lambda (_prefix a b) (collect! (list a b)))\n              (lambda (prefix a b) (collect! (list (car prefix) a b))))))\n        (unless (and compact? (visit-compact-bindings group left right #f collect-product collect-point))\n          (visit-products columns key #f #f collect-product))))\n    (cond\n      ;; Unindexed materialization uses the checked scanner and the same\n      ;; collector directly. No indexed predicate or publisher can apply.\n      ((not routes)\n       (validate-key! columns key)\n       (with-product-collector collect! collect-product\n         (for-each (lambda (block)\n           (visit-scan-rectangle-parts block columns key #f #f collect-product)) blocks)))\n      ((compact-query? columns)\n       (with-compact-bindings (- (vector-length routes) 2) columns key group left right\n         (if (and group (= (vector-length routes) 3)\n                  (not (hash-get (vector-ref routes 0) (car group)))) []\n           (materialize #t group left right)) []))\n      ((and complete-columns (equal? columns complete-columns))\n       (validate-key! columns key)\n       (with-list-builder (collect!)\n         (visit-admitted-complete-key columns key\n           (lambda (prefix left right)\n             (match prefix\n               ([] (collect! (list left right)))\n               ([group] (collect! (list group left right)))\n               (else (collect! (append prefix (list left right)))))))))\n      (else (validate-key! columns key) (materialize #f #f #f #f))))\n"

-- Container erasure preserves cell order and multiplicity. Rust Clone,
-- TrustedLen and Arc allocation remain standard-library premises, checked at
-- the compiled decoder boundary by row_materialization.rs rather than assumed
-- to be a complete Rust/compiler/allocator refinement.
def stagedTuple (decode : α → β) (cells : List α) : List β :=
  (cells.map decode).toArray.toList

def directTuple (decode : α → β) (cells : List α) : List β := cells.map decode

theorem tuple_erasure_exact (decode : α → β) (cells : List α) :
    stagedTuple decode cells = directTuple decode cells := by
  simp [stagedTuple, directTuple]

def tupleTemporaryCalls (width : Nat) : Nat := if width = 0 then 0 else 1
def tupleStagedCalls (width : Nat) : Nat := 1 + tupleTemporaryCalls width
def tupleDirectCalls : Nat := 1

theorem temporary_tuple_removed (width : Nat) :
    tupleStagedCalls width = tupleDirectCalls + tupleTemporaryCalls width := rfl

def tupleTemporaryBytes (rows width valueBytes : Nat) : Nat := rows * width * valueBytes

theorem observed_closure_temporary_bytes :
    tupleTemporaryBytes (24 * (256 * 16 * 15 / 2)) 2 64 = 94371840 := by decide

def ownedRowRustSource : String :=
  "    pub fn decode(&self, row: &[Cell]) -> crate::Row {\n        row.iter()\n            .map(|cell| self.values[cell.0.get() - 1].clone())\n            .collect()\n    }\n"

def ownedRowQuintSource : String :=
  "  pure def TupleTemporaryCalls(rows: List[Row]): int = rows.foldl(0, (n,row) => n + (if (row.length() == 0) 0 else 1))\n  pure def TupleTemporaryBytes(rows: List[Row], valueBytes: int): int = rows.foldl(0, (n,row) => n + row.length() * valueBytes)\n  pure def TupleDirectCalls(rows: List[Row]): int = rows.length()\n  pure def TupleStagedCalls(rows: List[Row]): int = TupleDirectCalls(rows) + TupleTemporaryCalls(rows)\n"


-- Representation denotation for the private single-column index. The complete
-- Rust Vec/HashMap migration remains a separate source-refinement obligation.
def ordinalRead (extent : Nat) (dense sparse : Nat → List α) (key : Nat) : List α :=
  if key < extent then dense key else sparse key

def ordinalGrow (old next : Nat) (dense sparse : Nat → List α) (key : Nat) : List α :=
  if old ≤ key ∧ key < next then sparse key else dense key

def ordinalRetire (next : Nat) (sparse : Nat → List α) (key : Nat) : List α :=
  if key < next then [] else sparse key

theorem ordinal_growth_preserves_lookup (old next key : Nat)
    (dense sparse : Nat → List α) (monotone : old ≤ next) :
    ordinalRead next (ordinalGrow old next dense sparse) (ordinalRetire next sparse) key =
      ordinalRead old dense sparse key := by
  by_cases before : key < old
  · have after : key < next := Nat.lt_of_lt_of_le before monotone
    have notAfter : ¬ old ≤ key := Nat.not_le_of_gt before
    simp [ordinalRead, ordinalGrow, before, after, notAfter]
  · by_cases after : key < next
    · have beyond : old ≤ key := Nat.le_of_not_gt before
      simp [ordinalRead, ordinalGrow, before, after, beyond]
    · simp [ordinalRead, ordinalRetire, before, after]

def ordinalExtentFits (target bound nativeLimit : Nat) : Bool :=
  decide (target ≤ bound ∧ target ≤ nativeLimit)

theorem ordinal_admission_bounds (target bound nativeLimit : Nat)
    (admitted : ordinalExtentFits target bound nativeLimit = true) :
    target ≤ bound ∧ target ≤ nativeLimit := by
  simpa [ordinalExtentFits] using admitted

theorem ordinal_spine_units_bound (keys target : Nat)
    (admitted : target ≤ (keys + 1) * 2 + 4) : target ≤ 2 * keys + 6 := by omega

-- All three components belong to one measured request. This does not attribute
-- a host elapsed interval to CPU, waiting, GC, or the SDK scheduler.
def sameRequestPartition (total replace exported validation : Nat) : Prop :=
  total = replace + exported + validation

theorem same_request_excludes_validation (total replace exported validation : Nat)
    (partition : sameRequestPartition total replace exported validation) :
    total - (replace + exported) = validation := by
  simp only [sameRequestPartition] at partition
  omega

theorem mixed_phase_maxima_rejected : ¬ sameRequestPartition 10 8 7 1 := by simp [sameRequestPartition]

def ordinalExtentRustSource : String :=
  "fn extent_fits(target: usize, bound: usize, native_limit: usize) -> bool {\n    target <= bound && target <= native_limit\n}\n"


-- Only generation is consumed when no content fingerprint exists. Unsupported
-- evidence still returns false; this choice creates no provenance authority.
def proofAuthorityRead (hasFingerprint : Bool) : Bool := hasFingerprint

theorem fingerprint_read_preserved : proofAuthorityRead true = true := rfl

theorem metadata_read_suffices_without_fingerprint : proofAuthorityRead false = false := rfl

def proofAuthorityRustSource : String :=
  "        let status = if self.fingerprint.is_some() {\n            self.owner.current_projection(control)?\n        } else {\n            self.owner.current_status(control)?\n        };\n"

end Ascent.LookupCost
#print axioms Ascent.LookupCost.admission_deduplication
#print axioms Ascent.LookupCost.canonical_columns_in_range
#print axioms Ascent.LookupCost.admitted_tiny_keeps_order_and_multiplicity
#print axioms Ascent.LookupCost.one_schema_comparison_removed
#print axioms Ascent.LookupCost.canonical_range_work_removed
#print axioms Ascent.LookupCost.heap_events_not_identified_by_net_snapshots
#print axioms Ascent.LookupCost.tuple_erasure_exact
#print axioms Ascent.LookupCost.temporary_tuple_removed
#print axioms Ascent.LookupCost.observed_closure_temporary_bytes

#print axioms Ascent.LookupCost.ordinal_growth_preserves_lookup
#print axioms Ascent.LookupCost.ordinal_admission_bounds
#print axioms Ascent.LookupCost.ordinal_spine_units_bound
#print axioms Ascent.LookupCost.same_request_excludes_validation
#print axioms Ascent.LookupCost.mixed_phase_maxima_rejected

#print axioms Ascent.LookupCost.fingerprint_read_preserved
#print axioms Ascent.LookupCost.metadata_read_suffices_without_fingerprint
