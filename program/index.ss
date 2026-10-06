;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; One engine's physical indexes over live all/delta vectors. Metadata plans
;;; stay immutable; source admission and row/version publication stay in evaluate.
(import (only-in :gerbil-ascent/table/index-sharing gerbil-ascent-index-sharing-layout
                 gerbil-ascent-shared-index-build gerbil-ascent-shared-index-extend!
                 gerbil-ascent-shared-index-rows)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-index-key
                 gerbil-ascent-index-key/terms gerbil-ascent-index-value)
        (only-in :gerbil-ascent/table/access gerbil-ascent-physical-index-build
                 gerbil-ascent-physical-index-extend! gerbil-ascent-physical-index-rows
                 gerbil-ascent-physical-index-single-rows)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?
                 gerbil-ascent-curried-index-provider?))
(export gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance! row-indexes-plan-atoms! row-indexes-plan-rules! row-indexes-plan-actions!)

(defstruct row-indexes (rows advance! plan-atoms!))

;;; Custom indexes may overselect candidates, but each must still represent
;;; a complete relation tuple. Check the whole batch before term callbacks.
;;; Traversal is bounded by admitted arity, including improper/cyclic rows.
(def (checked-provider-rows rows terms members)
  (for-each
   (lambda (row)
     (let loop ((remaining row) (columns terms))
       (if (null? columns)
         (unless (null? remaining)
           (error "ASCENT index provider returned wrong row arity" (length terms)))
         (if (pair? remaining)
           (loop (cdr remaining) (cdr columns))
           (error "ASCENT index provider returned wrong row arity" (length terms))))))
   rows)
  ;; Membership follows complete shape admission, before any term matching.
  ;; The witness belongs to this physical entry's all/delta version.
  (for-each
   (lambda (row)
     (unless (hash-get members row)
       (error "ASCENT index provider returned foreign row")))
   rows)
  rows)

(def (provider-row-members rows)
  (let (members (make-hash-table))
    (for-each (lambda (row) (hash-put! members row #t)) rows)
    members))

;;; Index ownership includes discovery of the logical lookup requirements.
;;; The three execution owners supply admitted metadata, never row snapshots
;;; or evaluated key expressions, and retain their own independent roots.
;; row-indexes-plan-rules!
;; : (forall (i r) (-> (RowIndexes i) [(RulePlan r)] Void))
;; : (-> RowIndexes AdmittedRulePlans Void)
;; | doc m%
;;     Register logical atoms in original rule and clause order. Negative and
;;     aggregate lookup requirements retain their admitted atom metadata.
;;
;;     # Examples
;;
;;     ```scheme
;;     (row-indexes-plan-rules! indexes rule-plans)
;;     ;; => registers engine-owned logical lookup requirements
;;     ```
;;   %
(def (row-indexes-plan-rules! indexes rules)
  ((row-indexes-plan-atoms! indexes)
   (foldr append []
    (map (lambda (rule)
           (filter-map (lambda (clause)
                         (and (memq (vector-ref clause 0) '(atom negation aggregate))
                              (vector-ref clause 1)))
                       (vector-ref rule 1))) rules))))

;; row-indexes-plan-actions!
;; : (forall (i a) (-> (RowIndexes i) [(CompiledAction a)] Void))
;; : (-> RowIndexes AdmittedPositiveActions Void)
;; | doc m%
;;     Register immutable compiled lookup atoms for a private worker. Do not
;;     evaluate callbacks, reorder actions or share the worker's physical roots.
;;
;;     # Examples
;;
;;     ```scheme
;;     (row-indexes-plan-actions! indexes actions)
;;     ;; => registers worker-owned compiled lookup requirements
;;     ```
;;   %
(def (row-indexes-plan-actions! indexes actions)
  ((row-indexes-plan-atoms! indexes)
   (filter-map (lambda (action)
                 (and (vector? (vector-ref action 0)) (vector-ref action 0))) actions)))

;;; Stable entries belong to one engine. Column tables share them across
;;; equivalent atoms; identity tables only shortcut that structural resolution.
(def empty-row-indexes
  ;; No rule can read this immutable owner; source transactions need no cache
  ;; advancement. Reject accidental consumers instead of silently scanning.
  (make-row-indexes
   (lambda (atom environment use-delta? slot-terms)
     (error "ASCENT empty index owner has no lookup consumer"))
   (lambda (index rows (reverse-order? #f)) (void))
   (lambda (atoms)
     (unless (null? atoms) (error "ASCENT empty index owner has lookup requirements")))))

(defstruct physical-index-entry (version lookup shared? members))
(defstruct atom-index-view (entry permutation))

;; gerbil-ascent-make-row-indexes
;;   : (-> Rows Rows Sizes Sizes Versions Versions Providers RowIndexes)
;;   | doc m%
;;       Own all/delta physical caches for one engine. The engine updates the
;;       supplied row, size and version vectors; indexes extend only admitted rows.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version providers)
;;       ;; => engine-local lookup and incremental extension procedures
;;       ```
;;     %
(def (gerbil-ascent-make-row-indexes all delta all-size delta-size all-version delta-version index-providers (required? #t))
  (if required?
    (make-required-row-indexes all delta all-size delta-size all-version delta-version index-providers)
    empty-row-indexes))

(def (make-required-row-indexes all delta all-size delta-size all-version delta-version index-providers)
  ;; Scans and small relations own no physical cache vectors. Allocate each
  ;; lane only when its first indexed lookup crosses the size threshold.
  (let ((all-indexes #f) (delta-indexes #f)
        (all-atoms #f) (delta-atoms #f)
        (layouts (make-vector (vector-length all) #f)) (planned-atoms #f))
      (def (plan-atoms! atoms)
        (when (or all-indexes delta-indexes) (error "cannot replan a live physical index"))
        ;; Small snapshots need no physical plan. An explicit curried receiver
        ;; triggers planning only when an actual lookup first needs an index.
        (set! planned-atoms
          (and (ormap gerbil-ascent-curried-index-provider? (vector->list index-providers)) atoms)))
      (def (ensure-layouts!)
        (when planned-atoms
          (let ((requirements (make-vector (vector-length all) []))
                (fresh (make-vector (vector-length all) #f)))
            (for-each
             (lambda (atom)
               (let ((i (vector-ref atom 0)) (columns (vector-ref atom 2)))
                 (when (and (gerbil-ascent-curried-index-provider? (vector-ref index-providers i))
                            (= (length columns) (hash-length (let (seen (make-hash-table-eq))
                              (for-each (lambda (c) (hash-put! seen c #t)) columns) seen))))
                   (vector-set! requirements i (cons columns (vector-ref requirements i)))))) planned-atoms)
            (for-each (lambda (i)
                        (let (layout (gerbil-ascent-index-sharing-layout (vector-ref requirements i)))
                          (vector-set! fresh i (and (> (hash-length layout) 0) layout))))
                      (iota (vector-length all)))
            ;; Metadata publication follows successful complete planning.
            (set! layouts fresh) (set! planned-atoms #f))))
      (def (indexed-rows atom environment use-delta? slot-terms)
        (let* ((index (vector-ref atom 0))
               (columns (vector-ref atom 2))
               (rows (vector-ref (if use-delta? delta all) index)))
          (if (or (null? columns)
                  (< (vector-ref (if use-delta? delta-size all-size)
                                 index)
                     32))
            rows
            (begin
              (ensure-layouts!)
            (let* ((identities
                    (if use-delta?
                      (or delta-atoms
                          (let (fresh (make-hash-table-eq))
                            (set! delta-atoms fresh) fresh))
                      (or all-atoms
                          (let (fresh (make-hash-table-eq))
                            (set! all-atoms fresh) fresh))))
                   (version (vector-ref
                             (if use-delta? delta-version all-version) index))
                   (view
                    (or (hash-get identities atom)
                        (let* ((layout (vector-ref layouts index))
                               (permutation (and layout (hash-get layout (list-sort < columns))))
                               (physical-columns (or permutation columns))
                               (caches
                                (if use-delta?
                                  (or delta-indexes
                                      (let (fresh (make-vector (vector-length delta) #f))
                                        (set! delta-indexes fresh) fresh))
                                  (or all-indexes
                                      (let (fresh (make-vector (vector-length all) #f))
                                        (set! all-indexes fresh) fresh))))
                               (cache
                                (or (vector-ref caches index)
                                    (let (fresh (make-hash-table))
                                      (vector-set! caches index fresh) fresh)))
                               (shared (hash-get cache physical-columns))
                               (resolved
                                (or shared
                                    (let (fresh (make-physical-index-entry #f #f (and permutation #t) #f))
                                      (hash-put! cache physical-columns fresh) fresh))))
                          (let (view (make-atom-index-view resolved permutation))
                            (hash-put! identities atom view)
                            view))))
                   (entry (atom-index-view-entry view))
                   (permutation (atom-index-view-permutation view))
                   (provider (vector-ref index-providers index))
                   (lookup
                    (if (and (physical-index-entry-version entry)
                             (= (physical-index-entry-version entry) version))
                      (physical-index-entry-lookup entry)
                      (let* ((members (and (not permutation)
                                          (not (gerbil-ascent-canonical-hash-index-provider? provider))
                                          (provider-row-members rows)))
                             (built (if permutation
                                   (gerbil-ascent-shared-index-build rows permutation)
                                   (gerbil-ascent-physical-index-build provider rows columns))))
                        ;; Failed builds keep the old version and lookup. Publish
                        ;; both only after the provider has returned successfully.
                        (physical-index-entry-lookup-set! entry built)
                        (physical-index-entry-members-set! entry members)
                        (physical-index-entry-version-set! entry version)
                        built))))
              ;; Only this trusted representation consumes a scalar. Custom
              ;; receivers retain list keys, callbacks and their lookup order.
              (if (and (not permutation) (gerbil-ascent-canonical-hash-index-provider? provider)
                       (null? (cdr columns)))
                (gerbil-ascent-physical-index-single-rows
                 lookup (gerbil-ascent-index-value
                         (car (vector-ref atom 4)) environment
                         (and slot-terms (car slot-terms))))
                (let (key (if slot-terms
                            (gerbil-ascent-index-key
                             (vector-ref atom 1) columns environment slot-terms)
                            (gerbil-ascent-index-key/terms
                             (vector-ref atom 4) environment)))
                  (if permutation
                    (gerbil-ascent-shared-index-rows lookup columns key)
                    (let (matched (gerbil-ascent-physical-index-rows provider lookup key))
                      (if (gerbil-ascent-canonical-hash-index-provider? provider)
                        matched
                        (checked-provider-rows matched (vector-ref atom 1)
                                               (physical-index-entry-members entry))))))))))))
      (def (advance-all-indexes! index new-rows (reverse-order? #f))
        (let (cache (and all-indexes (vector-ref all-indexes index)))
          (when (and cache (pair? new-rows))
            (let ((rows (if reverse-order? (reverse new-rows) new-rows))
                  (version (vector-ref all-version index))
                  (provider (vector-ref index-providers index)))
              (hash-for-each
               (lambda (columns entry)
                 (when (and (physical-index-entry-version entry)
                            (= (physical-index-entry-version entry) version))
                   ;; A provider may mutate its lookup before raising. Revoke
                   ;; the old version before dispatch so failure forces rebuild
                   ;; from still-committed rows on the next read.
                   (physical-index-entry-version-set! entry #f)
                   (let (extended (if (physical-index-entry-shared? entry)
                                   (gerbil-ascent-shared-index-extend! (physical-index-entry-lookup entry) rows)
                                   (gerbil-ascent-physical-index-extend!
                                    provider (physical-index-entry-lookup entry) rows columns)))
                     (physical-index-entry-lookup-set! entry extended)
                     (when (physical-index-entry-members entry)
                       (for-each
                        (lambda (row) (hash-put! (physical-index-entry-members entry) row #t))
                        rows))
                     (physical-index-entry-version-set! entry (+ version 1)))))
               cache)))))
    (make-row-indexes indexed-rows advance-all-indexes! plan-atoms!)))
