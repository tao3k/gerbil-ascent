;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; A storage Provider changes which facts a relation exposes. Evaluation-local
;;; state belongs to the relation run, not the shared Provider declaration.
;;; Stateful Providers must reject failures before mutating their private state;
;;; the evaluator preflights returned batches before committing its own rows.
(import (only-in :gerbil/runtime/gambit fx-)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop .defgeneric define-type validate)
        (only-in :core/types
                 PooFlowNativeObjectContract.
                 poo-flow-predicate-contract)
        (only-in "eqrel.ss" gerbil-ascent-eqrel-state
                 gerbil-ascent-eqrel-extension)
        (only-in "trrel.ss" gerbil-ascent-trrel-state
                 gerbil-ascent-trrel-extension)
        (only-in "trrel-uf.ss" gerbil-ascent-trrel-uf-state
                 gerbil-ascent-trrel-uf-extension))

(export GerbilAscentStorageProviderContract
        gerbil-ascent-set-storage-provider
        gerbil-ascent-canonical-set-storage-provider?
        gerbil-ascent-eqrel-storage-provider
        gerbil-ascent-trrel-storage-provider
        gerbil-ascent-trrel-uf-storage-provider
        gerbil-ascent-storage-make-state
        gerbil-ascent-set-batch-admit!
        gerbil-ascent-storage-extend)

(def +make-state+
  (poo-flow-predicate-contract 'ascent/storage-make-state procedure?
                               (lambda (_value _context) [])))
(def +extend+
  (poo-flow-predicate-contract 'ascent/storage-extend procedure?
                               (lambda (_value _context) [])))

;;; Every storage provider owns a fresh state per evaluation. The shared POO
;;; declaration contains only constructor and extension behavior.
(define-type (GerbilAscentStorageProviderContract
              @ PooFlowNativeObjectContract.)
  identity: 'ascent/storage-provider
  proto: (.o)
  responsibilities: (.o .make-state: +make-state+
                      .extend-rows: +extend+))

(def StorageProvider. (.ref GerbilAscentStorageProviderContract 'proto))

;; : (-> StorageProvider StorageState)
(def (gerbil-ascent-storage-make-state provider)
  ((.ref provider '.make-state)))

;;; Admit a newest-first source-log prefix against Set membership. On an
;;; empty Set, a unique whole log is already the correct row spine and can be
;;; shared without copying. The fallback walks source order, so duplicates
;;; preserve the first accepted row's position. The returned table owns all
;;; accepted rows, including when the input table was empty and resized.
;; gerbil-ascent-set-batch-admit!
;;   : (-> SourceLog Nat SetMembership Boolean (Values Rows SetMembership))
;;   | doc m%
;;       Admit a staged Set batch in source order and return the accepted rows
;;       with their membership index. An empty Set can share a unique source
;;       log without copying its list spine.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-set-batch-admit! '((1 2)) 1 (make-hash-table) #t)
;;       ;; => the accepted row list and its membership table
;;       ```
;;     %
(def (gerbil-ascent-set-batch-admit! source-log count seen share-source?)
  (def (admit present)
    (let (source-order
          (let collect ((cursor source-log) (left count) (ordered []))
            (if (= left 0) ordered
              (collect (cdr cursor) (fx- left 1)
                       (cons (car cursor) ordered)))))
      (let deduplicate ((remaining source-order) (accepted []))
        (if (null? remaining)
          (values accepted present)
          (let (row (car remaining))
            (if (hash-get present row)
              (deduplicate (cdr remaining) accepted)
              (begin
                (hash-put! present row #t)
                (deduplicate (cdr remaining) (cons row accepted)))))))))
  (if (and share-source? (= (hash-length seen) 0))
    (let (present (make-hash-table size: count))
      ;; Clear the private uniqueness table before source-order admission:
      ;; its newest-row keys must not replace first-accepted row identities.
      (let scan ((cursor source-log) (left count) (next-size 1))
        (if (= left 0)
          (if (null? cursor)
            (values source-log present)
            (begin (hash-clear! present) (admit present)))
          (begin
            ;; One insertion and its cardinality reveal a duplicate without
            ;; hashing every unique row a second time for a membership probe.
            (hash-put! present (car cursor) #t)
            (if (= (hash-length present) next-size)
              (scan (cdr cursor) (fx- left 1) (fx+ next-size 1))
              (begin (hash-clear! present) (admit present)))))))
    (admit seen)))

;;; Extension must return a bounded batch before the evaluator commits rows;
;;; stateful providers preflight failures before changing their own state.
;; : (-> StorageProvider StorageState Rows Rows Row Nat Rows)
(.defgeneric (gerbil-ascent-storage-extend provider state all pending row budget)
  slot: .extend-rows)

(def +canonical-set-storage-provider+
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ StorageProvider.)
                (.make-state (lambda () #f))
                (.extend-rows
                 (lambda (_state _all _pending row _budget) (list row))))))

(def gerbil-ascent-set-storage-provider +canonical-set-storage-provider+)

;;; Keep trusted representation identity independent of the exported default.
;; gerbil-ascent-canonical-set-storage-provider?
;;   : (-> StorageProviderCandidate Boolean)
;;   | doc m%
;;       Recognize the privately retained Set receiver validated at module load.
;;       Derived/custom receivers retain their normal checked dispatch.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-canonical-set-storage-provider? gerbil-ascent-set-storage-provider)
;;       ;; => #t for the original exported default
;;       ```
;;     %
(def (gerbil-ascent-canonical-set-storage-provider? value)
  (eq? value +canonical-set-storage-provider+))

(def gerbil-ascent-eqrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-eqrel-state)
                (.extend-rows gerbil-ascent-eqrel-extension))))

(def gerbil-ascent-trrel-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-trrel-state)
                (.extend-rows gerbil-ascent-trrel-extension))))

(def gerbil-ascent-trrel-uf-storage-provider
  (validate GerbilAscentStorageProviderContract
            (.o (:: @ gerbil-ascent-set-storage-provider)
                (.make-state gerbil-ascent-trrel-uf-state)
                (.extend-rows gerbil-ascent-trrel-uf-extension))))
