;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Generic stratified semi-naive evaluator. Mutable row buffers belong to one
;;; session; public declarations and returned snapshots are POO values.
(import (only-in :clan/poo/object .o .ref object?)
        (only-in :clan/poo/mop validate)
        (only-in :std/iter for iter Iterator &Iterator-next!)
        (only-in :gerbil-ascent/program/admission gerbil-ascent-initialize-source-row!)
        (only-in :gerbil-ascent/program/planning gerbil-ascent-prepare-rule)
        (only-in :gerbil-ascent/program/types GerbilAscentSessionContract)
        (only-in :gerbil-ascent/program/analysis gerbil-ascent-program-analysis
                 gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/program/funs gerbil-ascent-rule-strata
                 gerbil-ascent-lattice-feeds-relation?
                 gerbil-ascent-delta-positions
                 gerbil-ascent-lattice-key
                 gerbil-ascent-lattice-value
                 gerbil-ascent-joined-row
                 gerbil-ascent-expression-value
                 gerbil-ascent-bind-row
                 gerbil-ascent-head-row)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-hash-index-provider
                 gerbil-ascent-index-provider-build
                 gerbil-ascent-index-provider-extend!
                 gerbil-ascent-index-provider-lookup)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-storage-make-state
                 gerbil-ascent-set-batch-admit!
                 gerbil-ascent-set-storage-provider)
        (only-in :clan/poo/support/base until))

(export gerbil-ascent-evaluate-program gerbil-ascent-make-engine)

(def Session. (.ref GerbilAscentSessionContract 'proto))

;;; One engine owns all mutable row buffers and indexes. Reused immutable
;;; analysis/schema values never share evaluation-local relation state.
;; gerbil-ascent-make-engine
;;   : (-> Program Boolean (Maybe Analysis) (Maybe Schema) Boolean Engine)
;;   | doc m%
;;       Construct a stratified evaluator for a program and an optional
;;       retained session. Timing observes rules without changing their rows.
;;
;;       # Examples
;;
;;       ```scheme
;;       (gerbil-ascent-make-engine program #f)
;;       ;; => an engine with one fresh evaluation state
;;       ```
;;     %
(def (gerbil-ascent-make-engine program session? (analysis-override #f)
                                (schema-override #f)
                                (measure-rule-times? #f)
                                (plan-error #f))
  ;; The declaration constructor validates the full Core contract.
  ;; Evaluation checks mutable rows and clause bindings for this snapshot.
  (unless (object? program)
    (error "invalid ASCENT program" program))
  (let* ((relations (.ref program 'relations))
         (rules (.ref program 'rules))
         (input-limit (.ref program 'max-input-facts))
         (derived-limit (.ref program 'max-derived-facts))
         (output-limit (.ref program 'max-output-facts)))
    (unless (and (list? relations) (list? rules)
                 (exact-integer? input-limit) (> input-limit 0)
                 (exact-integer? derived-limit) (> derived-limit 0)
                 (exact-integer? output-limit) (> output-limit 0)
                 (boolean? measure-rule-times?))
      (error "invalid ASCENT program bounds"))
    (let* ((count (length relations))
           (schema (or schema-override
                       (gerbil-ascent-program-schema program relations)))
           (names (vector-ref schema 1))
           (arity (vector-ref schema 2))
           (field-checkers (vector-ref schema 3))
           (positions (vector-ref schema 4))
           (all (make-vector count []))
           (delta (make-vector count []))
           (all-version (make-vector count 0))
           (delta-version (make-vector count 0))
           (all-size (make-vector count 0))
           (delta-size (make-vector count 0))
           (all-indexes (make-vector count #f))
           (delta-indexes (make-vector count #f))
           (index-providers (vector-ref schema 5))
           (storage-extensions (vector-ref schema 6))
           (storage-states (make-vector count #f))
           (seen (make-vector count #f))
           (lattice-joins (vector-ref schema 7))
           (kinds (vector-ref schema 8))
           (storage-providers (vector-ref schema 9))
           (lattice-rows (make-vector count #f))
           (source-count 0)
           (source-materialized-count 0)
           (derived-count 0))
      (def position-of
        (if (= count 1)
          (lambda (name)
            (if (eq? name (vector-ref names 0))
              0
              (error "unknown ASCENT relation" name)))
          (lambda (name)
            (let (slot (hash-get positions name))
              (unless slot (error "unknown ASCENT relation" name))
              (- slot 1)))))
      (def (term-kind term)
        (let (kind (.ref term 'kind))
          (unless (memq kind '(variable wildcard literal expression pattern))
            (error "invalid ASCENT rule term" kind))
          kind))
      (def (atom-plan atom)
        (unless (and (object? atom)
                     (memq (.ref atom 'ascent-clause-kind)
                           '(atom negation aggregate)))
          (error "invalid ASCENT atom declaration" atom))
        (let* ((index (position-of (.ref atom 'relation)))
               (terms (.ref atom 'terms)))
          (unless (and (list? terms) (= (length terms) (vector-ref arity index)))
            (error "ASCENT atom arity mismatch" (.ref atom 'relation)))
          (vector index
                  (map (lambda (term)
                         (cons (term-kind term) (.ref term 'value)))
                       terms))))
      (def (indexed-rows atom environment use-delta?)
        (let* ((index (vector-ref atom 0))
               (columns (vector-ref atom 2))
               (rows (vector-ref (if use-delta? delta all) index)))
          (if (or (null? columns)
                  (< (vector-ref (if use-delta? delta-size all-size)
                                 index)
                     32))
            rows
            (let* ((caches (if use-delta? delta-indexes all-indexes))
                   (cache
                    (or (vector-ref caches index)
                        (let (fresh (make-hash-table))
                          (vector-set! caches index fresh)
                          fresh)))
                   (version (vector-ref
                             (if use-delta? delta-version all-version)
                             index))
                   (entry (hash-get cache columns))
                   (lookup
                    (if (and entry (= (car entry) version))
                      (cdr entry)
                      (let (built (gerbil-ascent-index-provider-build
                                   (vector-ref index-providers index)
                                   rows columns))
                        (hash-put! cache columns (cons version built))
                        built)))
                   (terms (vector-ref atom 1))
                   (key (map
                         (lambda (column)
                           (let (term (list-ref terms column))
                             (case (car term)
                               ((literal) (cdr term))
                               ((expression)
                                (gerbil-ascent-expression-value
                                 (cdr term) environment))
                               (else
                                (let (bound (assq (cdr term) environment))
                                  (unless bound
                                    (error "unbound ASCENT index variable"
                                           (cdr term)))
                                  (cdr bound))))))
                         columns)))
              (let (matched
                    (gerbil-ascent-index-provider-lookup
                     (vector-ref index-providers index) lookup key))
                (unless (list? matched)
                  (error "ASCENT index provider returned non-list rows"
                         matched))
                matched)))))
      (def (advance-all-indexes! index new-rows)
        (let (cache (vector-ref all-indexes index))
          (when (and cache (pair? new-rows))
            (let ((version (vector-ref all-version index))
                  (provider (vector-ref index-providers index)))
              (hash-for-each
               (lambda (columns entry)
                 (when (= (car entry) version)
                   (hash-put! cache columns
                     (cons (+ version 1)
                           (gerbil-ascent-index-provider-extend!
                            provider (cdr entry) new-rows columns)))))
               cache)))))
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
                (gerbil-ascent-storage-make-state
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
                 (if (eq? (vector-ref storage-providers index)
                          gerbil-ascent-set-storage-provider)
                   (set! source-materialized-count
                     (gerbil-ascent-initialize-source-row! row width
                       (vector-ref field-checkers index) present all index
                       source-materialized-count output-limit))
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
                      materialized)))))
             rows)
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
            (vector-set! all-size index (length (vector-ref all index)))
            (vector-set! delta-size index
              (vector-ref all-size index))
            (initialize (cdr remaining) (+ index 1)))))
      ;; Engine-local metadata keeps the shared immutable analysis layout
      ;; unchanged, including when a retained engine reuses that analysis.
      (def (prunable-prefix body)
        (if (and (pair? body) (eq? (vector-ref (car body) 0) 'atom))
          (let (atom (vector-ref (car body) 1))
            (cons (vector-ref atom 0)
                  (if (and (null? (vector-ref atom 2))
                           (andmap (lambda (term)
                                     (eq? (car term) 'variable))
                                   (vector-ref atom 1)))
                    (prunable-prefix (cdr body)) [])))
          []))
      (let* ((analysis
              ;; Source-only replacement preserves declarations and rules.
              ;; Its session reuses this immutable rule plan while the fresh
              ;; engine still owns new rows, indexes, storage and budgets.
              (or analysis-override
                  (gerbil-ascent-program-analysis
                   program relations rules
                   (lambda ()
                     (let (plans
                           (map
                            (lambda (rule index)
                              (gerbil-ascent-prepare-rule
                               rule index atom-plan plan-error))
                            rules (iota (length rules))))
                       (let* ((strata
                               (with-catch
                                (lambda (failure)
                                  (when plan-error
                                    (plan-error '(program dependencies)
                                                failure))
                                  (raise failure))
                                (lambda ()
                                  (gerbil-ascent-rule-strata
                                   plans count kinds))))
                              (highest (if (= count 0) -1
                                         (apply max (vector->list strata))))
                              (active (make-vector (+ highest 1) [])))
                         (let plan-stratum ((stratum 0))
                           (when (<= stratum highest)
                             (let (selected
                                   (filter-map
                                    (lambda (rule)
                                      (let (heads
                                            (filter
                                             (lambda (head)
                                               (= (vector-ref strata
                                                              (vector-ref head 0))
                                                  stratum))
                                             (vector-ref rule 0)))
                                        (and (pair? heads)
                                             (vector
                                              heads (vector-ref rule 1)
                                              (gerbil-ascent-delta-positions
                                               (vector-ref rule 1) strata
                                               stratum)
                                              (vector-ref rule 3)))))
                                    plans))
                               (vector-set! active stratum selected)
                               (plan-stratum (+ stratum 1)))))
                         (vector relations rules plans strata active)))))))
             (rule-plans (vector-ref analysis 2))
             (rule-ticks (and measure-rule-times?
                              (make-vector (length rules) 0)))
             (strata (vector-ref analysis 3))
             (active-by-stratum
              (vector-map
               (lambda (rules)
                 (map (lambda (rule)
                        (vector (vector-ref rule 0) (vector-ref rule 1)
                                (vector-ref rule 2) (vector-ref rule 3)
                                (list->vector
                                 (prunable-prefix (vector-ref rule 1)))))
                      rules))
               (vector-ref analysis 4)))
             (highest-stratum (- (vector-length active-by-stratum) 1))
             (lattice-feeds-relation?
              (and session?
                   (gerbil-ascent-lattice-feeds-relation?
                    rule-plans kinds)))
             (positive-rules?
              (and session?
                   (andmap
                    (lambda (rule)
                      (andmap (lambda (clause)
                                (eq? (vector-ref clause 0) 'atom))
                              (vector-ref rule 1)))
                    rule-plans)))
             (single-set-source?
              (and positive-rules? (= count 1)
                   (not (vector-ref lattice-joins 0))
                   (eq? (vector-ref storage-providers 0)
                        gerbil-ascent-set-storage-provider)))
             (source-originals
              (and session?
                   (list->vector
                    (map (lambda (relation) (.ref relation 'rows))
                         relations))))
             (source-additions (and session? (make-vector count [])))
             (staged-set-counts (and session? (make-vector count 0)))
             (staged-total 0)
             (source-overrides (and session? (make-vector count #f)))
             (recompute-from-source? #f)
             (resume-stratum #f)
             (resume-round 0)
             (materialized-dirty? #f)
             (first-run? #t)
             (dirty? #t)
             (last-result #f))
        (def (source-rows-at index)
          (or (vector-ref source-overrides index)
              (append (vector-ref source-originals index)
                      (reverse (vector-ref source-additions index)))))
        (def (source-program-with index replacement)
          (let (next-relations
                (map (lambda (relation position)
                       (let (source-rows
                             (if (= position index)
                               replacement
                               (source-rows-at position)))
                         (.o (:: @ relation) rows: source-rows)))
                     relations (iota count)))
            (.o (:: @ program) relations: next-relations)))
        (def (append-set-source! index row)
          ;; A Set source is buffered in its persistent recovery log; the
          ;; fixed-point boundary admits the whole batch exactly once.
          (when (> (+ source-materialized-count derived-count
                      staged-total 1)
                   output-limit)
            (flush-staged-set-rows!))
          (when (and (>= (+ source-materialized-count derived-count)
                         output-limit)
                     (not (hash-get (vector-ref seen index) row)))
            (error "ASCENT session output fact budget exceeded"))
          (set! source-count (+ source-count 1))
          (vector-set! source-additions index
            (cons row (vector-ref source-additions index)))
          (vector-set! staged-set-counts index
            (+ 1 (vector-ref staged-set-counts index)))
          (set! staged-total (+ staged-total 1))
          (set! dirty? #t))
        (def (append-source! name row)
          (when first-run?
            (error "ASCENT session must run before source updates"))
          (let* ((index (position-of name))
                 (width (vector-ref arity index))
                 (built-in-set?
                  (eq? (vector-ref storage-providers index)
                       gerbil-ascent-set-storage-provider)))
            (unless (and (list? row) (= (length row) width))
              (error "invalid ASCENT session source row" name row))
            (let (check (vector-ref field-checkers index))
              (when check (check row)))
            (when (>= source-count input-limit)
              (error "ASCENT session input fact budget exceeded"))
            (cond
             ((or (not positive-rules?)
                  lattice-feeds-relation?
                  recompute-from-source?
                  (vector-ref lattice-joins index))
              ;; Negation, aggregation, and lattice-to-relation projections
              ;; can invalidate prior rows. Re-evaluate the accepted source
              ;; snapshot before publishing a changed fixed point.
              (let* ((replacement
                      (append (source-rows-at index) (list row)))
                     (candidate (source-program-with index replacement))
                     (result ((gerbil-ascent-make-engine
                               candidate #f analysis schema
                               measure-rule-times?))))
                (set! source-count (+ source-count 1))
                (vector-set! source-overrides index replacement)
                (vector-set! source-additions index [])
                (set! recompute-from-source? #t)
                (set! dirty? #f)
                (set! last-result result)))
             (else
              (if built-in-set?
                (append-set-source! index row)
              (begin
                (flush-staged-set-rows!)
                (let* ((expanded
                    ((vector-ref storage-extensions index)
                     (vector-ref storage-states index)
                     (vector-ref all index)
                     (vector-ref delta index) row
                     (- output-limit
                        (+ source-materialized-count derived-count))))
                   (batch-seen
                    (and (pair? expanded) (pair? (cdr expanded))
                         (make-hash-table)))
                   (new-rows []))
              (unless (list? expanded)
                (error "ASCENT storage provider returned non-list rows"))
              ;; Validate the complete Provider batch before changing the
              ;; evaluator's retained session, including its input counter.
              (for-each
               (lambda (stored)
                 (unless (and (list? stored) (= (length stored) width))
                   (error "invalid ASCENT storage provider row" stored))
                 (let (check (vector-ref field-checkers index))
                   (when check (check stored)))
                 (unless (or (hash-get (vector-ref seen index) stored)
                             (and batch-seen (hash-get batch-seen stored)))
                   (when batch-seen (hash-put! batch-seen stored #t))
                   (set! new-rows (cons stored new-rows))))
               expanded)
              (set! new-rows (reverse new-rows))
              (let (added-count (length new-rows))
                (when (> (+ source-materialized-count derived-count
                            added-count) output-limit)
                  (error "ASCENT session output fact budget exceeded"))
                (set! source-count (+ source-count 1))
                (for-each
                 (lambda (stored)
                   (hash-put! (vector-ref seen index) stored #t)
                   (set! source-materialized-count
                     (+ source-materialized-count 1))
                   (vector-set! all index
                     (cons stored (vector-ref all index)))
                   (vector-set! delta index
                     (cons stored (vector-ref delta index))))
                 new-rows)
                (when (pair? new-rows)
                  (set! dirty? #t)
                  (set! materialized-dirty? #t)
                  (advance-all-indexes! index new-rows)
                  (vector-set! all-size index
                    (+ (vector-ref all-size index) added-count))
                  (vector-set! delta-size index
                    (+ (vector-ref delta-size index) added-count))
                  (vector-set! all-version index
                    (+ 1 (vector-ref all-version index)))
                  (vector-set! delta-version index
                    (+ 1 (vector-ref delta-version index))))))))))
            (unless (or (vector-ref source-overrides index)
                        built-in-set?)
              (vector-set! source-additions index
                (cons row (vector-ref source-additions index))))))
        (def (append-single-set-source! name row)
          (if recompute-from-source?
            (append-source! name row)
            (begin
              (when first-run?
                (error "ASCENT session must run before source updates"))
              (unless (eq? name (vector-ref names 0))
                (error "unknown ASCENT relation" name))
              (unless (and (list? row)
                           (= (length row) (vector-ref arity 0)))
                (error "invalid ASCENT session source row" name row))
              (let (check (vector-ref field-checkers 0))
                (when check (check row)))
              (when (>= source-count input-limit)
                (error "ASCENT session input fact budget exceeded"))
              (append-set-source! 0 row))))
        (def (replace-source! name rows)
          (when first-run?
            (error "ASCENT session must run before source updates"))
          (let* ((index (position-of name))
                 (width (vector-ref arity index)))
            (unless (list? rows)
              (error "invalid ASCENT replacement source rows" name rows))
            (for-each
             (lambda (row)
               (unless (and (list? row) (= (length row) width))
                 (error "invalid ASCENT replacement source row" name row))
               (let (check (vector-ref field-checkers index))
                 (when check (check row))))
             rows)
            (let (next-count
                  (+ (- source-count (length (source-rows-at index)))
                     (length rows)))
              (when (> next-count input-limit)
                (error "ASCENT session input fact budget exceeded"))
              (let* ((candidate (source-program-with index rows))
                     (result ((gerbil-ascent-make-engine
                               candidate #f analysis schema
                               measure-rule-times?))))
                (set! source-count next-count)
                (vector-set! source-overrides index rows)
                (vector-set! source-additions index [])
                (set! recompute-from-source? #t)
                (set! dirty? #f)
                (set! last-result result)))))
        (def (flush-staged-set-rows!)
          (when session?
            (let (accepted-any? #f)
             (let flush ((index 0))
              (when (< index count)
                (let (staged-count (vector-ref staged-set-counts index))
                  (when (> staged-count 0)
                    (let-values (((accepted present)
                                  (gerbil-ascent-set-batch-admit!
                                   (vector-ref source-additions index)
                                   staged-count
                                   (vector-ref seen index)
                                   (and (null? (vector-ref all index))
                                        (null? (vector-ref source-originals
                                                           index))))))
                      (vector-set! seen index present)
                      (when (pair? accepted)
                        (set! accepted-any? #t)
                        (set! materialized-dirty? #t)
                        (let* ((new-count (length accepted))
                               (old-all (vector-ref all index))
                               (old-delta (vector-ref delta index))
                               (shared-tail? (eq? old-all old-delta))
                               (new-delta
                                (and (not shared-tail?)
                                     (append accepted old-delta))))
                          (when (vector-ref all-indexes index)
                            (advance-all-indexes! index (reverse accepted)))
                          (let (new-all (append! accepted old-all))
                            (vector-set! all index new-all)
                            (vector-set! delta index
                              (if shared-tail? new-all new-delta)))
                          (set! source-materialized-count
                            (+ source-materialized-count new-count))
                          (vector-set! all-size index
                            (+ (vector-ref all-size index) new-count))
                          (vector-set! delta-size index
                            (+ (vector-ref delta-size index) new-count))
                          (vector-set! all-version index
                            (+ 1 (vector-ref all-version index)))
                          (vector-set! delta-version index
                            (+ 1 (vector-ref delta-version index))))))
                    (vector-set! staged-set-counts index 0)))
                (flush (+ index 1))))
             (set! staged-total 0)
             (when (and (not first-run?)
                        (not materialized-dirty?)
                        (not accepted-any?))
               (set! dirty? #f)))))
        (def (run-retained! (deadline #f))
         (when dirty? (flush-staged-set-rows!))
         (let (complete? #t)
         (when dirty?
         (call/cc
          (lambda (return)
         (let evaluate-stratum ((stratum (or resume-stratum 0)))
          (when (<= stratum highest-stratum)
            (let ((active-rules (vector-ref active-by-stratum stratum))
                  (active? #t) (round (if resume-stratum resume-round 0)))
              (unless resume-stratum
              (let reset-delta ((index 0))
                (when (< index count)
                  (vector-set! delta index
                    (if (= (vector-ref strata index) stratum)
                      (if (or first-run? (> stratum 0))
                        (vector-ref all index)
                        (vector-ref delta index))
                      []))
                  (vector-set! delta-size index
                    (length (vector-ref delta index)))
                  (vector-set! delta-version index
                    (+ 1 (vector-ref delta-version index)))
                  (reset-delta (+ index 1)))))
          (until (not active?)
          (set! round (+ round 1))
          (let ((pending (make-vector count []))
                (pending-seen (make-vector count #f))
                (pending-lattice-keys (make-vector count []))
                (pending-count 0))
            (def (admit-stored! index pending-table stored)
              (unless (and (list? stored)
                           (= (length stored) (vector-ref arity index)))
                (error "invalid ASCENT storage provider row" stored))
              (let (check (vector-ref field-checkers index))
                (when check (check stored)))
              (unless (or (hash-get (vector-ref seen index) stored)
                          (hash-get pending-table stored))
                (hash-put! pending-table stored #t)
                (set! pending-count (+ pending-count 1))
                (vector-set! pending index
                  (cons stored (vector-ref pending index)))))
            (def (emit! atom environment)
              (let* ((index (vector-ref atom 0))
                     (row (gerbil-ascent-head-row
                           (vector-ref atom 1) environment))
                     (pending-table
                      (or (vector-ref pending-seen index)
                          (let (fresh (make-hash-table))
                            (vector-set! pending-seen index fresh)
                          fresh))))
                (let (check (vector-ref field-checkers index))
                  (when check (check row)))
                (if (vector-ref lattice-joins index)
                  (let* ((key (gerbil-ascent-lattice-key row))
                         (staged (hash-get pending-table key))
                         (prior (or staged
                                    (hash-get (vector-ref lattice-rows index)
                                              key)))
                         (merged (if prior
                                   (gerbil-ascent-joined-row
                                    key ((vector-ref lattice-joins index)
                                         (gerbil-ascent-lattice-value prior)
                                         (gerbil-ascent-lattice-value row)))
                                   row)))
                    (let (check (vector-ref field-checkers index))
                      (when check (check merged)))
                    (unless (and prior (equal? merged prior))
                      (unless staged
                        (set! pending-count (+ pending-count 1)))
                      (hash-put! pending-table key merged)
                      (vector-set! pending-lattice-keys index
                        (cons key (vector-ref pending-lattice-keys index)))))
                  (if (eq? (vector-ref storage-providers index)
                           gerbil-ascent-set-storage-provider)
                    ;; The built-in extension is exactly (list row). Preserve
                    ;; validation order without allocating that temporary list.
                    (admit-stored! index pending-table row)
                    (let (expanded
                          ((vector-ref storage-extensions index)
                           (vector-ref storage-states index)
                           (vector-ref all index)
                           (vector-ref pending index) row
                           (- output-limit
                              (+ source-materialized-count
                                 derived-count pending-count))))
                      (unless (list? expanded)
                        (error "ASCENT storage provider returned non-list rows"))
                      (for-each
                       (lambda (stored)
                         (admit-stored! index pending-table stored))
                       expanded))))
                (when (> (+ derived-count pending-count) derived-limit)
                  (error "ASCENT derived fact budget exceeded"))
                (when (> (+ source-materialized-count
                            derived-count pending-count)
                         output-limit)
                  (error "ASCENT output fact budget exceeded"))))
            (def (clause-inputs variables environment)
              (map (lambda (name)
                     (let (binding (assq name environment))
                       (unless binding
                         (error "unbound ASCENT clause variable" name))
                       (cdr binding)))
                   variables))
            (def (visit-body body delta-at depth environment consume)
              (if (null? body)
                (consume environment)
                (let (clause (car body))
                  (cond
                   ((eq? (vector-ref clause 0) 'atom)
                    (let* ((atom (vector-ref clause 1))
                           (rows (indexed-rows atom environment
                                               (= depth delta-at))))
                      (for-each
                       (lambda (row)
                         (let (bound (gerbil-ascent-bind-row (vector-ref atom 3)
                                                row environment))
                           (when bound
                             (visit-body (cdr body) delta-at (+ depth 1)
                                         bound consume))))
                       rows)))
                   ((eq? (vector-ref clause 0) 'negation)
                    (let* ((atom (vector-ref clause 1))
                           (rows (indexed-rows atom environment #f)))
                      (unless (ormap
                               (lambda (row)
                                 (gerbil-ascent-bind-row (vector-ref atom 3)
                                           row environment))
                               rows)
                        (visit-body (cdr body) delta-at depth
                                    environment consume))))
                   ((eq? (vector-ref clause 0) 'aggregate)
                    (let* ((atom (vector-ref clause 1))
                           (rows (indexed-rows atom environment #f))
                           (variables (vector-ref clause 3))
                           (tuples []))
                      (for-each
                       (lambda (row)
                         (let (bound (gerbil-ascent-bind-row (vector-ref atom 3)
                                                row environment))
                           (when bound
                             (set! tuples
                               (cons (clause-inputs variables bound)
                                     tuples)))))
                       rows)
                      (let (values ((vector-ref clause 4)
                                    (reverse tuples)))
                        (unless (list? values)
                          (error "ASCENT aggregator must return a list"
                                 values))
                        (for-each
                         (lambda (value)
                           (let* ((output (vector-ref clause 2))
                                  (matcher (vector-ref clause 5))
                                  (next-environment
                                   (if matcher
                                     (let (matched (matcher value))
                                       (unless (and (list? matched)
                                                    (= (length matched)
                                                       (length output)))
                                         (error "ASCENT aggregate pattern returned invalid bindings"
                                                matched output))
                                       (append (map cons output matched)
                                               environment))
                                     (cons (cons output value)
                                           environment))))
                             (visit-body (cdr body) delta-at depth
                                         next-environment consume)))
                         values))))
                   ((eq? (vector-ref clause 0) 'guard)
                    (let (pass? (apply (vector-ref clause 2)
                                       (clause-inputs (vector-ref clause 1)
                                                      environment)))
                      (unless (boolean? pass?)
                        (error "ASCENT guard must return a boolean" pass?))
                      (when pass?
                        (visit-body (cdr body) delta-at depth
                                    environment consume))))
                   ((eq? (vector-ref clause 0) 'generator)
                    (let (values (apply (vector-ref clause 3)
                                         (clause-inputs (vector-ref clause 2)
                                                        environment)))
                      (for (value values)
                        (let* ((output (vector-ref clause 1))
                               (next-environment
                                (if (list? output)
                                  (let (row (if (vector? value)
                                               (vector->list value)
                                               value))
                                    (unless (and (list? row)
                                                 (= (length row)
                                                    (length output)))
                                      (error "ASCENT generator tuple arity mismatch"
                                             value))
                                    (gerbil-ascent-bind-row output row
                                                            environment))
                                  (cons (cons output value) environment))))
                          (visit-body (cdr body) delta-at depth
                                      next-environment consume)))))
                   ((eq? (vector-ref clause 0) 'binding)
                    (let (value (apply (vector-ref clause 3)
                                       (clause-inputs (vector-ref clause 2)
                                                      environment)))
                      (visit-body (cdr body) delta-at depth
                                  (cons (cons (vector-ref clause 1) value)
                                        environment)
                                  consume)))))))
            (for-each
             (lambda (rule)
               (let ((started (and rule-ticks (current-jiffy)))
                     (heads (vector-ref rule 0))
                     (body (vector-ref rule 1))
                     (positions (vector-ref rule 2))
                     (prunable (vector-ref rule 4)))
                 (if (null? positions)
                   (when (and (= round 1) first-run?)
                     (visit-body body -1 0 []
                                 (lambda (environment)
                                   (for-each
                                    (lambda (head) (emit! head environment))
                                    heads))))
                   (if (and (= round 1)
                            (or first-run? (> stratum 0)))
                     ;; At the first round every relation in this stratum has
                     ;; delta = all. One full evaluation covers every delta
                     ;; position without emitting the same join repeatedly.
                     (visit-body body -1 0 []
                                 (lambda (environment)
                                   (for-each
                                    (lambda (head) (emit! head environment))
                                    heads)))
                     (for-each
                      (lambda (delta-at)
                        ;; Prefix atoms have no index, expression, pattern or
                        ;; clause callbacks. The empty pivot uses raw rows.
                        (unless (and (< delta-at (vector-length prunable))
                                     (= (vector-ref delta-size
                                          (vector-ref prunable delta-at)) 0))
                          (visit-body body delta-at 0 []
                                      (lambda (environment)
                                        (for-each
                                         (lambda (head) (emit! head environment))
                                         heads)))))
                      positions)))
                 (when started
                   (let (index (vector-ref rule 3))
                     (vector-set! rule-ticks index
                       (+ (vector-ref rule-ticks index)
                          (- (current-jiffy) started)))))))
             active-rules)
            (set! active? #f)
            (let commit ((index 0))
              (when (< index count)
                (if (vector-ref lattice-joins index)
                  (let ((table (vector-ref pending-seen index))
                        (visited (make-hash-table))
                        (rows []))
                    ;; The last update for each key wins this round. Replay
                    ;; key events in reverse arrival order to retain the
                    ;; previous deterministic pending-row order.
                    (for-each
                     (lambda (key)
                       (unless (hash-get visited key)
                         (hash-put! visited key #t)
                         (set! rows (cons (hash-get table key) rows))))
                     (vector-ref pending-lattice-keys index))
                    (let (staged-rows (reverse rows))
                      (vector-set! pending index staged-rows)
                      (unless (null? staged-rows)
                        (vector-set! all index
                          (append
                           (reverse staged-rows)
                           (filter
                            (lambda (existing)
                              (not (hash-get
                                    table
                                    (gerbil-ascent-lattice-key existing))))
                            (vector-ref all index))))
                        (for-each
                         (lambda (row)
                           (hash-put! (vector-ref lattice-rows index)
                                      (gerbil-ascent-lattice-key row) row)
                           (hash-put! (vector-ref seen index) row #t)
                           (set! derived-count (+ derived-count 1))
                           (set! active? #t))
                         staged-rows))))
                  (for-each
                   (lambda (row)
                     (hash-put! (vector-ref seen index) row #t)
                     (vector-set! all index (cons row (vector-ref all index)))
                     (set! derived-count (+ derived-count 1))
                     (set! active? #t))
                   (vector-ref pending index)))
                (let (batch-size (length (vector-ref pending index)))
                  (unless (= batch-size 0)
                    (unless (vector-ref lattice-joins index)
                      (advance-all-indexes! index
                                            (vector-ref pending index)))
                    (vector-set! all-version index
                      (+ 1 (vector-ref all-version index)))
                    ;; Only the exact built-in Set appends unique pending rows
                    ;; without replacing historical rows. Restrict indexing to
                    ;; the built-in hash Provider too: custom callbacks may
                    ;; retain the row spine. Other Providers keep the recount.
                    (vector-set! all-size index
                      (if (and (not (vector-ref lattice-joins index))
                               (eq? (vector-ref storage-providers index)
                                    gerbil-ascent-set-storage-provider)
                               (eq? (vector-ref index-providers index)
                                    gerbil-ascent-hash-index-provider))
                        (+ (vector-ref all-size index) batch-size)
                        (length (vector-ref all index)))))
                  (vector-set! delta index (vector-ref pending index))
                  (vector-set! delta-size index batch-size)
                  (vector-set! delta-version index
                    (+ 1 (vector-ref delta-version index))))
                (commit (+ index 1))))
            (when (and active? deadline (>= (current-jiffy) deadline))
              (set! resume-stratum stratum)
              (set! resume-round round)
              (set! complete? #f)
              (return #f))))
            (set! resume-stratum #f)
            (set! resume-round 0)
            (evaluate-stratum (+ stratum 1)))))))
         (when complete?
           (set! first-run? #f)
           (set! dirty? #f)
           (set! materialized-dirty? #f))
         (let (snapshots
               (vector-map (lambda (rows) (reverse rows)) all))
           (set! last-result
             (.o (relation-names (vector->list names))
                 (finished complete?)
                 (evaluation-path 'stratified-semi-naive)
                 (rule-time-nanoseconds
                  (and rule-ticks
                       (map (lambda (ticks)
                              (quotient (* ticks 1000000000)
                                        (jiffies-per-second)))
                            (vector->list rule-ticks))))
                 (relation-sizes
                  (lambda ()
                    (map (lambda (name rows)
                           (cons name (length rows)))
                         (vector->list names) (vector->list snapshots))))
                 (rows-of (lambda (name)
                            (vector-ref snapshots (position-of name))))))))
         last-result))
        (def (run!)
          (if recompute-from-source?
            last-result
            (run-retained!)))
        (def (run-timeout! duration-nanoseconds)

          (unless (and (exact-integer? duration-nanoseconds)
                       (>= duration-nanoseconds 0))
            (error "invalid ASCENT timeout in nanoseconds"
                   duration-nanoseconds))
          (if recompute-from-source?
            last-result
            (run-retained!
             (+ (current-jiffy)
                (quotient (* duration-nanoseconds (jiffies-per-second))
                          1000000000)))))
        (if session?
          (validate GerbilAscentSessionContract
                    (.o (:: @ Session.)
                        (.append-source!
                         (if single-set-source?
                           append-single-set-source! append-source!))
                        (.replace-source! replace-source!)
                        (.run run!)
                        (.run-timeout run-timeout!)
                        (.analysis analysis)
                        (.schema schema)
                        (.recomputed? (lambda () recompute-from-source?))
                        (.source-additions source-additions)
                        (.source-overrides source-overrides)))
          run!)))))

;; : (-> Program EvaluationResult)
(def (gerbil-ascent-evaluate-program program
                                      measure-rule-times?: (measure-rule-times? #f))
  (unless (boolean? measure-rule-times?)
    (error "invalid ASCENT rule timing option" measure-rule-times?))
  ((gerbil-ascent-make-engine program #f #f #f measure-rule-times?)))
