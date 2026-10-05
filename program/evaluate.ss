;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Generic stratified semi-naive evaluator. Mutable row buffers belong to one
;;; session; public declarations and returned snapshots are POO values.
(import (only-in "actor-round.ss" gerbil-ascent-run-actor-round!)
        (only-in :clan/poo/object .o .ref object?)
        (only-in :clan/poo/mop validate)
        (only-in :std/iter for iter Iterator &Iterator-next!)
        (only-in "admission.ss" gerbil-ascent-initialize-source-row!
                 gerbil-ascent-admit-source-row!
                 gerbil-ascent-check-replacement-rows! gerbil-ascent-prepare-storage-batch)
        (only-in "result.ss" gerbil-ascent-publication-cache
                 gerbil-ascent-publish-rows gerbil-ascent-snapshot-rows gerbil-ascent-snapshot-sizes
                 gerbil-ascent-result-observation)
        (only-in "planning.ss" gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-run-positive-plan!
                 gerbil-ascent-emit-heads!)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance!)
        (only-in "types.ss" GerbilAscentSessionContract)
        (only-in "reuse.ss" gerbil-ascent-prepare-native-reuse
                 gerbil-ascent-activate-rules gerbil-ascent-activate-selected-rules native-reuse?
                 native-reuse-result native-reuse-affected)
        (only-in "analysis.ss" gerbil-ascent-program-analysis
                 gerbil-ascent-program-schema)
        (only-in :gerbil-ascent/core/rule-semantics gerbil-ascent-lattice-feeds-relation?
                 gerbil-ascent-lattice-key
                 gerbil-ascent-lattice-value
                 gerbil-ascent-joined-row)
        (only-in :gerbil-ascent/core/rule-bindings gerbil-ascent-bind-row
                 gerbil-ascent-binding-values
                 gerbil-ascent-call-with-bindings gerbil-ascent-extend-pattern)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?)
        (only-in :gerbil-ascent/table/storage
                 gerbil-ascent-storage-make-state
                 gerbil-ascent-set-batch-admit!
                 gerbil-ascent-canonical-set-storage-provider?)
        (only-in :clan/poo/support/base until))

(export gerbil-ascent-evaluate-program gerbil-ascent-make-engine
        gerbil-ascent-make-updated-engine)

(def Session. (.ref GerbilAscentSessionContract 'proto))

;;; One engine owns all mutable row buffers and indexes. Reused immutable
;;; analysis/schema values never share evaluation-local relation state.

;; gerbil-ascent-make-updated-engine
;; : (forall (p r a s e) (-> p p r a s Boolean e))
;; : (-> SourceSnapshot Program EvaluationResult Analysis Schema Boolean Engine)
;; | doc m%
;;     Build a retained update engine after admitting the completed closure.
;;     Unsupported reuse falls back to a fresh evaluation of accepted sources.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-make-updated-engine previous candidate completed
;;                                      analysis schema #f)
;;     ;; => a retained engine; completed must have finished
;;     ```
;;   %
(def (gerbil-ascent-make-updated-engine previous candidate completed
                                      analysis schema measure-rule-times?)
  (gerbil-ascent-make-engine
   candidate #t analysis schema measure-rule-times? #f
   (gerbil-ascent-prepare-native-reuse previous candidate completed analysis)))

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
                                (plan-error #f)
                                (reuse #f)
                                (workers 1))
  (unless (and (exact-integer? workers) (> workers 0)
               (or (= workers 1) (and (not session?) (not reuse) (not measure-rule-times?))))
    (error "invalid ASCENT parallel evaluation option" workers))
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
           (index-providers (vector-ref schema 5))
           (indexes (gerbil-ascent-make-row-indexes
                     all delta all-size delta-size all-version delta-version index-providers))
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
      (def indexed-rows (row-indexes-rows indexes))
      (def advance-all-indexes! (row-indexes-advance! indexes))
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
                 (if (gerbil-ascent-canonical-set-storage-provider?
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
                           source-materialized-count output-limit))))
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
      ;; Source admission above uses the real prospective input and budgets.
      ;; Seed only independent completed components; never seed affected SCCs.
      (when reuse
        (unless (native-reuse? reuse) (error "invalid native reuse capsule"))
        (let seed ((index 0))
          (when (< index count)
            (unless (vector-ref (native-reuse-affected reuse) index)
              (let* ((rows ((.ref (native-reuse-result reuse) 'rows-of) (vector-ref names index)))
                     (base (vector-ref all index))
                     (check (vector-ref field-checkers index))
                     ;; Set admission already populated this source membership.
                     ;; Lattice admission joins source rows by key instead, so
                     ;; build membership from its final joined source rows.
                     (base-present
                      (and (not check)
                       (if (vector-ref lattice-joins index)
                        (let (membership (make-hash-table))
                          (for-each (lambda (row) (hash-put! membership row #t))
                                    base)
                          membership)
                        (vector-ref seen index))))
                     (present (make-hash-table)))
                (for-each
                 (lambda (row)
                   (unless (and (list? row) (= (length row) (vector-ref arity index)))
                     (error "invalid completed reuse row"))
                   (when check (check row))
                   (unless (hash-get present row)
                     (hash-put! present row #t)
                     ;; User field callbacks retain the original equality walk.
                     (unless (if base-present (hash-get base-present row) (member row base))
                       (set! derived-count (+ derived-count 1))))) rows)
                (when (or (> derived-count derived-limit)
                          (> (+ source-materialized-count derived-count) output-limit))
                  (error "ASCENT reused closure fact budget exceeded"))
                (when (vector-ref lattice-joins index)
                  (let (keyed (make-hash-table))
                    (for-each (lambda (row) (hash-put! keyed (gerbil-ascent-lattice-key row) row)) rows)
                    (vector-set! lattice-rows index keyed)))
                (vector-set! all index (reverse rows))
                (vector-set! seen index present)
                (vector-set! delta index (vector-ref all index))
                (vector-set! all-size index (length rows))
                (vector-set! delta-size index (length rows))))
            (seed (+ index 1)))))
      (let* ((analysis
              ;; Source-only replacement preserves declarations and rules.
              ;; Its session reuses this immutable rule plan while the fresh
              ;; engine still owns new rows, indexes, storage and budgets.
              (or analysis-override
                  (gerbil-ascent-program-analysis
                   program relations rules
                   (lambda ()
                     (gerbil-ascent-prepare-program
                      relations rules schema plan-error)))))
             (rule-plans (vector-ref analysis 2))
             (rule-ticks (and measure-rule-times?
                              (make-vector (length rules) 0)))
             (strata (vector-ref analysis 3))
             (active-by-stratum
              (if reuse
                (gerbil-ascent-activate-selected-rules analysis
                 (native-reuse-affected reuse))
                (gerbil-ascent-activate-rules analysis)))
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
                   (gerbil-ascent-canonical-set-storage-provider?
                    (vector-ref storage-providers 0))))
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
                          (advance-all-indexes! index accepted #t)
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
         ;; One invocation owns the complete round workspace. Clearing slots
         ;; after commit releases pending state while delta keeps its row spine.
         (let (complete? #t)
         (when dirty?
         ;; Completed selected updates instantiate full frames only for later
         ;; dirty work. Clean calls and duplicate-only appends keep cached results;
         ;; partial timeout resumes retain their original selected frames.
         (unless active-by-stratum
           (set! active-by-stratum (gerbil-ascent-activate-rules analysis)))
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
            (def (emit-row! atom row)
              (let* ((index (vector-ref atom 0))
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
                  (if (gerbil-ascent-canonical-set-storage-provider?
                       (vector-ref storage-providers index))
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
            (def (visit-body body delta-at depth environment consume)
              (if (null? body)
                (consume environment)
                (let (clause (car body))
                  (cond
                   ((eq? (vector-ref clause 0) 'atom)
                    (let* ((atom (vector-ref clause 1))
                           (rows (indexed-rows atom environment
                                               (= depth delta-at) #f)))
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
                           (rows (indexed-rows atom environment #f #f)))
                      (unless (ormap
                               (lambda (row)
                                 (gerbil-ascent-bind-row (vector-ref atom 3)
                                           row environment))
                               rows)
                        (visit-body (cdr body) delta-at depth
                                    environment consume))))
                   ((eq? (vector-ref clause 0) 'aggregate)
                    (let* ((atom (vector-ref clause 1))
                           (rows (indexed-rows atom environment #f #f))
                           (variables (vector-ref clause 3))
                           (tuples []))
                      (for-each
                       (lambda (row)
                         (let (bound (gerbil-ascent-bind-row (vector-ref atom 3)
                                                row environment))
                           (when bound
                             (set! tuples
                               (cons (gerbil-ascent-binding-values
                                      variables bound "unbound ASCENT clause variable")
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
                                       (gerbil-ascent-extend-pattern
                                        output matched environment
                                        "ASCENT aggregate pattern returned invalid bindings"))
                                     (cons (cons output value)
                                           environment))))
                             (visit-body (cdr body) delta-at depth
                                         next-environment consume)))
                         values))))
                   ((eq? (vector-ref clause 0) 'guard)
                    (let (pass? (gerbil-ascent-call-with-bindings
                                  (vector-ref clause 2) (vector-ref clause 1)
                                  environment "unbound ASCENT clause variable"))
                      (unless (boolean? pass?)
                        (error "ASCENT guard must return a boolean" pass?))
                      (when pass?
                        (visit-body (cdr body) delta-at depth
                                    environment consume))))
                   ((eq? (vector-ref clause 0) 'generator)
                    (let (values (gerbil-ascent-call-with-bindings
                                  (vector-ref clause 3) (vector-ref clause 2)
                                  environment "unbound ASCENT clause variable"))
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
                    (let (value (gerbil-ascent-call-with-bindings
                                  (vector-ref clause 3) (vector-ref clause 2)
                                  environment "unbound ASCENT clause variable"))
                      (visit-body (cdr body) delta-at depth
                                  (cons (cons (vector-ref clause 1) value)
                                        environment)
                                  consume)))))))
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
          (set! pending-count 0)
            ;; The admitted pure positive subset has no evaluation callbacks.
            ;; Custom index/storage and lattice semantics remain on the serial path.
            (if (and (> workers 1)
                     (andmap (lambda (rule) (vector-ref rule 5)) active-rules)
                     (andmap gerbil-ascent-canonical-set-storage-provider?
                             (vector->list storage-providers))
                     (andmap gerbil-ascent-canonical-hash-index-provider?
                             (vector->list index-providers))
                     (andmap not (vector->list lattice-joins))
                     (andmap not (vector->list field-checkers)))
              (let ((frozen-all (vector-copy all)) (frozen-delta (vector-copy delta))
                    (frozen-all-size (vector-copy all-size)) (frozen-delta-size (vector-copy delta-size))
                    (frozen-all-version (vector-copy all-version)) (frozen-delta-version (vector-copy delta-version)))
                (gerbil-ascent-run-actor-round!
                 ;; Fresh invocation identity binds this program/frontier/round;
                 ;; no runtime generation or round upper bound is introduced.
                 (vector program stratum round frozen-all frozen-delta)
                 active-rules workers
                 (lambda (rule emit! checkpoint!)
                   (let* ((plan (vector-ref rule 5))
                          (frame (make-vector (vector-ref plan 2) #f))
                          (private-indexes
                           (gerbil-ascent-make-row-indexes
                            frozen-all frozen-delta frozen-all-size frozen-delta-size
                            frozen-all-version frozen-delta-version index-providers))
                          (rows (row-indexes-rows private-indexes))
                          (pivots (vector-ref rule 2))
                          (prunable (vector-ref rule 4)))
                     (def (visit! pivot)
                       (gerbil-ascent-run-positive-plan! plan frame pivot rows emit! checkpoint!))
                     (if (null? pivots)
                       (when (and (= round 1) first-run?) (visit! -1))
                       (if (and (= round 1) (or first-run? (> stratum 0)))
                         (visit! -1)
                         (for-each
                          (lambda (pivot)
                            (unless (and (< pivot (vector-length prunable))
                                         (= (vector-ref frozen-delta-size (vector-ref prunable pivot)) 0))
                              (visit! pivot))) pivots)))))
                 emit-row!))
              (begin
            (for-each
             (lambda (rule)
               (let ((started (and rule-ticks (current-jiffy)))
                     (heads (vector-ref rule 0))
                     (body (vector-ref rule 1))
                     (positions (vector-ref rule 2))
                     (prunable (vector-ref rule 4))
                     (positive-plan (vector-ref rule 5))
                     (frame (vector-ref rule 6)))
                 (if (null? positions)
                   (when (and (= round 1) first-run?)
                     (if positive-plan
                       (gerbil-ascent-run-positive-plan!
                        positive-plan frame -1 indexed-rows emit-row!)
                       (visit-body body -1 0 []
                         (lambda (environment)
                           (gerbil-ascent-emit-heads! heads environment emit-row!)))))
                   (if (and (= round 1)
                            (or first-run? (> stratum 0)))
                     ;; At the first round every relation in this stratum has
                     ;; delta = all. One full evaluation covers every delta
                     ;; position without emitting the same join repeatedly.
                     (if positive-plan
                       (gerbil-ascent-run-positive-plan!
                        positive-plan frame -1 indexed-rows emit-row!)
                       (visit-body body -1 0 []
                         (lambda (environment)
                           (gerbil-ascent-emit-heads! heads environment emit-row!))))
                     (for-each
                      (lambda (delta-at)
                        ;; Prefix atoms have no index, expression, pattern or
                        ;; clause callbacks. The empty pivot uses raw rows.
                        (unless (and (< delta-at (vector-length prunable))
                                     (= (vector-ref delta-size
                                          (vector-ref prunable delta-at)) 0))
                          (if positive-plan
                            (gerbil-ascent-run-positive-plan!
                             positive-plan frame delta-at indexed-rows emit-row!)
                            (visit-body body delta-at 0 []
                              (lambda (environment)
                                (gerbil-ascent-emit-heads! heads environment emit-row!))))))
                      positions)))
                 (when started
                   (let (index (vector-ref rule 3))
                     (vector-set! rule-ticks index
                       (+ (vector-ref rule-ticks index)
                          (- (current-jiffy) started)))))))
             active-rules)
              ))
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
                               (gerbil-ascent-canonical-set-storage-provider?
                                (vector-ref storage-providers index))
                               (gerbil-ascent-canonical-hash-index-provider?
                                (vector-ref index-providers index)))
                        (+ (vector-ref all-size index) batch-size)
                        (length (vector-ref all index)))))
                  (vector-set! delta index (vector-ref pending index))
                  (vector-set! delta-size index batch-size)
                  (vector-set! delta-version index
                    (+ 1 (vector-ref delta-version index))))
                (when (pair? (vector-ref pending index))
                  (vector-set! pending index [])
                  (vector-set! pending-lattice-keys index [])
                  (hash-clear! (vector-ref pending-seen index)))
                (commit (+ index 1))))
            (when (and active?
                       (if (vector? deadline) (vector-ref deadline 0) deadline)
                       (>= (current-jiffy)
                           (if (vector? deadline) (vector-ref deadline 0) deadline)))
              (set! resume-stratum stratum)
              (set! resume-round round)
              (set! complete? #f)
              (return #f)))
            (set! resume-stratum #f)
            (set! resume-round 0)
            (evaluate-stratum (+ stratum 1))))))))
         (when complete?
           (set! first-run? #f)
           (set! dirty? #f)
           (set! materialized-dirty? #f))
         (let* ((snapshots
                 (if (vector? deadline)
                     (gerbil-ascent-publish-rows all deadline)
                     (vector-map (lambda (rows) (reverse rows)) all)))
                (observation
                 (gerbil-ascent-result-observation
                  (and reuse (native-reuse-affected reuse)) names active-by-stratum rule-ticks)))
           (set! last-result
             (.o (relation-names (vector->list names))
                 (finished complete?)
                 (evaluation-path (vector-ref observation 0))
                 (reused-relations (vector-ref observation 1))
                 (active-rule-count (vector-ref observation 2))
                 (rule-time-nanoseconds (vector-ref observation 3))
                 (relation-sizes (lambda () (gerbil-ascent-snapshot-sizes names snapshots)))
                 (rows-of (lambda (name)
                            (gerbil-ascent-snapshot-rows
                             (vector-ref snapshots (position-of name)))))))))
         (when (and reuse complete?)
           (set! active-by-stratum #f)
           (set! reuse #f))
         last-result))
        (def (run!)
          (if recompute-from-source?
            last-result
            (run-retained!)))
        (if session?
          (let (published (gerbil-ascent-publication-cache count))
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
                      (gerbil-ascent-canonical-set-storage-provider?
                       (vector-ref storage-providers index))))
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
                       (present (vector-ref seen index)))
                    ;; Preflight owns its forward list; no retained membership,
                    ;; source counter or row buffer changes before it succeeds.
                    (let-values (((new-rows added-count)
                                  (gerbil-ascent-prepare-storage-batch
                                   expanded width (vector-ref field-checkers index)
                                   present (+ source-materialized-count derived-count)
                                   output-limit)))
                      (set! source-count (+ source-count 1))
                      (let ((new-all (vector-ref all index))
                            (new-delta (vector-ref delta index)))
                        (for-each
                         (lambda (stored)
                           (hash-put! present stored #t)
                           (set! new-all (cons stored new-all))
                           (set! new-delta (cons stored new-delta)))
                         new-rows)
                        (vector-set! all index new-all)
                        (vector-set! delta index new-delta))
                      (set! source-materialized-count
                        (+ source-materialized-count added-count))
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
                (gerbil-ascent-check-replacement-rows!
                 name rows width (vector-ref field-checkers index))
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
            (def (run-session!)
              (if recompute-from-source? last-result
                (begin (vector-set! published 0 #f) (run-retained! published))))
            (def (run-timeout! duration-nanoseconds)
              (unless (and (exact-integer? duration-nanoseconds)
                           (>= duration-nanoseconds 0))
                (error "invalid ASCENT timeout in nanoseconds"
                       duration-nanoseconds))
              (if recompute-from-source?
                last-result
                (begin
                  (vector-set! published 0
                    (+ (current-jiffy)
                       (quotient (* duration-nanoseconds (jiffies-per-second))
                                 1000000000)))
                  (run-retained! published))))
          (validate GerbilAscentSessionContract
                    (.o (:: @ Session.)
                        (.append-source!
                         (if single-set-source?
                           append-single-set-source! append-source!))
                        (.replace-source! replace-source!)
                        (.run run-session!)
                        (.run-timeout run-timeout!)
                        (.analysis analysis)
                        (.schema schema)
                        (.recomputed? (lambda () recompute-from-source?))
                        (.source-additions source-additions)
                        (.source-overrides source-overrides))))
          run!)))))

;; : (-> Program EvaluationResult)
(def (gerbil-ascent-evaluate-program program
                                      measure-rule-times?: (measure-rule-times? #f)
                                      workers: (workers 1))
  (unless (boolean? measure-rule-times?)
    (error "invalid ASCENT rule timing option" measure-rule-times?))
  ((gerbil-ascent-make-engine program #f #f #f measure-rule-times? #f #f workers)))
