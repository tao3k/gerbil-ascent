;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Generic stratified semi-naive evaluator. Mutable row buffers belong to one
;;; session; public declarations and returned snapshots are POO values.
(import (only-in :clan/poo/object .o .ref object?)
        (only-in :clan/poo/mop validate)
        (only-in "objects.ss" gerbil-ascent-clause-plan)
        (only-in "types.ss" GerbilAscentSessionContract)
        (only-in "funs.ss" gerbil-ascent-rule-strata
                 gerbil-ascent-delta-positions
                 gerbil-ascent-lattice-key
                 gerbil-ascent-lattice-value
                 gerbil-ascent-joined-row
                 gerbil-ascent-bind-row
                 gerbil-ascent-head-row)
        (only-in :gerbil-ascent/table/provider
                 gerbil-ascent-index-provider-build
                 gerbil-ascent-index-provider-lookup)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-storage-make-state)
        (only-in :clan/poo/support/base until))

(export gerbil-ascent-evaluate-program
        gerbil-ascent-open-session
        gerbil-ascent-session-append-source!
        gerbil-ascent-session-run)

(def Session. (.ref GerbilAscentSessionContract 'proto))

(def (gerbil-ascent-make-engine program session?)
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
           (names (make-vector count #f))
           (arity (make-vector count #f))
           (positions (make-hash-table-eq))
           (all (make-vector count []))
           (delta (make-vector count []))
           (all-version (make-vector count 0))
           (delta-version (make-vector count 0))
           (all-size (make-vector count 0))
           (delta-size (make-vector count 0))
           (all-indexes (make-vector count #f))
           (delta-indexes (make-vector count #f))
           (index-providers (make-vector count #f))
           (storage-extensions (make-vector count #f))
           (storage-states (make-vector count #f))
           (seen (make-vector count #f))
           (lattice-joins (make-vector count #f))
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
          (unless (memq kind '(variable literal))
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
                             (if (eq? (car term) 'literal)
                               (cdr term)
                               (let (bound (assq (cdr term) environment))
                                 (unless bound
                                   (error "unbound ASCENT index variable"
                                          (cdr term)))
                                 (cdr bound)))))
                         columns)))
              (let (matched
                    (gerbil-ascent-index-provider-lookup
                     (vector-ref index-providers index) lookup key))
                (unless (list? matched)
                  (error "ASCENT index provider returned non-list rows"
                         matched))
                matched)))))
      (let initialize ((remaining relations) (index 0))
        (unless (null? remaining)
          (let* ((relation (car remaining))
                 (name (.ref relation 'name))
                 (width (.ref relation 'arity))
                 (rows (.ref relation 'rows))
                 (kind (.ref relation 'storage-kind))
                 (storage-provider
                  (and (eq? kind 'relation)
                       (.ref relation 'storage-provider)))
                 (present (make-hash-table)))
            (unless (and (symbol? name) (not (hash-get positions name))
                         (exact-integer? width) (<= 0 width) (list? rows)
                         (memq kind '(relation lattice))
                         (or (eq? kind 'relation) (> width 0)))
              (error "invalid or duplicate ASCENT relation" name))
            (vector-set! names index name)
            (vector-set! arity index width)
            (hash-put! positions name (+ index 1))
            (when (eq? kind 'lattice)
              (let (join (.ref relation 'join))
                (unless (procedure? join)
                  (error "invalid ASCENT lattice join" name))
                (vector-set! lattice-joins index join)
                (vector-set! lattice-rows index (make-hash-table))))
            (when (eq? kind 'relation)
              ;; Resolve the POO method slot once per relation. The row loop
              ;; calls the selected Scheme function without redispatching.
              (vector-set! storage-extensions index
                (.ref storage-provider '.extend-rows))
              (vector-set! storage-states index
                (gerbil-ascent-storage-make-state storage-provider)))
            (for-each
             (lambda (row)
               (unless (and (list? row) (= (length row) width))
                 (error "invalid ASCENT relation row" name row))
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
            (vector-set! index-providers index
              (.ref relation 'index-provider))
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
                            (when (eq? (car term) 'variable)
                              (unless (memq (cdr term) bound)
                                (error "unsafe ASCENT head variable"
                                       (cdr term)))))
                          (vector-ref plan 1))
                         plan))
                     heads))
            (vector head-plans (reverse body-plans) atoms))))
      (let* ((rule-plans (map prepare-rule rules))
             (strata (gerbil-ascent-rule-strata rule-plans count))
             (highest-stratum
              (if (= count 0) -1 (apply max (vector->list strata))))
             (positive-rules?
              (andmap
               (lambda (rule)
                 (andmap (lambda (clause)
                           (eq? (vector-ref clause 0) 'atom))
                         (vector-ref rule 1)))
               rule-plans))
             (first-run? #t)
             (dirty? #t)
             (last-result #f))
        (def (append-source! name row)
          (when first-run?
            (error "ASCENT session must run before source updates"))
          (unless positive-rules?
            (error "ASCENT session updates require positive rules"))
          (when (ormap procedure? (vector->list lattice-joins))
            (error "ASCENT session updates do not support lattice relations"))
          (let* ((index (position-of name))
                 (width (vector-ref arity index)))
            (when (vector-ref lattice-joins index)
              (error "ASCENT session lattice updates are unsupported" name))
            (unless (and (list? row) (= (length row) width))
              (error "invalid ASCENT session source row" name row))
            (when (>= source-count input-limit)
              (error "ASCENT session input fact budget exceeded"))
            (let ((changed? #f)
                  (expanded
                  ((vector-ref storage-extensions index)
                   (vector-ref storage-states index)
                   (vector-ref all index)
                   (vector-ref delta index) row
                   (- output-limit
                      (+ source-materialized-count derived-count)))))
              (unless (list? expanded)
                (error "ASCENT storage provider returned non-list rows"))
              (set! source-count (+ source-count 1))
              (for-each
               (lambda (stored)
                 (unless (and (list? stored) (= (length stored) width))
                   (error "invalid ASCENT storage provider row" stored))
                 (unless (hash-get (vector-ref seen index) stored)
                   (when (>= (+ source-materialized-count derived-count)
                             output-limit)
                     (error "ASCENT session output fact budget exceeded"))
                   (hash-put! (vector-ref seen index) stored #t)
                   (set! source-materialized-count
                     (+ source-materialized-count 1))
                   (vector-set! all index
                     (cons stored (vector-ref all index)))
                   (vector-set! delta index
                     (cons stored (vector-ref delta index)))
                   (set! changed? #t)
                   (set! dirty? #t)))
               expanded)
              (when changed?
                (vector-set! all-size index (length (vector-ref all index)))
                (vector-set! delta-size index
                  (length (vector-ref delta index)))
                (vector-set! all-version index
                  (+ 1 (vector-ref all-version index)))
                (vector-set! delta-version index
                  (+ 1 (vector-ref delta-version index)))))))
        (def (run!)
         (when dirty?
         (let evaluate-stratum ((stratum 0))
          (when (<= stratum highest-stratum)
            (let ((active-rules []) (active? #t) (round 0))
              (for-each
               (lambda (rule)
                 (let (heads
                       (filter (lambda (head)
                                 (= (vector-ref strata (vector-ref head 0))
                                    stratum))
                               (vector-ref rule 0)))
                   (unless (null? heads)
                     (set! active-rules
                       (cons (vector heads (vector-ref rule 1)
                                     (gerbil-ascent-delta-positions
                                      (vector-ref rule 1) strata stratum))
                             active-rules)))))
               rule-plans)
              (set! active-rules (reverse active-rules))
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
                           (visit-body (cdr body) delta-at depth
                                       (cons (cons (vector-ref clause 2)
                                                   value)
                                             environment)
                                       consume))
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
                      (unless (list? values)
                        (error "ASCENT generator must return a list" values))
                      (for-each
                       (lambda (value)
                         (visit-body (cdr body) delta-at depth
                                     (cons (cons (vector-ref clause 1) value)
                                           environment)
                                     consume))
                       values)))
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
        (if session?
          (validate GerbilAscentSessionContract
                    (.o (:: @ Session.)
                        (.append-source! append-source!)
                        (.run run!)))
          run!)))))

(def (gerbil-ascent-open-session program)
  (gerbil-ascent-make-engine program #t))

(def (gerbil-ascent-session-append-source! session name row)
  ((.ref session '.append-source!) name row))

(def (gerbil-ascent-session-run session)
  ((.ref session '.run)))

(def (gerbil-ascent-evaluate-program program)
  ((gerbil-ascent-make-engine program #f)))
