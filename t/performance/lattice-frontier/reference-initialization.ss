;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Initial source admission owns the engine's fresh row/state buffers.
(import :gerbil-ascent/core/relation-view
        (only-in :clan/poo/object .ref)
        (only-in :gerbil-ascent/program/admission gerbil-ascent-initialize-source-row!
                 gerbil-ascent-admit-source-row!)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-lattice-key
                 gerbil-ascent-lattice-value gerbil-ascent-joined-row)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-storage-engine-state
                 gerbil-ascent-storage-admit-state!
                 gerbil-ascent-canonical-set-storage-provider?
                 gerbil-ascent-canonical-view-storage-provider?
                 gerbil-ascent-storage-view-extension! gerbil-ascent-storage-freeze-view)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?))
(export make-initial-source-state gerbil-ascent-initialize-sources!)

;;; Private vectors are borrowed only during construction of one engine.
;;; The record names their roles; no mutable declaration or result is retained.
;; initial-source-state
;; : (forall (r n s h) (-> r r n n s h h (InitialSourceState r n s h)))
;; : (-> RowBuffers RowBuffers SizeBuffers SizeBuffers StorageStates Memberships LatticeRows InitialSourceState)
;; | doc m%
;;     Name the fresh engine's existing buffers for initial source admission.
;;     The carrier adds no copies, callbacks or shared public state.
;;
;;     # Examples
;;
;;     ```scheme
;;     (make-initial-source-state all delta all-size delta-size states seen keyed)
;;     ;; => a private carrier borrowing this engine's fresh buffers
;;     ```
;;   %
(defstruct initial-source-state
  (all delta all-size delta-size storage-states seen lattice-rows))

;; gerbil-ascent-initialize-sources!
;; : (forall (r s b) (-> r s b Natural Natural (Values Natural Natural)))
;; : (-> (List Relation) Schema InitialSourceState Natural Natural (Values Natural Natural))
;; | doc m%
;;     Admit source rows in declaration order into fresh engine-owned buffers.
;;     Preserve field checks, input/output limits, final lattice update order
;;     and complete native storage admission. Return input/materialized counts.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-initialize-sources! relations schema buffers 64 256)
;;     ;; => two values: admitted input and materialized source counts
;;     ```
;;   %
(def (gerbil-ascent-initialize-sources! relations schema buffers input-limit output-limit)
  (let ((names (vector-ref schema 1)) (arity (vector-ref schema 2))
        (field-checkers (vector-ref schema 3))
        (storage-extensions (vector-ref schema 6))
        (lattice-joins (vector-ref schema 7)) (kinds (vector-ref schema 8))
        (storage-providers (vector-ref schema 9))
        (all (initial-source-state-all buffers))
        (delta (initial-source-state-delta buffers))
        (all-size (initial-source-state-all-size buffers))
        (delta-size (initial-source-state-delta-size buffers))
        (storage-states (initial-source-state-storage-states buffers))
        (seen (initial-source-state-seen buffers))
        (lattice-rows (initial-source-state-lattice-rows buffers))
        (source-count 0) (source-materialized-count 0))
    (let initialize ((remaining relations) (index 0))
      (unless (null? remaining)
        (let* ((relation (car remaining))
               (name (vector-ref names index))
               (width (vector-ref arity index))
               (rows (.ref relation 'rows))
               (kind (vector-ref kinds index))
               (present (make-hash-table))
               (lattice-events []))
          (unless (list? rows)
            (error "invalid ASCENT relation rows" name rows))
          (when (eq? kind 'lattice)
            (vector-set! lattice-rows index (make-hash-table)))
          (when (eq? kind 'relation)
            (vector-set! storage-states index
              (gerbil-ascent-storage-engine-state
               (vector-ref storage-providers index))))
          (for-each
           (lambda (row)
             (unless (and (list? row) (= (length row) width))
               (error "invalid ASCENT relation row" name row))
             (let (check (vector-ref field-checkers index))
               (when check (check row)))
             (set! source-count (+ source-count 1))
             (when (or (> source-count input-limit)
                       (> source-count output-limit))
               (error "ASCENT source fact budget exceeded"))
             (if (eq? kind 'lattice)
               (let* ((key (gerbil-ascent-lattice-key row))
                      (keyed (vector-ref lattice-rows index))
                      (previous (hash-get keyed key))
                      (merged (if previous
                                (gerbil-ascent-joined-row
                                 key ((vector-ref lattice-joins index)
                                      (gerbil-ascent-lattice-value previous)
                                      (gerbil-ascent-lattice-value row)))
                                row)))
                 (let (check (vector-ref field-checkers index))
                   (when check (check merged)))
                 (hash-put! keyed key merged)
                 (unless previous
                   (set! source-materialized-count
                     (+ source-materialized-count 1)))
                 (set! lattice-events (cons key lattice-events)))
               ;; Initial duplicates remain rows; the exact built-in Set
               ;; extension only wraps this row in a temporary list.
               (cond
                ((and (gerbil-ascent-canonical-view-storage-provider? (vector-ref storage-providers index))
                      (gerbil-ascent-canonical-hash-index-provider? (vector-ref (vector-ref schema 5) index)))
                 (let (frontier (gerbil-ascent-storage-view-extension!
                                 (vector-ref storage-states index) row
                                 (- output-limit source-materialized-count)))
                   (let (check (vector-ref field-checkers index))
                     (when check (gerbil-ascent-for-each-row check frontier)))
                   (set! source-materialized-count (+ source-materialized-count (gerbil-ascent-row-count frontier)))
                   (gerbil-ascent-storage-admit-state! (vector-ref storage-states index))))
                ((gerbil-ascent-canonical-set-storage-provider?
                    (vector-ref storage-providers index))
                 (set! source-materialized-count
                   ;; With no field callback, nothing can invalidate the
                   ;; shape checked above. Exact Set storage returns row.
                   ;; Callback-bearing rows still cross the checked boundary.
                   (let (check (vector-ref field-checkers index))
                     (if check
                       (gerbil-ascent-initialize-source-row! row width check
                         present all index source-materialized-count output-limit)
                       (gerbil-ascent-admit-source-row! row present all index
                         source-materialized-count output-limit)))))
                (else
                 (let (materialized
                       ((vector-ref storage-extensions index)
                        (vector-ref storage-states index)
                        (vector-ref all index) [] row
                        (- output-limit source-materialized-count)))
                   (unless (list? materialized)
                     (error "ASCENT storage provider returned non-list rows"))
                   (for-each
                    (lambda (stored)
                      (set! source-materialized-count
                        (gerbil-ascent-initialize-source-row! stored width
                          (vector-ref field-checkers index) present all index
                          source-materialized-count output-limit)))
                    materialized)
                   (gerbil-ascent-storage-admit-state!
                    (vector-ref storage-states index)))))))
           rows)
          (when (and (gerbil-ascent-canonical-view-storage-provider? (vector-ref storage-providers index))
                     (gerbil-ascent-canonical-hash-index-provider? (vector-ref (vector-ref schema 5) index)))
            ;; Query planning follows source admission to preserve diagnostics.
            ;; Build only a frozen carrier here; routing is selected afterwards.
            (vector-set! all index (gerbil-ascent-storage-freeze-view (vector-ref storage-states index) #f)))
          (when (eq? kind 'lattice)
            (let ((keyed (vector-ref lattice-rows index))
                  (visited (make-hash-table))
                  (accepted []))
              ;; Source rows are already joined by key. Materialize each
              ;; final row once, in last-source-update order.
              (for-each
               (lambda (key)
                 (unless (hash-get visited key)
                   (hash-put! visited key #t)
                   (set! accepted (cons (hash-get keyed key) accepted))))
               lattice-events)
              (vector-set! all index (reverse accepted))))
          (vector-set! seen index present)
          (vector-set! delta index (vector-ref all index))
          (vector-set! all-size index (gerbil-ascent-row-count (vector-ref all index)))
          (vector-set! delta-size index
            (vector-ref all-size index))
          (initialize (cdr remaining) (+ index 1)))))
    (values source-count source-materialized-count)))
