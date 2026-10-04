;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Initialization mutates only buffers owned by the constructing engine.
;;; Source multiplicity and row identity are preserved, including duplicates.
(export gerbil-ascent-initialize-source-row! gerbil-ascent-check-replacement-rows!)

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
  (hash-put! present stored #t)
  (let (next-count (+ count 1))
    (when (> next-count output-limit)
      (error "ASCENT source fact budget exceeded"))
    (vector-set! all index (cons stored (vector-ref all index)))
    next-count))
