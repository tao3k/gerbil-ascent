;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Generic stratified semi-naive evaluator. Mutable row buffers belong to one
;;; session; public declarations and returned snapshots are POO values.
(import (only-in :clan/poo/object .o .ref object?)
        (only-in :clan/poo/mop validate)
        :std/iter
        (only-in "objects.ss" gerbil-ascent-clause-plan
                 gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-lattice)
        (only-in "types.ss" GerbilAscentSessionContract)
        (only-in "funs.ss" gerbil-ascent-rule-strata
                 gerbil-ascent-delta-positions
                 gerbil-ascent-lattice-key
                 gerbil-ascent-lattice-value
                 gerbil-ascent-joined-row
                 gerbil-ascent-expression-value
                 gerbil-ascent-bind-row
                 gerbil-ascent-head-row)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-index-provider-build
                 gerbil-ascent-index-provider-extend!
                 gerbil-ascent-index-provider-lookup)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-storage-make-state)
        (only-in :clan/poo/support/base until))

(export gerbil-ascent-evaluate-program
        gerbil-ascent-open-session
        gerbil-ascent-session-append-source!
        gerbil-ascent-session-replace-source!
        gerbil-ascent-session-run)

(def Session. (.ref GerbilAscentSessionContract 'proto))

;; Program declarations are POO values. Their lowered rule plan is immutable
;; and can be shared; each evaluation still creates its own relation state.
(def +program-analysis-cache+ (make-hash-table-eq weak-keys: #t))
(def +program-schema-cache+ (make-hash-table-eq weak-keys: #t))
(def +program-analysis-lock+ (make-mutex 'ascent-program-analysis))

(def (with-program-analysis-lock thunk)
  (dynamic-wind
   (lambda () (mutex-lock! +program-analysis-lock+))
   thunk
   (lambda () (mutex-unlock! +program-analysis-lock+))))

(def (gerbil-ascent-program-analysis program relations rules build)
  (let (cached
        (with-program-analysis-lock
         (lambda () (hash-get +program-analysis-cache+ program))))
    (if (and cached
             (eq? relations (vector-ref cached 0))
             (eq? rules (vector-ref cached 1)))
      cached
      (let (fresh (build))
        (with-program-analysis-lock
         (lambda ()
           (hash-put! +program-analysis-cache+ program fresh)))
        fresh))))

(def (gerbil-ascent-program-schema program relations)
  (let (cached
        (with-program-analysis-lock
         (lambda () (hash-get +program-schema-cache+ program))))
    (if (and cached (eq? relations (vector-ref cached 0)))
      cached
      (let* ((count (length relations))
             (names (make-vector count #f))
             (arity (make-vector count #f))
             (field-checkers (make-vector count #f))
             (positions (make-hash-table-eq))
             (index-providers (make-vector count #f))
             (storage-extensions (make-vector count #f))
             (lattice-joins (make-vector count #f))
             (kinds (make-vector count #f))
             (storage-providers (make-vector count #f)))
        (for-each
         (lambda (relation index)
           (let* ((name (.ref relation 'name))
                  (width (.ref relation 'arity))
                  (kind (.ref relation 'storage-kind))
                  (predicates (.ref relation 'field-predicates)))
             (unless (and (symbol? name) (not (hash-get positions name))
                          (exact-integer? width) (<= 0 width)
                          (memq kind '(relation lattice))
                          (or (eq? kind 'relation) (> width 0))
                          (list? predicates)
                          (or (null? predicates)
                              (= (length predicates) width))
                          (andmap procedure? predicates))
               (error "invalid or duplicate ASCENT relation" name))
             (vector-set! names index name)
             (vector-set! arity index width)
             (vector-set! kinds index kind)
             (hash-put! positions name (+ index 1))
             (when (pair? predicates)
               (vector-set! field-checkers index
                 (lambda (row)
                   (for-each
                    (lambda (predicate value)
                      (unless (predicate value)
                        (error "ASCENT relation field type mismatch"
                               name row)))
                    predicates row))))
             (vector-set! index-providers index
               (.ref relation 'index-provider))
             (if (eq? kind 'lattice)
               (let (join (.ref relation 'join))
                 (unless (procedure? join)
                   (error "invalid ASCENT lattice join" name))
                 (vector-set! lattice-joins index join))
               (let (provider (.ref relation 'storage-provider))
                 (vector-set! storage-providers index provider)
                 (vector-set! storage-extensions index
                   (.ref provider '.extend-rows))))))
         relations (iota count))
        (let (fresh (vector relations names arity field-checkers positions
                            index-providers storage-extensions lattice-joins
                            kinds storage-providers))
          (with-program-analysis-lock
           (lambda () (hash-put! +program-schema-cache+ program fresh)))
          fresh)))))

(def (gerbil-ascent-make-engine program session? (analysis-override #f)
                                (schema-override #f))
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
                 (exact-integer? output-limit) (> output-limit 0))
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
      (def (position-of name)
        (let (slot (hash-get positions name))
          (unless slot (error "unknown ASCENT relation" name))
          (- slot 1)))
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
                 (present (make-hash-table)))
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
                   (vector-set! all index
                     (cons merged
                           (if previous
                             (filter (lambda (existing)
                                       (not (equal? (gerbil-ascent-lattice-key existing)
                                                    key)))
                                     (vector-ref all index))
                             (vector-ref all index)))))
                 (let (materialized
                       ((vector-ref storage-extensions index)
                        (vector-ref storage-states index)
                        (vector-ref all index) [] row
                        (- output-limit source-materialized-count)))
                   (unless (list? materialized)
                     (error "ASCENT storage provider returned non-list rows"))
                   (for-each
                    (lambda (stored)
                      (unless (and (list? stored) (= (length stored) width))
                        (error "invalid ASCENT storage provider row" stored))
                      (let (check (vector-ref field-checkers index))
                        (when check (check stored)))
                      (hash-put! present stored #t)
                      (set! source-materialized-count
                        (+ source-materialized-count 1))
                      (when (> source-materialized-count output-limit)
                        (error "ASCENT source fact budget exceeded"))
                      (vector-set! all index
                        (cons stored (vector-ref all index))))
                    materialized))))
             rows)
            (vector-set! seen index present)
            (vector-set! delta index (vector-ref all index))
            (vector-set! all-size index (length (vector-ref all index)))
            (vector-set! delta-size index
              (vector-ref all-size index))
            (initialize (cdr remaining) (+ index 1)))))
      (def (prepare-rule rule)
        (unless (object? rule)
          (error "invalid ASCENT rule declaration" rule))
        (let* ((body (.ref rule 'body))
               (heads (.ref rule 'heads))
               (bound []) (atoms 0) (body-plans []))
          (unless (and (list? body) (pair? heads) (list? heads))
            (error "invalid ASCENT rule declaration" rule))
          (for-each
           (lambda (clause)
             (unless (object? clause)
               (error "invalid ASCENT rule clause" clause))
             (let (result (gerbil-ascent-clause-plan clause atom-plan bound))
               (set! body-plans (cons (vector-ref result 0) body-plans))
               (set! bound (vector-ref result 1))
               (set! atoms (+ atoms (vector-ref result 2)))))
           body)
          (let (head-plans
                (map (lambda (head)
                       (unless (and (object? head)
                                    (eq? (.ref head 'ascent-clause-kind) 'atom))
                         (error "invalid ASCENT rule head" head))
                       (let (plan (atom-plan head))
                         (for-each
                          (lambda (term)
                            (case (car term)
                              ((variable)
                               (unless (memq (cdr term) bound)
                                 (error "unsafe ASCENT head variable"
                                        (cdr term))))
                              ((expression)
                               (for-each
                                (lambda (name)
                                  (unless (memq name bound)
                                    (error "unsafe ASCENT head expression variable"
                                           name)))
                                (vector-ref (cdr term) 0)))
                              ((pattern)
                               (error "ASCENT pattern is invalid in a rule head"))
                              ((wildcard)
                               (error "ASCENT wildcard is invalid in a rule head"))))
                          (vector-ref plan 1))
                         plan))
                     heads))
            (vector head-plans (reverse body-plans) atoms))))
      (let* ((analysis
              ;; Source-only replacement preserves declarations and rules.
              ;; Its session reuses this immutable rule plan while the fresh
              ;; engine still owns new rows, indexes, storage and budgets.
              (or analysis-override
                  (gerbil-ascent-program-analysis
                   program relations rules
                   (lambda ()
                     (let (plans (map prepare-rule rules))
                       (let* ((strata (gerbil-ascent-rule-strata plans count))
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
                                               stratum)))))
                                    plans))
                               (vector-set! active stratum selected)
                               (plan-stratum (+ stratum 1)))))
                         (vector relations rules plans strata active)))))))
             (rule-plans (vector-ref analysis 2))
             (strata (vector-ref analysis 3))
             (active-by-stratum (vector-ref analysis 4))
             (highest-stratum (- (vector-length active-by-stratum) 1))
             (positive-rules?
              (and session?
                   (andmap
                    (lambda (rule)
                      (andmap (lambda (clause)
                                (eq? (vector-ref clause 0) 'atom))
                              (vector-ref rule 1)))
                    rule-plans)))
             (source-originals
              (and session?
                   (list->vector
                    (map (lambda (relation) (.ref relation 'rows))
                         relations))))
             (source-additions (and session? (make-vector count [])))
             (source-overrides (and session? (make-vector count #f)))
             (recompute-from-source? #f)
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
        (def (append-source! name row)
          (when first-run?
            (error "ASCENT session must run before source updates"))
          (let* ((index (position-of name))
                 (width (vector-ref arity index)))
            (unless (and (list? row) (= (length row) width))
              (error "invalid ASCENT session source row" name row))
            (let (check (vector-ref field-checkers index))
              (when check (check row)))
            (when (>= source-count input-limit)
              (error "ASCENT session input fact budget exceeded"))
            (cond
             ((or (not positive-rules?)
                  recompute-from-source?
                  (vector-ref lattice-joins index))
              ;; Negation, aggregation, or a lattice refinement can invalidate
              ;; previously consumed rows. Re-evaluate the accepted source
              ;; snapshot before publishing a changed fixed point.
              (let* ((replacement
                      (append (source-rows-at index) (list row)))
                     (candidate (source-program-with index replacement))
                     (result ((gerbil-ascent-make-engine
                               candidate #f analysis schema))))
                (set! source-count (+ source-count 1))
                (vector-set! source-overrides index replacement)
                (vector-set! source-additions index [])
                (set! recompute-from-source? #t)
                (set! dirty? #f)
                (set! last-result result)))
             (else
              (let* ((expanded
                    ((vector-ref storage-extensions index)
                     (vector-ref storage-states index)
                     (vector-ref all index)
                     (vector-ref delta index) row
                     (- output-limit
                        (+ source-materialized-count derived-count))))
                   (batch-seen (make-hash-table))
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
                             (hash-get batch-seen stored))
                   (hash-put! batch-seen stored #t)
                   (set! new-rows (cons stored new-rows))))
               expanded)
              (set! new-rows (reverse new-rows))
              (when (> (+ source-materialized-count derived-count
                          (length new-rows)) output-limit)
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
                (advance-all-indexes! index new-rows)
                (vector-set! all-size index (length (vector-ref all index)))
                (vector-set! delta-size index
                  (length (vector-ref delta index)))
                (vector-set! all-version index
                  (+ 1 (vector-ref all-version index)))
                (vector-set! delta-version index
                  (+ 1 (vector-ref delta-version index)))))))
            (unless (vector-ref source-overrides index)
              (vector-set! source-additions index
                (cons row (vector-ref source-additions index))))))
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
                               candidate #f analysis schema))))
                (set! source-count next-count)
                (vector-set! source-overrides index rows)
                (vector-set! source-additions index [])
                (set! recompute-from-source? #t)
                (set! dirty? #f)
                (set! last-result result)))))
        (def (run-retained!)
         (when dirty?
         (let evaluate-stratum ((stratum 0))
          (when (<= stratum highest-stratum)
            (let ((active-rules (vector-ref active-by-stratum stratum))
                  (active? #t) (round 0))
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
                  (reset-delta (+ index 1))))
          (until (not active?)
          (set! round (+ round 1))
          (let ((pending (make-vector count []))
                (pending-seen (make-vector count #f))
                (pending-count 0))
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
                      (vector-set! pending index
                        (cons merged
                              (filter (lambda (existing)
                                        (not (equal? (gerbil-ascent-lattice-key existing)
                                                     key)))
                                      (vector-ref pending index))))))
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
                       (unless (and (list? stored)
                                    (= (length stored)
                                       (vector-ref arity index)))
                         (error "invalid ASCENT storage provider row" stored))
                       (let (check (vector-ref field-checkers index))
                         (when check (check stored)))
                       (unless (or (hash-get (vector-ref seen index) stored)
                                   (hash-get pending-table stored))
                         (hash-put! pending-table stored #t)
                         (set! pending-count (+ pending-count 1))
                         (vector-set! pending index
                           (cons stored (vector-ref pending index)))))
                     expanded)))
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
                         (let (bound (gerbil-ascent-bind-row (vector-ref atom 1)
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
                                 (gerbil-ascent-bind-row (vector-ref atom 1)
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
                         (let (bound (gerbil-ascent-bind-row (vector-ref atom 1)
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
               (let ((heads (vector-ref rule 0))
                     (body (vector-ref rule 1))
                     (positions (vector-ref rule 2)))
                 (if (null? positions)
                   (when (and (= round 1) first-run?)
                     (visit-body body -1 0 []
                                 (lambda (environment)
                                   (for-each
                                    (lambda (head) (emit! head environment))
                                    heads))))
                   (for-each
                    (lambda (delta-at)
                      (visit-body body delta-at 0 []
                                  (lambda (environment)
                                    (for-each
                                     (lambda (head) (emit! head environment))
                                     heads))))
                    positions))))
             active-rules)
            (set! active? #f)
            (let commit ((index 0))
              (when (< index count)
                (for-each
                 (lambda (row)
                   (when (vector-ref lattice-joins index)
                     (let (key (gerbil-ascent-lattice-key row))
                       (hash-put! (vector-ref lattice-rows index) key row)
                       (vector-set! all index
                         (filter (lambda (existing)
                                   (not (equal? (gerbil-ascent-lattice-key existing)
                                                key)))
                                 (vector-ref all index)))))
                   (hash-put! (vector-ref seen index) row #t)
                   (vector-set! all index (cons row (vector-ref all index)))
                   (set! derived-count (+ derived-count 1))
                   (set! active? #t))
                 (vector-ref pending index))
                (unless (null? (vector-ref pending index))
                  (unless (vector-ref lattice-joins index)
                    (advance-all-indexes! index
                                          (vector-ref pending index)))
                  (vector-set! all-version index
                    (+ 1 (vector-ref all-version index)))
                  (vector-set! all-size index
                    (length (vector-ref all index))))
                (vector-set! delta index (vector-ref pending index))
                (vector-set! delta-size index
                  (length (vector-ref pending index)))
                (vector-set! delta-version index
                  (+ 1 (vector-ref delta-version index)))
                (commit (+ index 1))))))
            (evaluate-stratum (+ stratum 1)))))
         (set! first-run? #f)
         (set! dirty? #f)
         (let (snapshots
               (vector-map (lambda (rows) (reverse rows)) all))
           (set! last-result
             (.o (relation-names (vector->list names))
                 (evaluation-path 'stratified-semi-naive)
                 (rows-of (lambda (name)
                            (vector-ref snapshots (position-of name))))))))
         last-result)
        (def (run!)
          (if recompute-from-source?
            last-result
            (run-retained!)))
        (if session?
          (validate GerbilAscentSessionContract
                    (.o (:: @ Session.)
                        (.append-source! append-source!)
                        (.replace-source! replace-source!)
                        (.run run!)))
          run!)))))

(def (gerbil-ascent-open-session program)
  ;; A Provider may mutate its private state before returning an invalid
  ;; batch or raising. Keep the accepted source snapshot outside the engine
  ;; so a failed operation can rebuild all evaluation-local state from it.
  (let* ((relations (.ref program 'relations))
         (positions (make-hash-table-eq))
         (initial (list->vector
                   (map (lambda (relation) (.ref relation 'rows))
                        relations)))
         (pending (list->vector (vector->list initial)))
         (committed (list->vector (vector->list initial)))
         (initialized? #f)
         (clean? #f)
         (last-result #f)
         (engine (gerbil-ascent-make-engine program #t)))
    (for-each
     (lambda (relation index)
       (hash-put! positions (.ref relation 'name) (+ index 1)))
     relations (iota (length relations)))
    (def (snapshot-copy rows)
      (list->vector (vector->list rows)))
    (def (position-of name)
      (let (slot (hash-get positions name))
        (unless slot (error "unknown ASCENT relation" name))
        (- slot 1)))
    (def (snapshot-program rows)
      (gerbil-ascent-program
       (map (lambda (relation source-rows)
              (let ((name (.ref relation 'name))
                    (arity (.ref relation 'arity))
                    (index (.ref relation 'index-provider))
                    (types (.ref relation 'field-predicates)))
                (if (eq? (.ref relation 'storage-kind) 'lattice)
                  (gerbil-ascent-lattice name arity source-rows
                                         (.ref relation 'join) index types)
                  (gerbil-ascent-relation name arity source-rows index
                                          (.ref relation 'storage-provider)
                                          types))))
            relations (vector->list rows))
       (.ref program 'rules)
       (.ref program 'max-input-facts)
       (.ref program 'max-derived-facts)
       (.ref program 'max-output-facts)))
    (def (restore! rows)
      (set! engine #f)
      (let* ((candidate (snapshot-program rows))
             (fresh (gerbil-ascent-make-engine candidate #t)))
        (when initialized? ((.ref fresh '.run)))
        (set! engine fresh)
        (set! pending (snapshot-copy rows))
        (set! clean? (and initialized?
                          (equal? (vector->list rows)
                                  (vector->list committed))))))
    (def (attempt thunk)
      (with-catch
       (lambda (failure) (vector #f failure))
       (lambda () (vector #t (thunk)))))
    (def (recover! rows failure)
      (let (restored (attempt (lambda () (restore! rows))))
        (unless (vector-ref restored 0)
          (restore! committed)))
      (raise failure))
    (def (append-source! name row)
      (let (before (snapshot-copy pending))
        (let (outcome
              (attempt
               (lambda ()
                 ((.ref engine '.append-source!) name row)
                 (let (index (position-of name))
                   (vector-set! pending index
                     (append (vector-ref pending index) (list row)))))))
          (unless (vector-ref outcome 0)
            (recover! before (vector-ref outcome 1)))
          (set! clean? #f)
          (vector-ref outcome 1))))
    (def (replace-source! name rows)
      (let (before (snapshot-copy pending))
        (let (outcome
              (attempt
               (lambda ()
                 ((.ref engine '.replace-source!) name rows)
                 (vector-set! pending (position-of name) rows))))
          (unless (vector-ref outcome 0)
            (recover! before (vector-ref outcome 1)))
          (set! clean? #f)
          (vector-ref outcome 1))))
    (def (run!)
      (if clean?
        last-result
        (let (outcome (attempt (lambda () ((.ref engine '.run)))))
          (unless (vector-ref outcome 0)
            (recover! committed (vector-ref outcome 1)))
          (set! initialized? #t)
          (set! committed (snapshot-copy pending))
          (set! last-result (vector-ref outcome 1))
          (set! clean? #t)
          last-result)))
    (validate GerbilAscentSessionContract
              (.o (:: @ Session.)
                  (.append-source! append-source!)
                  (.replace-source! replace-source!)
                  (.run run!)))))

(def (gerbil-ascent-session-append-source! session name row)
  ((.ref session '.append-source!) name row))

(def (gerbil-ascent-session-replace-source! session name rows)
  ((.ref session '.replace-source!) name rows))

(def (gerbil-ascent-session-run session)
  ((.ref session '.run)))

(def (gerbil-ascent-evaluate-program program)
  ((gerbil-ascent-make-engine program #f)))
