;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Generic stratified semi-naive evaluator. Mutable row buffers belong to one
;;; session; public declarations and returned snapshots are POO values.
(import :gerbil-ascent/core/relation-view
        (only-in "view-state.ss" gerbil-ascent-view-relation? gerbil-ascent-stage-view!
                 gerbil-ascent-view-journal-event gerbil-ascent-view-export-cut
                 gerbil-ascent-commit-view! gerbil-ascent-empty-view gerbil-ascent-add-frontier)
        (only-in "positive-components.ss" gerbil-ascent-run-positive-components! gerbil-ascent-component-mode?)
        (only-in "actor-round.ss" gerbil-ascent-run-actor-round! gerbil-ascent-actor-round-eligible?)
        (only-in "source-log.ss" gerbil-ascent-source-log-rows)
        (only-in :clan/poo/object .o .ref object?)
        (only-in :clan/poo/mop validate)
        (only-in :std/iter for iter Iterator &Iterator-next!)
        (only-in "initialization.ss" make-initial-source-state gerbil-ascent-initialize-sources!)
        (only-in "admission.ss" gerbil-ascent-admit-source-row!
                 gerbil-ascent-check-replacement-rows! gerbil-ascent-prepare-storage-batch)
        (only-in "result.ss" gerbil-ascent-publication-cache
                 gerbil-ascent-publish-rows gerbil-ascent-snapshot-rows gerbil-ascent-snapshot-sizes
                 gerbil-ascent-result-observation gerbil-ascent-public-snapshot-rows)
        (only-in "planning.ss" gerbil-ascent-prepare-program)
        (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-run-positive-plan!
                 gerbil-ascent-emit-heads!)
        (only-in "index.ss" gerbil-ascent-make-row-indexes row-indexes-rows row-indexes-advance! row-indexes-plan-rules! row-indexes-plan-actions!)
        (only-in "types.ss" GerbilAscentSessionContract)
        (only-in "reuse.ss" gerbil-ascent-prepare-native-reuse
                 gerbil-ascent-activate-rules gerbil-ascent-activate-selected-rules
                 gerbil-ascent-seed-native-reuse! make-closure-seed-state native-reuse-affected)
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
                 gerbil-ascent-storage-owned-states
                 gerbil-ascent-storage-check-state! gerbil-ascent-storage-admit-state!
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
                                (workers 1) (canceled? #f))
  (unless (or (not canceled?) (procedure? canceled?))
    (error "invalid ASCENT cancellation predicate" canceled?))
  (when (and canceled? (or session? reuse measure-rule-times?))
    (error "ASCENT cancellation requires a fresh untimed evaluator"))
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
                     all delta all-size delta-size all-version delta-version index-providers (pair? rules)))
           (storage-extensions (vector-ref schema 6))
           (storage-states (make-vector count #f))
           (seen (make-vector count #f))
           (lattice-joins (vector-ref schema 7))
           (kinds (vector-ref schema 8))
           (storage-providers (vector-ref schema 9))
           (lattice-rows (make-vector count #f))
           (view-generation (gensym 'ascent-source))
           (view-journals (make-vector count []))
           (source-count 0)
           (source-materialized-count 0)
           (derived-count 0)
           (publication-failed? #f))
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
      (def (callback-rows atom environment use-delta? slot-terms)
        (indexed-rows atom environment use-delta? slot-terms #t))
      (def (view-relation? index)
        (gerbil-ascent-view-relation? (vector-ref storage-providers index)
                                     (vector-ref index-providers index)))
      (def (commit-view! index frontier)
        (gerbil-ascent-commit-view! index (vector-ref storage-states index) frontier
          all delta all-size delta-size all-version delta-version
          (vector-ref names index) (cons view-generation source-count) (vector-ref view-journals index)))
      ;; Cache revocation alone cannot undo membership or rows already admitted
      ;; by this engine. A failed index publication requires source reconstruction.
      (def advance-all-indexes!
        (let (advance! (row-indexes-advance! indexes))
          (lambda (index rows (reverse-order? #f))
            (with-catch
             (lambda (failure)
               (set! publication-failed? #t)
               (raise failure))
             (lambda () (advance! index rows reverse-order?))))))
      (call-with-values
       (lambda ()
         (gerbil-ascent-initialize-sources! relations schema
           (make-initial-source-state all delta all-size delta-size
                                      storage-states seen lattice-rows)
           input-limit output-limit))
       (lambda (inputs materialized)
         (set! source-count inputs)
         (set! source-materialized-count materialized)))
      (for-each (lambda (index)
        (when (view-relation? index)
          (vector-set! view-journals index
            (list (gerbil-ascent-view-journal-event 'source (.ref (list-ref relations index) 'rows))))
          (let (frozen (gerbil-ascent-view-export-cut (if (relation-view? (vector-ref all index)) (vector-ref all index)
                          gerbil-ascent-empty-view) (vector-ref view-journals index)))
            (vector-set! all index (gerbil-ascent-view-bind frozen (vector-ref names index)
                                    (cons view-generation source-count) 0 'total))
            (vector-set! delta index
              (gerbil-ascent-view-with-export
                (gerbil-ascent-view-bind frozen (vector-ref names index)
                  (cons view-generation source-count) 0 'delta)
                (lambda () (reverse (gerbil-ascent-view-rows frozen)))))))) (iota count))
      ;; Source admission uses the prospective input and budgets. Reuse owns
      ;; completed-row admission into these same private engine buffers.
      ;; Neither phase can publish a failed prospective Session.
      (when reuse
        (set! derived-count
          (gerbil-ascent-seed-native-reuse! reuse schema
            (make-closure-seed-state all seen delta all-size delta-size lattice-rows)
            source-materialized-count derived-limit output-limit)))
      (let* ((storage-owners (gerbil-ascent-storage-owned-states storage-states))
             (analysis
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
             (_index-layout (row-indexes-plan-rules! indexes rule-plans))
             (rule-ticks (and measure-rule-times?
                              (make-vector (length rules) 0)))
             (strata (vector-ref analysis 3))
             (all-active (gerbil-ascent-activate-rules analysis))
             ;; A later callback may observe rows injected by an earlier pure
             ;; rule. Preserve ordered traversal across the entire program.
             (ordered-execution?
              (not (gerbil-ascent-actor-round-eligible?
                     (apply append (vector->list all-active)) storage-providers
                     index-providers lattice-joins field-checkers)))
             (active-by-stratum
              (if reuse
                (gerbil-ascent-activate-selected-rules analysis
                 (native-reuse-affected reuse))
                all-active))
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
         (for-each gerbil-ascent-storage-check-state! storage-owners)
         (when publication-failed?
           (error "ASCENT engine publication requires source replay"))
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
               (pending-injections (make-vector count []))
               (pending-lattice-keys (make-vector count []))
               (pending-count 0)
               (component-mode? (gerbil-ascent-component-mode? session? workers canceled? analysis schema)))
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
                (cond
                 ((view-relation? index)
                  (let (frontier (gerbil-ascent-stage-view! (vector-ref storage-states index) row
                                  (- output-limit (+ source-materialized-count derived-count pending-count))
                                  (vector-ref field-checkers index)))
                    (when (> (gerbil-ascent-row-count frontier) 0)
                      (vector-set! pending-injections index (cons (map values row) (vector-ref pending-injections index))))
                    (set! pending-count (+ pending-count (gerbil-ascent-row-count frontier)))
                    (vector-set! pending index (gerbil-ascent-add-frontier (vector-ref pending index) frontier))))
                 ((vector-ref lattice-joins index)
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
                        (cons key (vector-ref pending-lattice-keys index))))))
                 (else
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
                       expanded)))))
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
                           (rows (callback-rows atom environment
                                               (= depth delta-at) #f)))
                      (gerbil-ascent-for-each-row
                       (lambda (row)
                         (let (bound (gerbil-ascent-bind-row (vector-ref atom 3)
                                                row environment))
                           (when bound
                             (visit-body (cdr body) delta-at (+ depth 1)
                                         bound consume))))
                       rows)))
                   ((eq? (vector-ref clause 0) 'negation)
                    (let* ((atom (vector-ref clause 1))
                           (rows (callback-rows atom environment #f #f)))
                      (unless (gerbil-ascent-any-row?
                               (lambda (row)
                                 (gerbil-ascent-bind-row (vector-ref atom 3)
                                           row environment))
                               rows)
                        (visit-body (cdr body) delta-at depth
                                    environment consume))))
                   ((eq? (vector-ref clause 0) 'aggregate)
                    (let* ((atom (vector-ref clause 1))
                           (rows (callback-rows atom environment #f #f))
                           (variables (vector-ref clause 3))
                           (tuples []))
                      (gerbil-ascent-for-each-row
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
                    (gerbil-ascent-row-count (vector-ref delta index)))
                  (vector-set! delta-version index
                    (+ 1 (vector-ref delta-version index)))
                  (reset-delta (+ index 1)))))
          (until (not active?)
          (set! round (+ round 1))
          (set! pending-count 0)
            ;; The admitted pure positive subset has no evaluation callbacks.
            ;; Custom index/storage and lattice semantics remain on the serial path.
            (if component-mode?
              (gerbil-ascent-run-positive-components! analysis schema all workers emit-row!
                                                       (or canceled? (lambda () #f)))
            (if (and (or (> workers 1) canceled?)
                     (not ordered-execution?)
                     (gerbil-ascent-actor-round-eligible? active-rules storage-providers
                                                        index-providers lattice-joins field-checkers))
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
                          (_private-layout
                           (row-indexes-plan-actions! private-indexes (vector-ref plan 1)))
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
                 emit-row! (or canceled? (lambda () #f))))
              (begin
            (when canceled? (error "ASCENT cancellation requires pure Set worker rules"))
            (for-each
             (lambda (rule)
               (let ((started (and rule-ticks (current-jiffy)))
                     (heads (vector-ref rule 0))
                     (body (vector-ref rule 1))
                     (positions (vector-ref rule 2))
                     (prunable (vector-ref rule 4))
                     (positive-plan (vector-ref rule 5))
                     (frame (vector-ref rule 6)))
                 (let (rows-access (if ordered-execution? callback-rows indexed-rows))
                 (if (null? positions)
                   (when (and (= round 1) first-run?)
                     (if positive-plan
                       (gerbil-ascent-run-positive-plan!
                        positive-plan frame -1 rows-access emit-row!)
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
                        positive-plan frame -1 rows-access emit-row!)
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
                             positive-plan frame delta-at rows-access emit-row!)
                            (visit-body body delta-at 0 []
                              (lambda (environment)
                                (gerbil-ascent-emit-heads! heads environment emit-row!))))))
                      positions))))
                 (when started
                   (let (index (vector-ref rule 3))
                     (vector-set! rule-ticks index
                       (+ (vector-ref rule-ticks index)
                          (- (current-jiffy) started)))))))
             active-rules)
              ))
            )
            (set! active? #f)
            (let commit ((index 0))
              (when (< index count)
                (if (view-relation? index)
                  (let (frontier (vector-ref pending index))
                    (if (> (gerbil-ascent-row-count frontier) 0)
                      (begin
                             (vector-set! view-journals index
                               (cons (gerbil-ascent-view-journal-event 'derived (reverse (vector-ref pending-injections index)))
                                     (vector-ref view-journals index)))
                             (commit-view! index frontier)
                             (set! derived-count (+ derived-count (gerbil-ascent-row-count frontier)))
                             (set! active? #t))
                      (begin
                             (let (total (vector-ref all index))
                               (vector-set! delta index
                                 (gerbil-ascent-view-bind gerbil-ascent-empty-view
                                   (relation-view-identity total) (relation-view-generation total)
                                   (relation-view-revision total) 'delta)))
                             (vector-set! delta-size index 0)))
                    (vector-set! pending index [])
                    (vector-set! pending-injections index []))
                  (begin
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
                ))
                (commit (+ index 1))))
            ;; Private storage state becomes reusable only after the entire
            ;; round has published rows, membership, versions and indexes.
            (for-each gerbil-ascent-storage-admit-state! storage-owners)
            ;; Every required SCC is already closed; this one owner commit
            ;; installs the complete cut, without another shared solver round.
            (when component-mode? (set! active? #f))
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
                     (gerbil-ascent-publish-rows all deadline all-size)
                     (vector-map (lambda (rows) (if (relation-view? rows) rows (reverse rows))) all)))
                (sizes (vector-copy all-size))
                (representations (map (lambda (name rows size)
                                   (list name (if (relation-view? rows) 'rectangles 'explicit)
                                         size (if (relation-view? rows) (relation-view-units rows) size)))
                                     (vector->list names) (vector->list all) (vector->list sizes)))
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
                 (representation-observation (lambda () (map (lambda (row) (map values row)) representations)))
                 (relation-sizes (lambda () (map cons (vector->list names) (vector->list sizes))))
                 (rows-of (lambda (name)
                            (gerbil-ascent-public-snapshot-rows
                             (vector-ref snapshots (position-of name)) session?)))))))
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
                  (gerbil-ascent-source-log-rows (vector-ref source-originals index)
                                                (vector-ref source-additions index))))
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
              ;; A successful replacement retires the incremental frames.
              ;; Subsequent appends evaluate a fresh candidate from source logs.
              (unless recompute-from-source?
                (for-each gerbil-ascent-storage-check-state! storage-owners)
                (when publication-failed?
                  (error "ASCENT engine publication requires source replay")))
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
                         ;; Retained publication owns public list/row reads even
                         ;; when the enclosing engine adopts only this result.
                         (result ((.ref (gerbil-ascent-make-engine
                                         candidate #t analysis schema
                                         measure-rule-times?) '.run))))
                    (set! source-count (+ source-count 1))
                    (vector-set! source-overrides index replacement)
                    (vector-set! source-additions index [])
                    (set! recompute-from-source? #t)
                    (set! dirty? #f)
                    (set! last-result result)))
                 (else
                  (cond
                   ((view-relation? index)
                    (flush-staged-set-rows!)
                    (let (frontier (gerbil-ascent-stage-view! (vector-ref storage-states index) row
                                    (- output-limit (+ source-materialized-count derived-count))
                                    (vector-ref field-checkers index)))
                      (set! source-count (+ source-count 1))
                      (when (> (gerbil-ascent-row-count frontier) 0)
                        (set! dirty? #t) (set! materialized-dirty? #t)
                        (set! source-materialized-count (+ source-materialized-count (gerbil-ascent-row-count frontier)))
                        (vector-set! view-journals index
                          (cons (gerbil-ascent-view-journal-event 'source (list row)) (vector-ref view-journals index)))
                        (commit-view! index (gerbil-ascent-add-frontier (vector-ref delta index) frontier)))))
                   (built-in-set? (append-set-source! index row))
                   (else
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
                        (+ 1 (vector-ref delta-version index)))))))))))
                (unless (or (vector-ref source-overrides index)
                            built-in-set?)
                  (vector-set! source-additions index
                    (cons row (vector-ref source-additions index))))
                (gerbil-ascent-storage-admit-state!
                 (vector-ref storage-states index))))
            (def (append-single-set-source! name row)
              (when publication-failed?
                (error "ASCENT engine publication requires source replay"))
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
                ;; Failed incremental admission may have advanced its counter
                ;; before recording a source. Count the complete prospective
                ;; source cut, including duplicates, before fresh evaluation.
                (let* ((candidate (source-program-with index rows))
                       (next-count
                        (apply + (map (lambda (relation)
                                        (length (.ref relation 'rows)))
                                      (.ref candidate 'relations)))))
                  (when (> next-count input-limit)
                    (error "ASCENT session input fact budget exceeded"))
                  (let (result ((.ref (gerbil-ascent-make-engine
                                       candidate #t analysis schema
                                       measure-rule-times?) '.run)))
                    (set! source-count next-count)
                    (vector-set! source-overrides index rows)
                    (vector-set! source-additions index [])
                    (set! recompute-from-source? #t)
                    (set! publication-failed? #f)
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
                                      workers: (workers 1)
                                      canceled?: (canceled? #f))
  (unless (boolean? measure-rule-times?)
    (error "invalid ASCENT rule timing option" measure-rule-times?))
  ((gerbil-ascent-make-engine program #f #f #f measure-rule-times? #f #f workers canceled?)))
