;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Initialization mutates only buffers owned by the constructing engine.
;;; Source multiplicity and row identity are preserved, including duplicates.
(import (only-in :std/list/list-builder with-list-builder))

(export gerbil-ascent-initialize-source-row! gerbil-ascent-admit-source-row!
        gerbil-ascent-check-replacement-rows! gerbil-ascent-prepare-storage-batch)

;; : (forall (a) (-> Symbol [a] Integer (Maybe (-> a Any)) Void))
;; gerbil-ascent-check-replacement-rows!
;;   : (-> RelationName Rows Arity (Maybe RowChecker) Void)
;;   | doc m%
;;       Validate prospective source rows before any replacement state changes.
;;       Atomic and retained updates expose the same diagnostic boundary.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-check-replacement-rows! 'edge '((0 1)) 2 #f)
;;       ;; => validates the prospective source without publishing it
;;       ```
;;     %
(def (gerbil-ascent-check-replacement-rows! name rows width check)
  (unless (list? rows)
    (error "invalid ASCENT replacement source rows" name rows))
  (for-each
   (lambda (row)
     (unless (and (list? row) (= (length row) width))
       (error "invalid ASCENT replacement source row" name row))
     (when check (check row))) rows))

;; gerbil-ascent-initialize-source-row!
;;   : (-> Row Nat (Maybe RowChecker) Membership RowsBuffer Nat Nat Nat Nat)
;;   | doc m%
;;       Validate and materialize one source expansion row in engine-owned
;;       buffers, returning its updated materialized count. Every source row
;;       consumes budget even when the membership table already contains it.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-initialize-source-row!
;;         '(1) 1 #f (make-hash-table) (vector []) 0 0 8)
;;       ;; => 1
;;       ```
;;     %
(def (gerbil-ascent-initialize-source-row! stored width check present all index
                                          count output-limit)
  (unless (and (list? stored) (= (length stored) width))
    (error "invalid ASCENT storage provider row" stored))
  (when check (check stored))
  (gerbil-ascent-admit-source-row! stored present all index count output-limit))

;; : (forall (a m b) (-> a m b Integer Integer Integer Integer))
;; gerbil-ascent-admit-source-row!
;;   : (-> ValidatedRow Membership RowsBuffer Nat Nat Nat Nat)
;;   | doc m%
;;       Materialize a source row after its caller's validation boundary.
;;       Checked initialization retains its shape/checker order. Direct
;;       admission requires validation with no intervening callback or extension.
;;       Duplicates retain their row identity and consume materialized budget.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-admit-source-row!
;;         '(1) (make-hash-table) (vector []) 0 0 8)
;;       ;; => 1, after the caller has validated the row
;;       ```
;;     %
(def (gerbil-ascent-admit-source-row! stored present all index count output-limit)
  (hash-put! present stored #t)
  (let (next-count (+ count 1))
    (when (> next-count output-limit)
      (error "ASCENT source fact budget exceeded"))
    (vector-set! all index (cons stored (vector-ref all index)))
    next-count))

;; : (forall (a m) (-> [a] Integer (Maybe (-> a Any)) m Integer Integer (Values [a] Integer)))
;; gerbil-ascent-prepare-storage-batch
;;   : (-> Rows Arity (Maybe RowChecker) Membership Nat Nat (Values Rows Nat))
;;   | doc m%
;;       Validate the complete provider expansion in order, retaining the first
;;       new row for each value. Only private list headers are mutated. Existing
;;       membership and provider list headers remain unchanged, even on failure.
;;       Budget rejection follows all row checks, before publication.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-prepare-storage-batch '((1) (1)) 1 #f (make-hash-table) 0 8)
;;       ;; => values '((1)) 1
;;       ```
;;     %
(def (gerbil-ascent-prepare-storage-batch expanded width check present count output-limit)
  (unless (list? expanded)
    (error "ASCENT storage provider returned non-list rows"))
  (let* ((batch-seen (and (pair? expanded) (pair? (cdr expanded))
                          (make-hash-table)))
         (accepted
          (with-list-builder (put!)
            (for-each
             (lambda (stored)
               (unless (and (list? stored) (= (length stored) width))
                 (error "invalid ASCENT storage provider row" stored))
               (when check (check stored))
               (unless (or (hash-get present stored)
                           (and batch-seen (hash-get batch-seen stored)))
                 (when batch-seen (hash-put! batch-seen stored #t))
                 (put! stored)))
             expanded)))
         ;; The private table contains exactly the accepted new rows. Empty
         ;; and singleton expansions do not need a second membership table.
         (added-count (if batch-seen (hash-length batch-seen)
                         (if (pair? accepted) 1 0))))
    (when (> (+ count added-count) output-limit)
      (error "ASCENT session output fact budget exceeded"))
    (values accepted added-count)))
