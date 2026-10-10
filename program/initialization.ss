;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Initial source admission owns the engine's fresh row/state buffers.
(import :gerbil-ascent/core/relation-view
        (only-in :clan/poo/object .ref)
        (only-in "lattice-frontier.ss" make-lattice-frontier lattice-frontier-stage!
                 lattice-frontier-rows)
        (only-in "admission.ss" gerbil-ascent-initialize-source-row!)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-lattice-key
                 gerbil-ascent-lattice-value gerbil-ascent-joined-row)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-storage-engine-state
                 gerbil-ascent-storage-admit-state!
                 gerbil-ascent-canonical-set-storage-provider?
                 gerbil-ascent-canonical-view-storage-provider?
                 gerbil-ascent-storage-view-extension! gerbil-ascent-storage-freeze-view)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?))
(export make-initial-source-state gerbil-ascent-initialize-sources!)

;;; Callback traversal must read the next list node after materialization.
;;; A pure Set can use the native fold's functional occurrence count instead.
;; : (forall (r) (-> AdmissionMode [r] (AdmissionBindings r) (-> r Void) (U Natural Void)))
;; : (-> AdmissionMode SourceRows AdmissionBindings MaterializationSyntax (U Natural Void))
;; | doc m%
;;     Expand ordered checks before the selected materialization algorithm.
;;     The pure form returns a count through foldl without a checker closure.
;;     The callbacks form preserves for-each traversal and runtime checker state.
;;
;;     # Examples
;;
;;     ```scheme
;;     (source-admission-loop pure rows
;;       (row name width count input-limit output-limit) (admit! row))
;;     ;; => final accepted source count, for exact Set without callbacks
;;     ```
;;   %
(defrules source-admission-loop (pure callbacks)
  ((_ pure rows (row name width source-count input-limit output-limit) body ...)
   (foldl
    (lambda (row source-count)
      (unless (and (list? row) (= (length row) width))
        (error "invalid ASCENT relation row" name row))
      (let (next-count (+ source-count 1))
        (when (or (> next-count input-limit) (> next-count output-limit))
          (error "ASCENT source fact budget exceeded"))
        body ...
        next-count))
    source-count rows))
  ((_ callbacks rows (row check-source!) body ...)
   (for-each (lambda (row) (check-source! row) body ...) rows)))

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
  (all delta all-size delta-size storage-states seen lattice-rows) final: #t)

;; gerbil-ascent-initialize-sources!
;; : (forall (r s b) (-> [r] s b Natural Natural (Values Natural Natural)))
;; : (-> [Relation] Schema InitialSourceState Natural Natural (Values Natural Natural))
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
  (using (buffers :- initial-source-state)
   (let ((names (vector-ref schema 1)) (arity (vector-ref schema 2))
        (field-checkers (vector-ref schema 3))
        (storage-extensions (vector-ref schema 6))
        (lattice-joins (vector-ref schema 7)) (kinds (vector-ref schema 8))
        (storage-providers (vector-ref schema 9))
        (all buffers.all)
        (delta buffers.delta)
        (all-size buffers.all-size)
        (delta-size buffers.delta-size)
        (storage-states buffers.storage-states)
        (seen buffers.seen)
        (lattice-rows buffers.lattice-rows)
        (source-count 0) (source-materialized-count 0))
    (let (index 0)
      (for-each
       (lambda (relation)
        (let* ((name (vector-ref names index))
               (width (vector-ref arity index))
               (rows (.ref relation 'rows))
               (kind (vector-ref kinds index))
               (check (vector-ref field-checkers index))
               (provider (vector-ref storage-providers index))
               (set-storage? (gerbil-ascent-canonical-set-storage-provider? provider))
               (native-set? (and (eq? kind 'relation) set-storage? (not check)))
               ;; Allocate this effectful checker only for callback paths.
               (check-source!
                (and (not native-set?)
                     (lambda (row)
                       (unless (and (list? row) (= (length row) width))
                         (error "invalid ASCENT relation row" name row))
                       (when check (check row))
                       (set! source-count (+ source-count 1))
                       (when (or (> source-count input-limit) (> source-count output-limit))
                         (error "ASCENT source fact budget exceeded")))))
               (native-view?
                (and (gerbil-ascent-canonical-view-storage-provider? provider)
                     (gerbil-ascent-canonical-hash-index-provider?
                      (vector-ref (vector-ref schema 5) index))))
               (present (make-hash-table))
               (frontier #f))
          (unless (list? rows)
            (error "invalid ASCENT relation rows" name rows))
          (when (eq? kind 'lattice)
            (vector-set! lattice-rows index (make-hash-table)))
          (when (eq? kind 'relation)
            (vector-set! storage-states index
              (gerbil-ascent-storage-engine-state
               (vector-ref storage-providers index))))
          (cond
           ((eq? kind 'lattice)
            (source-admission-loop callbacks rows
              (row check-source!)
               (let* ((key (gerbil-ascent-lattice-key row))
                      (keyed (vector-ref lattice-rows index))
                      (previous (hash-get keyed key))
                      (merged (if previous
                                (gerbil-ascent-joined-row
                                 key ((vector-ref lattice-joins index)
                                      (gerbil-ascent-lattice-value previous)
                                      (gerbil-ascent-lattice-value row)))
                                row)))
                 (when check (check merged))
                 (hash-put! keyed key merged)
                 (unless previous
                   (set! source-materialized-count
                     (+ source-materialized-count 1)))
                 (unless frontier (set! frontier (make-lattice-frontier)))
                 ;; Source admission records every accepted occurrence, even
                 ;; when joining leaves its value equal to the previous row.
                 (lattice-frontier-stage! frontier key merged))))
           (native-view?
            (source-admission-loop callbacks rows
              (row check-source!)
                 (let (frontier (gerbil-ascent-storage-view-extension!
                                 (vector-ref storage-states index) row
                                 (- output-limit source-materialized-count)))
                   (when check (gerbil-ascent-for-each-row check frontier))
                   (set! source-materialized-count (+ source-materialized-count (gerbil-ascent-row-count frontier)))
                   (gerbil-ascent-storage-admit-state! (vector-ref storage-states index)))))
           (set-storage?
            ;; Callback-bearing rows cross the checked boundary a second time:
            ;; the first callback may have mutated their shape or field values.
            (if check
              (source-admission-loop callbacks rows
                (row check-source!)
                 (set! source-materialized-count
                   (gerbil-ascent-initialize-source-row! row width check
                     present all index source-materialized-count output-limit)))
              ;; Exact Set storage with no callbacks cannot replace or mutate
              ;; a validated row. Build its private reversed spine locally;
              ;; retain every duplicate and the original membership/budget order.
              (let (accepted (vector-ref all index))
                (set! source-count
              (source-admission-loop pure rows
                  (row name width source-count input-limit output-limit)
                  (hash-put! present row #t)
                  (set! source-materialized-count (+ source-materialized-count 1))
                  (when (> source-materialized-count output-limit)
                    (error "ASCENT source fact budget exceeded"))
                  (set! accepted (cons row accepted))))
                (vector-set! all index accepted))))
           (else
            (source-admission-loop callbacks rows
              (row check-source!)
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
                          check present all index
                          source-materialized-count output-limit)))
                    materialized)
                   (gerbil-ascent-storage-admit-state!
                    (vector-ref storage-states index))))))
          (when native-view?
            ;; Query planning follows source admission to preserve diagnostics.
            ;; Build only a frozen carrier here; routing is selected afterwards.
            (vector-set! all index (gerbil-ascent-storage-freeze-view (vector-ref storage-states index) #f)))
          (when (eq? kind 'lattice)
            (vector-set! all index (if frontier (lattice-frontier-rows frontier) [])))
          (vector-set! seen index present)
          (vector-set! delta index (vector-ref all index))
          (vector-set! all-size index (gerbil-ascent-row-count (vector-ref all index)))
          (vector-set! delta-size index
            (vector-ref all-size index))
          (set! index (+ index 1)))) relations))
    (values source-count source-materialized-count))))
