;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Retained source snapshots, failure recovery, and timeout admission.
(import (only-in "source-snapshot.ss" gerbil-ascent-source-snapshot
                 gerbil-ascent-prepare-source-log-snapshot source-snapshot-program
                 source-snapshot-rows)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/mop validate)
        (only-in "types.ss" GerbilAscentSessionContract)
        (only-in "admission.ss" gerbil-ascent-check-replacement-rows!)
        (only-in "update-selection.ss" gerbil-ascent-update-eligible?)
        (only-in "evaluate.ss" gerbil-ascent-make-engine gerbil-ascent-make-updated-engine)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-canonical-set-storage-provider?))

(export gerbil-ascent-open-session
        gerbil-ascent-session-append-source!
        gerbil-ascent-session-replace-source!
        gerbil-ascent-session-replace-sources!
        gerbil-ascent-session-run
        gerbil-ascent-session-run-timeout)

(def Session. (.ref GerbilAscentSessionContract 'proto))

;;; A retained session owns accepted source snapshots outside the mutable
;;; engine, allowing failed provider updates to rebuild from committed input.
(def (gerbil-ascent-open-session program
                                 measure-rule-times?: (measure-rule-times? #f))
  (unless (boolean? measure-rule-times?)
    (error "invalid ASCENT rule timing option" measure-rule-times?))
  (def (copy-source-rows rows)
    ;; Own both the outer list and every row pair before an engine can observe
    ;; them. Nested host values remain shared and need a separate contract.
    (unless (list? rows) (error "invalid ASCENT source rows" rows))
    (map (lambda (row)
           (unless (list? row) (error "invalid ASCENT source row" row))
           (map identity row))
         rows))
  ;; A Provider may mutate its private state before returning an invalid
  ;; batch or raising. Keep the accepted source snapshot outside the engine
  ;; so a failed operation can rebuild all evaluation-local state from it.
  (let* ((relations (.ref program 'relations))
         (initial-relations
          (map (lambda (relation)
                 (.o (:: @ relation)
                     rows: (copy-source-rows (.ref relation 'rows))))
               relations))
         (initial-program (.o (:: @ program) relations: initial-relations))
         (source-snapshot (gerbil-ascent-source-snapshot initial-program))
         (single-relation-name
          (and (pair? relations) (null? (cdr relations))
               (.ref (car relations) 'name)))
         (positions (make-hash-table-eq))
         (initial (list->vector
                   (map (lambda (relation)
                          (cons (.ref relation 'rows) []))
                        initial-relations)))
         ;; A Set append can flush buffered sources in every Set relation.
         ;; Custom index extension may mutate before raising, even when the
         ;; triggering append targets a relation with native indexes.
         (safe-set-flush?
          (andmap (lambda (relation)
                    (or (eq? (.ref relation 'storage-kind) 'lattice)
                        (not (gerbil-ascent-canonical-set-storage-provider?
                              (.ref relation 'storage-provider)))
                        (gerbil-ascent-canonical-hash-index-provider?
                         (.ref relation 'index-provider))))
                  relations))
         (atomic-appends
          (list->vector
           (map (lambda (relation)
                  (or (eq? (.ref relation 'storage-kind) 'lattice)
                      (and safe-set-flush?
                           (gerbil-ascent-canonical-set-storage-provider?
                            (.ref relation 'storage-provider)))))
                relations)))
         (direct-appends?
          (andmap (lambda (safe?) safe?)
                  (vector->list atomic-appends)))
         (pending (list->vector (vector->list initial)))
         (committed (list->vector (vector->list initial)))
         (committed-result #f)
         (initialized? #f)
         (clean? #f)
         (partial? #f)
         (replay-on-timeout? #f)
         (replacement-active? #f)
         (last-result #f)
         (engine (gerbil-ascent-make-engine initial-program #t #f #f
                                          measure-rule-times?))
         (engine-analysis (.ref engine '.analysis))
         (engine-schema (.ref engine '.schema))
         (engine-base-rows
          (list->vector (map (lambda (relation) (.ref relation 'rows))
                             initial-relations)))
         (engine-append (.ref engine '.append-source!))
         (engine-additions (.ref engine '.source-additions))
         (engine-overrides (.ref engine '.source-overrides)))
    (for-each
     (lambda (relation index)
       (hash-put! positions (.ref relation 'name) (+ index 1)))
     relations (iota (length relations)))
    (def (snapshot-copy rows)
      ;; Each accepted snapshot owns its source-log headers. Row spines remain
      ;; persistent, so later appends cannot change a committed snapshot.
      ;; Nested host values are shared: immutability of admitted row values is
      ;; a separate premise, especially for opaque callbacks and providers.
      (vector-map (lambda (state) (cons (car state) (cdr state))) rows))
    (def (copy-append-row index name row)
      ;; Validate shape before copying; the engine still owns the one field
      ;; callback check and the fact-budget check on this captured row.
      (unless (and (list? row)
                   (= (length row) (vector-ref (vector-ref engine-schema 2) index)))
        (error "invalid ASCENT session source row" name row))
      (map (lambda (value) value) row))
    (def (engine-source-snapshot)
      (list->vector
       (map (lambda (index)
              (let (replacement (vector-ref engine-overrides index))
                (if replacement
                  (cons replacement [])
                  (cons (vector-ref engine-base-rows index)
                        (vector-ref engine-additions index)))))
            (iota (length relations)))))
    (def (position-of name)
      (if (and single-relation-name (eq? name single-relation-name))
        0
        (let (slot (hash-get positions name))
          (unless slot (error "unknown ASCENT relation" name))
          (- slot 1))))
    ;; Source-only snapshots retain the admitted immutable declarations.
    ;; Replacement checks shape/types before publication, and the fresh native
    ;; engine rechecks every materialized row and all original fact budgets.
    (def (prepare-source-cut rows)
      (gerbil-ascent-prepare-source-log-snapshot source-snapshot rows))
    (def (restore! rows)
      (set! engine #f)
      (let* ((cut (prepare-source-cut rows))
             (candidate (source-snapshot-program cut))
             (fresh (gerbil-ascent-make-engine candidate #t
                                              engine-analysis engine-schema
                                              measure-rule-times?))
             (restored-result (and initialized? ((.ref fresh '.run)))))
        (adopt-engine! fresh cut)
        (set! pending (snapshot-copy rows))
        (set! partial? #f)
        (set! clean? (and initialized?
                          (equal? (vector->list rows)
                                  (vector->list committed))))
        (set! replay-on-timeout? (and initialized? (not clean?)))
        (when clean?
          (set! last-result (or committed-result restored-result)))))
    (def (adopt-engine! fresh cut)
      (set! source-snapshot cut)
      (set! engine fresh)
      (set! replay-on-timeout? #f)
      (set! engine-append (.ref fresh '.append-source!))
      (set! engine-additions (.ref fresh '.source-additions))
      (set! engine-overrides (.ref fresh '.source-overrides))
      (set! engine-base-rows (source-snapshot-rows cut)))
    (def (attempt thunk)
      (with-catch
       (lambda (failure) (vector #f failure))
       (lambda () (vector #t (thunk)))))
    (def (recover! rows failure)
      (let (restored (attempt (lambda () (restore! rows))))
        (unless (vector-ref restored 0)
          (restore! committed)))
      (raise failure))
    (def (record-append! index source-state)
      (let (replacement (vector-ref engine-overrides index))
        (if replacement
          (begin
            (set-car! source-state replacement)
            (set-cdr! source-state []))
          (set-cdr! source-state
            (vector-ref engine-additions index))))
      (set! clean? #f))
    (def (check-idle!)
      (when replacement-active?
        (error "ASCENT session operation during replacement validation")))
    (def (append-source! name row)
      (check-idle!)
      (when partial?
        (error "finish ASCENT partial run before changing sources"))
      (let* ((index (position-of name))
             (source-state (vector-ref pending index))
             (owned-row (copy-append-row index name row)))
        (if (vector-ref atomic-appends index)
          (begin
           (engine-append name owned-row)
           (record-append! index source-state))
          (with-catch
           (lambda (failure)
             (recover! pending failure))
           (lambda ()
             (engine-append name owned-row)
             (record-append! index source-state))))))
    (def (direct-append-source! name row)
      (check-idle!)
      (when partial?
        (error "finish ASCENT partial run before changing sources"))
      (let* ((index (position-of name))
             (owned-row (copy-append-row index name row)))
        (engine-append name owned-row))
      (set! clean? #f))
    (def (replace-source! name rows)
      (check-idle!)
      (when partial?
        (error "finish ASCENT partial run before changing sources"))
      ;; Opaque providers retain the deferred single-source update contract:
      ;; their next zero-duration run must observe unfinished work. Only the
      ;; checked native subset can publish dependency invalidation here.
      ;; Eligibility depends only on the original declarations. The batch
      ;; transaction validates replacement rows before constructing its one
      ;; prospective program and computing authoritative dependency closure.
      (if (and initialized? clean? (gerbil-ascent-update-eligible? program))
          (let ((previous-committed committed)
                (previous-result committed-result))
            (replace-sources! (list (cons name rows)))
            ;; Single-source validation remains provisional until run. Its
            ;; completed validation result can serve an unrestricted run,
            ;; but a timed run must still expose committed round boundaries.
            (set! committed previous-committed)
            (set! committed-result previous-result)
            (set! last-result previous-result)
            (set! clean? #f)
            (set! replay-on-timeout? #t)
            (void))
          (let* ((index (position-of name))
             (source-state (vector-ref pending index))
             ;; Opaque replacement must own the same source spines as the
             ;; native batch path before any eager result can retain them.
             (owned-rows (copy-source-rows rows))
             (outcome
              (attempt
               (lambda ()
                 ((.ref engine '.replace-source!) name owned-rows)
                 (vector-set! pending index (cons owned-rows []))))))
        (unless (vector-ref outcome 0)
          (vector-set! pending index source-state)
          (recover! pending (vector-ref outcome 1)))
        (set! clean? #f)
        (vector-ref outcome 1))))
    ;;; Invalidate dependent relations and solve a prospective source snapshot before
    ;;; changing the retained engine. A failed batch leaves both the last
    ;;; completed result and its source state available for later updates.
    (def (replace-sources! replacements (accept-result #f))
      (check-idle!)
      (unless (or (not accept-result) (procedure? accept-result))
        (error "invalid ASCENT replacement acceptance procedure"))
      (dynamic-wind
        (lambda () (set! replacement-active? #t))
        (lambda () (replace-sources/idle! replacements accept-result))
        (lambda () (set! replacement-active? #f))))
    (def (replace-sources/idle! replacements accept-result)
      (unless (and initialized? clean?)
        (error "batch replacement requires a completed clean session"))
      (unless (list? replacements)
        (error "batch replacements must be a list" replacements))
      (when (null? replacements)
        (error "batch replacement requires at least one source"))
      (let ((prospective (snapshot-copy committed))
            (seen (make-hash-table-eq)))
        (for-each
         (lambda (replacement)
           (unless (and (pair? replacement)
                        (symbol? (car replacement)))
             (error "invalid source replacement" replacement))
           (let* ((name (car replacement))
                  (index (position-of name)))
             (when (hash-get seen name)
               (error "duplicate batch source" name))
             (hash-put! seen name #t)
             (gerbil-ascent-check-replacement-rows!
              name (cdr replacement) (vector-ref (vector-ref engine-schema 2) index)
              (vector-ref (vector-ref engine-schema 3) index))
             (vector-set! prospective index
                          (cons (copy-source-rows (cdr replacement)) []))))
         replacements)
        (let* ((cut (prepare-source-cut prospective))
               (candidate (source-snapshot-program cut))
               (fresh (gerbil-ascent-make-updated-engine
                       committed candidate committed-result
                       engine-analysis engine-schema measure-rule-times? cut
                       (and engine ((.ref engine '.native-publication)))))
               (result ((.ref fresh '.run))))
          (unless (.ref result 'finished)
            (error "batch source replacement did not complete"))
          ;; A trusted owner checks evidence against this completed prospective
          ;; result before any retained source or engine is published. Reentrant
          ;; Session operations are rejected for the whole transaction.
          (when (and accept-result (not (eq? #t (accept-result result))))
            (error "ASCENT replacement result was not accepted"))
          (adopt-engine! fresh cut)
          (set! pending (snapshot-copy prospective))
          (set! committed (snapshot-copy prospective))
          (set! last-result result)
          (set! committed-result result)
          (set! clean? #t)
          (set! partial? #f)
          result)))
    (def (run!)
      (check-idle!)
      (if clean?
        last-result
        (let* ((next-pending
                (if direct-appends? (engine-source-snapshot) pending))
               (outcome (attempt (lambda () ((.ref engine '.run))))))
          (unless (vector-ref outcome 0)
            (recover! committed (vector-ref outcome 1)))
          (set! initialized? #t)
          (set! pending next-pending)
          (set! committed (snapshot-copy next-pending))
          (set! last-result (vector-ref outcome 1))
          (set! committed-result last-result)
          (set! clean? #t)
          (set! partial? #f)
          (set! replay-on-timeout? #f)
          last-result)))
    (def (run-timeout! duration-nanoseconds)
      (check-idle!)

      (unless (and (exact-integer? duration-nanoseconds)
                   (>= duration-nanoseconds 0))
        (error "invalid ASCENT timeout in nanoseconds"
               duration-nanoseconds))
      (if clean?
        last-result
        (let* ((next-pending
                (if direct-appends? (engine-source-snapshot) pending))
               (outcome
                (attempt
                 (lambda ()
                   ;; Replacement and nonpositive updates validate eagerly.
                   ;; A timeout must still run the accepted source through
                   ;; committed round boundaries rather than return that
                   ;; already-complete validation snapshot.
                   (when (or replay-on-timeout?
                             ((.ref engine '.recomputed?)))
                     (let* ((cut (prepare-source-cut next-pending))
                            (candidate (source-snapshot-program cut))
                            (fresh
                             (gerbil-ascent-make-engine
                              candidate #t engine-analysis engine-schema
                              measure-rule-times?)))
                       (adopt-engine! fresh cut)))
                   ((.ref engine '.run-timeout) duration-nanoseconds)))))
          (unless (vector-ref outcome 0)
            (recover! committed (vector-ref outcome 1)))

          (let (result (vector-ref outcome 1))
            (set! last-result result)
            (set! pending next-pending)
            (if (.ref result 'finished)
              (begin
                (set! initialized? #t)
                (set! committed (snapshot-copy next-pending))
                (set! committed-result result)
                (set! clean? #t)
                (set! partial? #f))
              (set! partial? #t))
            result))))
    (validate GerbilAscentSessionContract
              (.o (:: @ Session.)
                  (.append-source!
                   (if direct-appends? direct-append-source!
                       append-source!))
                  (.replace-source! replace-source!)
                  (.replace-sources! replace-sources!)
                  (.run run!)
                  (.run-timeout run-timeout!)))))

(def (gerbil-ascent-session-append-source! session name row)
  ((.ref session '.append-source!) name row))

(def (gerbil-ascent-session-replace-source! session name rows)
  ((.ref session '.replace-source!) name rows))

(def (gerbil-ascent-session-replace-sources! session replacements (accept-result #f))
  (if accept-result
    ((.ref session '.replace-sources!) replacements accept-result)
    ((.ref session '.replace-sources!) replacements)))

(def (gerbil-ascent-session-run session)
  ((.ref session '.run)))

(def (gerbil-ascent-session-run-timeout session duration-nanoseconds)
  ((.ref session '.run-timeout) duration-nanoseconds))
