;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Declaration descriptors and current protocol guards; no engine buffers.
(import (only-in :std/list/list delete-duplicates/hash)
        (only-in :clan/poo/object .o .cc .ref .ref/cached object-revision)
        (only-in :clan/poo/mop define-type element? validate Type. Any)
        (only-in :clan/poo/type Record)
        (only-in :clan/poo/object-contract ObjectContract.)
        (only-in :tao3k/yuanxu/types/contracts
                 YuanxuObjectContract. YuanxuContract.
                 yuanxu-predicate-contract)
        (only-in :gerbil-ascent/table/provider
                 GerbilAscentIndexProviderContract gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 GerbilAscentStorageProviderContract gerbil-ascent-canonical-set-storage-provider?))
(export
  GerbilAscentRelationContract
  GerbilAscentLatticeContract
  GerbilAscentTermContract
  slot-contract
  +symbol+
  +arity+
  gerbil-ascent-fact-limit?
  +fact-budget+
  +rows+
  +field-predicates+
  +provider+
  +storage-provider+
  term-kind?
  +term-kind+
  +any+
  +plan+
  clause-kind?
  clause-kind-contract
  +term-value+
  canonical-metadata-current?
  canonical-value-member
  canonical-validation-current?
  canonical-value-check-current?)

;; : (-> Symbol Procedure PredicateContract)
(def (slot-contract identity predicate)
  (yuanxu-predicate-contract identity predicate))

(def +symbol+ (slot-contract 'ascent/symbol symbol?))
(def +arity+ (slot-contract 'ascent/arity
                           (lambda (value)
                             (and (exact-integer? value) (<= 0 value)))))
(def (gerbil-ascent-fact-limit? value)
  (or (eqv? value +inf.0)
      (and (exact-integer? value) (> value 0))))
(def +fact-budget+
  (slot-contract 'ascent/fact-budget gerbil-ascent-fact-limit?))
(def +rows+ (slot-contract 'ascent/rows list?))
(def +field-predicates+
  (slot-contract 'ascent/field-predicates
                 (lambda (value)
                   (and (list? value) (andmap procedure? value)))))
(def +provider+
  (slot-contract 'ascent/index-provider
                 (lambda (value)
                   ;; This exact receiver was validated when its module loaded.
                   ;; Derived/custom objects have another identity and retain
                   ;; the complete receiver contract, including missing slots.
                   (or (gerbil-ascent-canonical-hash-index-provider? value)
                       (element? GerbilAscentIndexProviderContract value)))))
(def +storage-provider+
  (slot-contract 'ascent/storage-provider
                 (lambda (value)
                   (or (gerbil-ascent-canonical-set-storage-provider? value)
                       (element? GerbilAscentStorageProviderContract value)))))
(def (term-kind? value)
  (memq value '(variable wildcard literal expression pattern)))
(def +term-kind+ (slot-contract 'ascent/term-kind term-kind?))
(def +any+ (slot-contract 'ascent/value (lambda (_value) #t)))
(def +plan+ (slot-contract 'ascent/clause-plan procedure?))
;; : (-> Symbol PredicateContract)
(def (clause-kind? expected value) (eq? value expected))
(def (clause-kind-contract kind)
  (slot-contract 'ascent/clause-kind (cut clause-kind? kind <>)))

;;; Relation shape checks arity, source rows, and physical providers before
;;; the evaluator creates any mutable table state.
(define-type (GerbilAscentRelationContract @ YuanxuObjectContract.)
  identity: 'ascent/relation
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'relation)
                      index-provider: +provider+
                      storage-provider: +storage-provider+))

;;; A lattice owns a join operation; key refinement semantics are distinct
;;; from ordinary set insertion even when source rows have the same shape.
(define-type (GerbilAscentLatticeContract @ YuanxuObjectContract.)
  identity: 'ascent/lattice
  proto: (.o)
  responsibilities: (.o name: +symbol+ arity: +arity+ rows: +rows+
                      field-predicates: +field-predicates+
                      storage-kind: (clause-kind-contract 'lattice)
                      join: (slot-contract 'ascent/lattice-join procedure?)
                      checked-operator:
                      (slot-contract 'ascent/lattice-checked-operator
                                     (lambda (value)
                                       (or (not value) (vector? value))))
                      index-provider: +provider+))

;;; Terms retain tagged source intent until planning can resolve variables and
;;; construct executable expression and pattern operations.
(define-type (GerbilAscentTermContract @ YuanxuObjectContract.)
  identity: 'ascent/term
  proto: (.o)
  responsibilities: (.o kind: +term-kind+ value: +any+))

;; Nested membership consumes a Boolean, not a contextual receipt. Reuse
;; the upstream value Type with the same ancestry, fields and kind predicate;
;; explicit Term admission still uses the complete public Flow Contract above.
(def +term-value+
  (.cc ObjectContract. identity: 'ascent/term-value
       required-prototype: (.ref GerbilAscentTermContract 'proto)
       extra-fields: 'delegate constraints: (list Any)
       responsibilities: (.o kind: (.cc Type. .element?: term-kind?) value: Any)))


;; Retain public descriptor mutation and classifier instrumentation. POO revisions
;; invalidate ordinary metadata edits; classifier identity also detects the
;; existing direct instance instrumentation used by the semantic cost control.
;; This caches descriptor identity only, never the result for an input value.
;; BEGIN GENERATED PREPARATION METADATA-GUARD
(def (canonical-metadata-current? contract slots)
  (let* ((fields (.ref contract 'responsibilities))
         (descriptors (cons contract (map (cut .ref fields <>) slots)))
         ;; Revisions are pure identity reads. A shared field descriptor (for
         ;; example the three Program fact limits) needs one revision check.
         ;; Keep ALL slot/classifier deliveries below, in their original order:
         ;; those reads are observable through POO and cannot be deduplicated.
         (sources (delete-duplicates/hash (cons fields descriptors) table: (make-hash-table-eq)))
         (revisions (map object-revision sources))
         (classifiers (map (cut .ref <> '.classify) descriptors)))
    (lambda ()
      (and (andmap (lambda (source revision) (= (object-revision source) revision)) sources revisions)
           (eq? fields (.ref/cached contract 'responsibilities))
           (andmap (lambda (slot descriptor) (eq? (.ref/cached fields slot) descriptor)) slots (cdr descriptors))
           (andmap (lambda (descriptor classifier) (eq? (.ref/cached descriptor '.classify) classifier))
                   descriptors classifiers)))))
(def (canonical-value-member contract view slots)
  (let (current? (canonical-value-check-current? contract slots))
    (lambda (value)
      (if (current?) (element? view value) (element? contract value)))))
(def (canonical-validation-current? contract slots)
  (let* ((fields (.ref contract 'responsibilities))
         (descriptors (delete-duplicates/hash (map (cut .ref fields <>) slots) table: (make-hash-table-eq)))
         (missing (gensym 'missing-validation-protocol))
         ;; One stable sentinel producer per guard. Cache misses still invoke
         ;; it separately through POO, fail this guard and take full admission.
         ;; Never allocate a new default closure at each protocol slot probe.
         (missing-default (lambda () missing))
         (entries
          (apply append
            (map (lambda (entry)
                   (map (lambda (slot) (vector (car entry) slot (.ref (car entry) slot))) (cdr entry)))
                 (cons (cons contract '(.element? .validate .admit .obligations value-contract))
                       (map (lambda (field) (cons field '(.element? .admit .obligations value-contract))) descriptors))))))
    (lambda ()
      (andmap (lambda (entry)
                (eq? (vector-ref entry 2)
                     (.ref/cached (vector-ref entry 0) (vector-ref entry 1) missing-default))) entries))))
;;; Capture metadata/method identities for a callback-free compatible value view.
;;; The caller proves view compatibility; this predicate never admits a value.
;; : (-> Contract [Symbol] (-> Boolean))
(def (canonical-value-check-current? contract slots)
  (let ((metadata? (canonical-metadata-current? contract slots))
        (protocol? (canonical-validation-current? contract slots)))
    (lambda () (and (metadata?) (protocol?)))))
;; END GENERATED PREPARATION METADATA-GUARD
