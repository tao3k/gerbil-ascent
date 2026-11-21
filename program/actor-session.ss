;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :gerbil/runtime/control with-unwind-protect)
        (only-in :std/sync/completion make-completion completion-wait! completion-post!
                 completion-reset! completion-error!)
        (only-in :gerbil-ascent/core/actor-envelope
                 gerbil-ascent-send-envelope! gerbil-ascent-match-envelope!)
        (only-in :gerbil-ascent/core/execution-control
                 current-ascent-execution-control ascent-execution-checkpoint! ascent-accept-publication!)
        (only-in :gerbil-ascent/core/positive-plan
                 current-positive-plan-cost gerbil-ascent-pure-positive-plan?)
        (only-in :gerbil-ascent/core/relation-view relation-view-count)
        (only-in "source-cut.ss" gerbil-ascent-make-source-cut
                 gerbil-ascent-source-cut-rows gerbil-ascent-source-cut-update
                 gerbil-ascent-source-cut-terminal-slot gerbil-ascent-source-cut-edit-edge
                 source-slot-newest-first source-slot-count source-slot-view source-slot-rows
                 source-slot-binary-visitor source-slot-validated-binary-view source-slot-packed-extra)
        (only-in "component-worker.ss" gerbil-ascent-functional-result-view
                 gerbil-ascent-branching-result-view gerbil-ascent-replay-branching-frontier)
        (only-in "condensed-closure.ss" gerbil-ascent-condense-closure
                 gerbil-ascent-extend-condensed-closure condensed-closure?
                 gerbil-ascent-condensed-same-partition?
                 gerbil-ascent-remove-condensed-edge
                 condensed-closure-source condensed-closure-size gerbil-ascent-condensed-closure-view
                 gerbil-ascent-condensed-witness gerbil-ascent-verify-condensed-witness)
        (only-in "result.ss" gerbil-ascent-make-published-result gerbil-ascent-result-observation)
        (only-in "update-selection.ss" gerbil-ascent-actor-update-eligible?)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/type validate)
        (only-in "types.ss" GerbilAscentSessionContract gerbil-ascent-canonical-actor-inputs?
                 gerbil-ascent-projection-tree-current?)
        (only-in "evaluate.ss" gerbil-ascent-make-engine gerbil-ascent-make-engine-state)
        (only-in "engine-state.ss" engine-state-schema engine-state-analysis)
        (only-in "positive-components.ss" gerbil-ascent-component-mode?))
(export gerbil-ascent-open-actor-session gerbil-ascent-open-condensed-actor-session
        gerbil-ascent-session-cancel! gerbil-ascent-session-edit-edge!
        gerbil-ascent-session-last-completed gerbil-ascent-session-close!
        gerbil-ascent-session-state)

(defstruct actor-run (epoch token worker monitor reply authority sources accept-result fallback) final: #t)
(defstruct actor-job (epoch evaluate) final: #t)
(defstruct actor-edge-edit (insert? row) final: #t)
(defstruct actor-engine (run token) final: #t)
(defstruct state-request (reply) final: #t)

(def Session. (.ref GerbilAscentSessionContract 'proto))

(def (session-failure message)
  (with-catch (lambda (failure) failure) (lambda () (error message))))

;; Match the admitted terms and relation ordinals, independent of DSL names.
(def (binary-identity-rule rule)
  (let (plan (vector-ref rule 5))
    (and (gerbil-ascent-pure-positive-plan? plan)
         (= (vector-ref plan 2) 2)
         (let ((heads (vector-ref plan 0)) (body (vector-ref plan 1)))
           (and (pair? heads) (null? (cdr heads))
                (pair? body) (null? (cdr body))
                (let* ((head (car heads))
                       (read (car body))
                       (atom (vector-ref read 0))
                       (source (vector-ref atom 0))
                       (target (vector-ref (vector-ref head 0) 0)))
                  (and (not (= source target))
                       (null? (vector-ref atom 2))
                       (equal? (vector-ref read 1) '((fresh . 0) (fresh . 1)))
                       (equal? (vector-ref head 1) '((bound . 0) (bound . 1)))
                       (cons source target))))))))

(def (ranked-closure-rule? rule source target)
  (let (plan (vector-ref rule 5))
    (and (gerbil-ascent-pure-positive-plan? plan)
         (= (vector-ref plan 2) 3)
         (memv 0 (vector-ref rule 2))
         (let ((heads (vector-ref plan 0)) (body (vector-ref plan 1)))
           (and (pair? heads) (null? (cdr heads))
                (pair? body) (pair? (cdr body)) (null? (cddr body))
                (let* ((head (car heads)) (left (car body)) (right (cadr body))
                       (self (vector-ref left 0)) (edge (vector-ref right 0)))
                  (and (= target (vector-ref (vector-ref head 0) 0))
                       (= target (vector-ref self 0))
                       (= source (vector-ref edge 0))
                       (null? (vector-ref self 2)) (equal? (vector-ref edge 2) '(0))
                       (equal? (vector-ref left 1) '((fresh . 0) (fresh . 1)))
                       (equal? (vector-ref right 1) '((bound . 1) (fresh . 2)))
                       (equal? (vector-ref head 1) '((bound . 0) (bound . 2))))))))))

(defstruct actor-terminal-plan (source target recursive?) final: #t)

(def (actor-terminal-analysis analysis arities)
  (let* ((strata (vector-ref analysis 5))
         (rules (and (= (vector-length strata) 1) (vector-ref strata 0))))
    (and (= (vector-length arities) 2)
         (= (vector-ref arities 0) 2) (= (vector-ref arities 1) 2)
         (pair? rules)
         (let (first (binary-identity-rule (car rules)))
           (cond
             ((null? (cdr rules))
              (and first (make-actor-terminal-plan (car first) (cdr first) #f)))
             ((and (pair? (cdr rules)) (null? (cddr rules)))
              (let* ((base (or first (binary-identity-rule (cadr rules))))
                     (step (if first (cadr rules) (car rules))))
                (and base (ranked-closure-rule? step (car base) (cdr base))
                     (make-actor-terminal-plan (car base) (cdr base) #t))))
             (else #f))))))

(def (actor-token-canceled? token)
  ;; Compare-and-swap returns the previous word. A false-to-false change
  ;; observes the token without clearing a cancellation or taking a mutex.
  (vector-cas! token 0 #f #f))

(def (actor-check-token! token)
  (when (actor-token-canceled? token) (error "ASCENT actor Session canceled")))

(def (build-condensed-closure source size visit-binary previous check!)
  (or (and (condensed-closure? previous)
           (let (prior (condensed-closure-source previous))
             (if (eq? source prior)
               (cons previous 'reused)
               (case (- size (condensed-closure-size previous))
                 ((1)
                  (let (edge
                        (if visit-binary
                          (source-slot-packed-extra source prior check! #t)
                          (let (rows (source-slot-newest-first source))
                            (and (eq? (cdr rows) (source-slot-newest-first prior)) (car rows)))))
                    (and edge
                         (alet (index (gerbil-ascent-extend-condensed-closure
                                       previous source size edge check! (and visit-binary #t)))
                           (cons index
                             (if (gerbil-ascent-condensed-same-partition? previous index)
                               (if visit-binary 'inserted 'appended)
                               'rebuilt))))))
                 ((-1)
                  (alet* ((edge (source-slot-packed-extra prior source check!))
                          (index (gerbil-ascent-remove-condensed-edge previous source size edge check!)))
                    (cons index
                      (if (gerbil-ascent-condensed-same-partition? previous index)
                        'removed 'rebuilt))))
                 (else #f)))))
      (alet (index (gerbil-ascent-condense-closure source size
                    (or visit-binary
                        (lambda (consume)
                          (for-each (lambda (row) (consume (car row) (cadr row)))
                                    (source-slot-newest-first source))))
                    check!))
        (cons index 'rebuilt))))

(def (build-condensed-edit source size previous (edit :- actor-edge-edit) check!)
  (let (index
         (if edit.insert?
           (gerbil-ascent-extend-condensed-closure previous source size edit.row check! #f #t)
           (gerbil-ascent-remove-condensed-edge previous source size edit.row check! #t)))
    (unless index (error "ASCENT edge edit requires known endpoints and a change in edge membership"))
    (cons index
      (if (gerbil-ascent-condensed-same-partition? previous index)
        (if edit.insert? 'inserted 'removed)
        (if edit.insert? 'merged-local 'split-local)))))

(def (actor-terminal-result program schema analysis (plan :- actor-terminal-plan) sources token
                            committed previous-frontier condense? version (edit #f))
  (let* ((input-limit (.ref program 'max-input-facts))
         (derived-limit (.ref program 'max-derived-facts))
         (output-limit (.ref program 'max-output-facts))
         (source (gerbil-ascent-source-cut-terminal-slot sources plan.source plan.target
                   input-limit output-limit)))
    (and source
         (let* ((count (source-slot-count source))
                (room (min derived-limit (- output-limit count)))
                (validated-view #f) (condensed #f) (update-kind #f)
                (evaluation
                 (if plan.recursive?
                   (and (or edit
                            (and condense? (condensed-closure? previous-frontier)
                                 (eq? source (condensed-closure-source previous-frontier)))
                            (and (>= room count) (>= count 32)))
                        (let ((visit-binary (and (not edit) (source-slot-binary-visitor source)))
                              (check! (if (and edit (current-ascent-execution-control))
                                        (lambda ()
                                          (actor-check-token! token)
                                          (ascent-execution-checkpoint! 1 0))
                                        (lambda () (actor-check-token! token))))
                              (prior (and (not (eq? sources committed))
                                          (gerbil-ascent-source-cut-terminal-slot committed plan.source plan.target
                                            input-limit output-limit))))
                          (def (newest-first) (source-slot-newest-first source))
                          (or (and condense?
                                   (alet* ((candidate
                                            (if edit
                                              (build-condensed-edit source count previous-frontier edit check!)
                                              (build-condensed-closure source count visit-binary
                                                previous-frontier check!)))
                                           (index (car candidate))
                                           ;; Keep the metered walk's exact per-target charges.
                                           (view (gerbil-ascent-condensed-closure-view index version room check!
                                                   (and edit (not (current-ascent-execution-control))))))
                                     (set! condensed index)
                                     (set! update-kind (cdr candidate))
                                     (unless (source-slot-view source)
                                       (set! validated-view (source-slot-validated-binary-view source)))
                                     (cons view index)))
                              (and (not edit)
                                   (or (and previous-frontier (not (condensed-closure? previous-frontier))
                                            (gerbil-ascent-replay-branching-frontier (newest-first) count room check!
                                              previous-frontier))
                                       (let (functional
                                              (gerbil-ascent-functional-result-view
                                                (and (not visit-binary) (newest-first)) count room check! visit-binary))
                                         (when (and functional (not (source-slot-view source)))
                                           (set! validated-view (source-slot-validated-binary-view source)))
                                         functional)
                                       (let (rows (newest-first))
                                         (gerbil-ascent-branching-result-view rows count room check!
                                           (and prior (= count (+ (source-slot-count prior) 1))
                                                (eq? (cdr rows) (source-slot-newest-first prior))))))))))
                   (and (<= count room) (source-slot-view source))))
                (target (if (pair? evaluation) (car evaluation) evaluation)))
           (and target
                (let* ((names (vector-ref schema 1))
                       (positions (vector-ref schema 4))
                       (sizes (make-vector 2 count))
                       (views (make-vector 2 (or (source-slot-view source) validated-view
                                                 (source-slot-rows source)))))
                  (actor-check-token! token)
                  (when edit (ascent-execution-checkpoint! 0 (+ count (relation-view-count target))))
                  (vector-set! sizes plan.target (relation-view-count target))
                  (vector-set! views plan.target target)
                  (let (result
                        (gerbil-ascent-make-published-result names (vector-ref schema 2) views sizes
                          (map (lambda (name size) (list name 'explicit size size))
                               (vector->list names) (vector->list sizes))
                          (gerbil-ascent-result-observation #f names (vector-ref analysis 5) #f)
                          (lambda (name)
                            (let (slot (hash-get positions name))
                              (unless slot (error "unknown ASCENT relation" name))
                              (- slot 1)))
                          #t #t))
                    (vector #t
                      (if condensed
                        (.o (:: @ result)
                            evaluation-path: 'condensed-closure
                            closure-update: update-kind
                            closure-witness: (lambda (from to budget)
                              (gerbil-ascent-condensed-witness condensed version from to budget))
                            verify-closure-witness: (lambda (proof)
                              (gerbil-ascent-verify-condensed-witness condensed version proof)))
                        result)
                      #f #t (and (pair? evaluation) (cdr evaluation))))))))))

;;; Only the owner mutates source cuts, generation and publication. A run owns
;;; a private evaluator; its monitor cannot publish. Cancel credit is observed by
;;; the evaluator's round owner at traversal/batch checkpoints, never by polling
;;; the Session mailbox from a compute worker. Generation Naturals are unbounded.
;; gerbil-ascent-open-actor-session
;; : (-> PurePositiveSetProgram workers: PositiveInteger ActorSession)
;; | doc m%
;;     Admit detached source cuts before transferring them to the Session owner.
;;     Only that owner publishes a prepared transaction or a completed run;
;;     canceled and failed runs restore the last committed cut.
;;     Omitted workers use the active VM processor count (at least one).
;;     Explicit workers remain a caller-owned positive capacity limit.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-open-actor-session program workers: 4)
;;     ;; => a Session with isolated source ownership and bounded workers
;;     ```
;;   %
(def (gerbil-ascent-open-actor-session program
                                      workers: (workers (max 1 (##current-vm-processor-count)))
                                      required?: (required? #t))
  (open-actor-session program workers required? #f))

;; Opt-in binary reachability Session with ordered, detached full exports.
(def (gerbil-ascent-open-condensed-actor-session program)
  (open-actor-session program 1 #t #t))

(def (open-actor-session program workers required? condense?)
  (unless (and (exact-integer? workers) (> workers 0))
    (error "invalid ASCENT actor Session capacity" workers))
  (let* ((admitted (gerbil-ascent-make-engine-state program))
         (schema (engine-state-schema admitted))
         (analysis (engine-state-analysis admitted)))
    (cond
     ((gerbil-ascent-component-mode? #f workers #t analysis schema)
      (make-actor-session program workers schema analysis condense?))
     (required? (error "ASCENT actor Session requires pure positive Set rules"))
     (else #f))))

(def (make-actor-session program workers schema analysis condense?)
  (let* ((relations (.ref program 'relations))
         (input-limit (.ref program 'max-input-facts))
         (positions (vector-ref schema 4)) (arities (vector-ref schema 2))
         (projection (and (= workers 1) (= (##current-vm-processor-count) 1)
                          (actor-terminal-analysis analysis arities)))
         (initial (gerbil-ascent-make-source-cut positions arities
                    (map (lambda (relation) (cons (.ref relation 'name) (.ref relation 'rows))) relations)
                    (and projection (actor-terminal-plan-source projection))
                    (and projection (actor-terminal-plan-recursive? projection))))
         (gate (make-mutex 'ascent-session-lifecycle)) (closed? #f)
         (state-spare (vector #f))
         (owner
          (parameterize ((current-ascent-execution-control #f))
           (spawn/name 'ascent-session-owner
           (lambda ()
             (let ((pending initial) (committed initial) (published #f) (retained #f)
                   (snapshot-source #f) (snapshot-relations #f)
                   (source-indexes (and (= workers 1) (make-vector (vector-length arities) #f)))
                   (generation 0) (running #f) (closing [])
                   (resident #f) (resident-monitor #f) (branching-frontier #f))
               (def (reply! channel value) (completion-post! channel value))
               (def (read-state)
                 (list generation
                   (if running
                     (if (= generation (actor-run-epoch running)) 'running 'draining)
                     'idle)))
               (def (snapshot sources)
                 ;; Compute outside the POO slot scope: `relations` inside its
                 ;; own slot expression would resolve recursively to that slot.
                 (unless (eq? sources snapshot-source)
                   (set! snapshot-relations
                     (map (lambda (relation position)
                            (.o (:: @ relation) rows: (gerbil-ascent-source-cut-rows sources position)))
                          relations (iota (length relations))))
                   (set! snapshot-source sources))
                 ;; Reuse owned row declarations, not lazy Program slots or results.
                 (.o (:: @ program) relations: snapshot-relations))
               (def (mark-canceled!)
                 (when running
                   (set! generation (+ generation 1))
                   (vector-cas! (actor-run-token running) 0 #t #f)))
               (def (update! replacements append?)
                 (when running (error "ASCENT actor Session source update while running"))
                 (let (next (gerbil-ascent-source-cut-update pending positions arities replacements append? input-limit))
                   (set! pending next)
                   (set! retained #f)
                   (set! snapshot-source #f) (set! snapshot-relations #f)
                   (set! generation (+ generation 1)) (void)))
               ;; Only the owner performs final acceptance and publication.
               ;; A worker cannot freeze caller cancellation before this point.
               (def (owns-run? epoch worker)
                 (and running (= epoch (actor-run-epoch running))
                      (eq? worker (actor-run-worker running))))
               (def (finish! epoch worker outcome)
                 (when (owns-run? epoch worker)
                   (let (monitor (actor-run-monitor running))
                     (when monitor (thread-join! monitor)))
                   (let (outcome
                          (if (and (= epoch generation) (vector-ref outcome 0))
                            (with-catch (lambda (failure) (vector #f failure))
                              (lambda ()
                                (parameterize ((current-ascent-execution-control
                                                (actor-run-authority running)))
                                  (let (accept-result (actor-run-accept-result running))
                                    (if (vector-ref outcome 3)
                                      (begin
                                        (when (and accept-result
                                                   (not (eq? #t (accept-result (vector-ref outcome 1)))))
                                          (error "ASCENT replacement result was not accepted"))
                                        (ascent-accept-publication!))
                                      (begin
                                        (when accept-result
                                          (error "batch source replacement did not complete"))
                                        (ascent-execution-checkpoint!)))))
                                outcome))
                            outcome))
                     (if (and (= epoch generation) (vector-ref outcome 0))
                       (begin
                         (when (vector-ref outcome 3)
                           (set! pending (actor-run-sources running))
                           (set! committed pending)
                           (set! published (vector-ref outcome 1))
                           (set! branching-frontier
                             (and (> (vector-length outcome) 4) (vector-ref outcome 4))))
                         (set! retained (vector-ref outcome 2))
                         (reply! (actor-run-reply running) (vector #t (vector-ref outcome 1))))
                       (begin
                         (set! pending committed)
                         (set! retained #f)
                         (when source-indexes (vector-fill! source-indexes #f))
                         (set! snapshot-source #f)
                         (set! snapshot-relations #f)
                         (reply! (actor-run-reply running)
                           (if (= epoch generation) outcome
                             (vector #f (session-failure "ASCENT actor Session canceled")))))))
                   (set! running #f)))
               (def (terminal-result sources token version (edit #f))
                 (and (not (current-positive-plan-cost))
                      (= (##current-vm-processor-count) 1)
                      (gerbil-ascent-projection-tree-current? program)
                      (andmap (lambda (relation)
                                (and (null? (.ref relation 'field-predicates))
                                     (not (.ref relation 'checked-domain))))
                              relations)
                      (actor-terminal-result program schema analysis projection sources token
                        committed branching-frontier condense? version edit)))
               (def (start-ordinary! epoch token channel authority sources accept-result evaluate)
                 (let* ((session-owner (current-thread))
                        (worker (spawn/name 'ascent-session-evaluation evaluate))
                        (monitor
                         (spawn/name 'ascent-session-monitor
                           (lambda ()
                             (let (outcome
                                    (with-catch (lambda (failure) (vector #f failure))
                                      (lambda () (thread-join! worker))))
                               (thread-send session-owner ['terminal epoch worker outcome]))))))
                   (set! running
                     (make-actor-run epoch token worker monitor channel authority sources accept-result #f))))
               (def (ensure-resident!)
                 (unless resident
                   (let* ((session-owner (current-thread))
                          (worker
                           (spawn/name 'ascent-session-terminal
                             (lambda ()
                               (let loop ()
                                 (let (job (thread-receive))
                                   (when job
                                     (let (outcome
                                           (with-catch (lambda (failure) (vector #f failure))
                                             (actor-job-evaluate job)))
                                       (thread-send session-owner
                                         ['resident-terminal (actor-job-epoch job) (current-thread) outcome]))
                                     (loop)))))))
                          (monitor
                           (spawn/name 'ascent-session-terminal-monitor
                             (lambda ()
                               (with-catch
                                 (lambda (failure)
                                   (thread-send session-owner ['resident-exit worker failure]))
                                 (lambda () (thread-join! worker)))))))
                     (set! resident worker)
                     (set! resident-monitor monitor))))
               (def (start-resident! epoch token channel authority sources accept-result evaluate fallback)
                 (ensure-resident!)
                 (let (worker resident)
                   (set! running
                     (make-actor-run epoch token worker #f channel authority sources accept-result fallback))
                   (with-catch
                     (lambda (failure) (finish! epoch worker (vector #f failure)))
                     (lambda () (thread-send worker (make-actor-job epoch evaluate))))))
               (def (finish-resident! epoch worker outcome)
                 (when (owns-run? epoch worker)
                   (if (eq? outcome 'declined)
                     (if (= epoch generation)
                       (with-catch (lambda (failure) (finish! epoch worker (vector #f failure)))
                         (actor-run-fallback running))
                       (finish! epoch worker (vector #f (session-failure "ASCENT actor Session canceled"))))
                     (finish! epoch worker outcome))))
               (def (forget-resident! worker failure)
                 (when (eq? worker resident)
                   (thread-join! resident-monitor)
                   (set! resident #f)
                   (set! resident-monitor #f)
                   (when (and running (eq? (actor-run-worker running) worker))
                     (finish! (actor-run-epoch running) worker (vector #f failure)))))
               (def (stop-resident!)
                 (when resident
                   (thread-send resident #f)
                   (thread-join! resident-monitor)))
               (def (evaluate-cut cut sources owned? previous token duration authority allow-terminal? epoch)
                 (with-catch (lambda (failure) (vector #f failure))
                   (lambda ()
                     (parameterize
                         ((current-ascent-execution-control
                           (and authority
                                (lambda (work facts)
                                  (authority (if (= work -1) 0 work) facts)))))
                       (ascent-execution-checkpoint!)
                       (let (projected
                             (and allow-terminal? projection owned? (not duration) (not authority)
                                  (terminal-result sources token epoch)))
                         (if projected
                           projected
                           (let* ((retain? (and (= workers 1) owned?
                                                (gerbil-ascent-projection-tree-current? program)
                                                (gerbil-ascent-actor-update-eligible? program sources)))
                                  (candidate (or (and retain? previous)
                                                 (make-actor-engine #f (vector #f)))))
                             (def (canceled?)
                               (let (active (vector-ref (actor-engine-token candidate) 0))
                                 (and active (actor-token-canceled? active))))
                             (ascent-execution-checkpoint!)
                             (dynamic-wind
                               (lambda () (vector-set! (actor-engine-token candidate) 0 token))
                               (lambda ()
                                 (unless (actor-engine-run candidate)
                                   (actor-engine-run-set! candidate
                                     (gerbil-ascent-make-engine cut #f analysis schema
                                       #f #f #f workers canceled? #f sources owned?
                                       (and owned? source-indexes) retain?)))
                                 (let (result ((actor-engine-run candidate) duration))
                                   (vector #t result (and retain? candidate) (.ref result 'finished))))
                               (lambda () (vector-set! (actor-engine-token candidate) 0 #f))))))))))
               (def (start-run! channel authority duration (accept-result #f) (replacements #f))
                 (when (or running (pair? closing)) (error "ASCENT actor Session is busy"))
                 (let (sources
                        (if accept-result
                          (begin
                            (unless (eq? pending committed)
                              (error "batch replacement requires a completed clean session"))
                            (unless (pair? replacements)
                              (error "batch replacement requires at least one source"))
                            (gerbil-ascent-source-cut-update
                             committed positions arities replacements #f input-limit))
                          pending))
                   (set! generation (+ generation 1))
                   (let* ((owned? (gerbil-ascent-canonical-actor-inputs? program relations))
                          (previous (and (eq? sources pending) retained))
                          (cut (if owned? program (snapshot sources)))
                          (_ (when (and source-indexes (not owned?))
                               (vector-fill! source-indexes #f)))
                          (epoch generation)
                          (token (vector #f)))
                     (def (ordinary! allow-terminal?)
                       (start-ordinary! epoch token channel authority sources accept-result
                         (lambda () (evaluate-cut cut sources owned? previous token duration authority allow-terminal? epoch))))
                     (if (and projection owned? (not duration) (not authority)
                              (not accept-result) (not (current-positive-plan-cost))
                              (= (##current-vm-processor-count) 1))
                       (start-resident! epoch token channel authority sources accept-result
                         (lambda ()
                           (ascent-execution-checkpoint!)
                           (or (terminal-result sources token epoch) 'declined))
                         (lambda () (ordinary! #f)))
                       (ordinary! #t)))))
               (def (start-edge-edit! channel authority expected name operation left right)
                 (when (or running (pair? closing)) (error "ASCENT actor Session is busy"))
                 (unless (and published (eq? expected published) (eq? pending committed))
                   (error "ASCENT edge edit requires the current completed Result and a clean Session"))
                 (unless (and condense? projection (actor-terminal-plan-recursive? projection)
                              (condensed-closure? branching-frontier)
                              (gerbil-ascent-canonical-actor-inputs? program relations)
                              (eqv? (hash-get positions name) (+ 1 (actor-terminal-plan-source projection))))
                   (error "ASCENT edge edit requires a condensed Session source"))
                 (unless (and (memq operation '(insert delete)) (fixnum? left) (fixnum? right))
                   (error "invalid ASCENT edge edit" operation left right))
                 (ascent-execution-checkpoint!)
                 (let* ((insert? (eq? operation 'insert))
                        (sources (gerbil-ascent-source-cut-edit-edge committed
                                   (actor-terminal-plan-source projection) insert? left right input-limit))
                        (edit (make-actor-edge-edit insert? (list left right)))
                        (epoch (+ generation 1))
                        (token (vector #f)))
                   (set! generation epoch)
                   (start-resident! epoch token channel authority sources #f
                     (lambda ()
                       (parameterize ((current-ascent-execution-control authority))
                         (ascent-execution-checkpoint!)
                         (or (terminal-result sources token epoch edit)
                             (error "ASCENT edge edit could not publish within the admitted fact limits"))))
                     #f)))
               (def (dispatch-request! channel authority operation args)
                 (with-catch (lambda (failure) (reply! channel (vector #f failure)))
                   (lambda ()
                     (parameterize ((current-ascent-execution-control authority))
                       (case operation
                         ((run) (start-run! channel authority (if (null? args) #f (car args))))
                         ((edit-edge) (apply start-edge-edit! channel authority args))
                         ((replace-and-run)
                          (start-run! channel authority #f (cadr args) (car args)))
                         ((append) (update! (list (cons (car args) (list (cadr args)))) #t) (reply! channel (vector #t (void))))
                         ((replace) (update! (list (cons (car args) (cadr args))) #f) (reply! channel (vector #t (void))))
                         ((replace-many) (update! (car args) #f) (reply! channel (vector #t (void))))
                         ((cancel) (mark-canceled!) (reply! channel (vector #t (if running 'draining 'idle))))
                         ((result) (reply! channel (vector #t published)))
                         ((state) (reply! channel (vector #t (read-state))))
                         ((close) (mark-canceled!) (set! closing (cons channel closing))))))))
               (def (dispatch-message! message)
                 (if (state-request? message)
                   (let (reply (state-request-reply message))
                     (with-catch (lambda (failure) (completion-error! reply failure))
                       (lambda () (completion-post! reply (read-state)))))
                   (gerbil-ascent-match-envelope! message
                     (['request channel authority operation args]
                      (dispatch-request! channel authority operation args))
                     (else
                       (match message
                         (['terminal epoch worker outcome] (finish! epoch worker outcome))
                         (['resident-terminal epoch worker outcome]
                          (finish-resident! epoch worker outcome))
                         (['resident-exit worker failure]
                          (forget-resident! worker failure)))))))
               (let loop ()
                 (dispatch-message! (thread-receive))
                 (if (and (pair? closing) (not running))
                   (begin
                     (mutex-lock! gate) (set! closed? #t) (mutex-unlock! gate)
                     ;; No requests accepted after closed? is set. Drain requests
                     ;; already admitted through gate before terminating owner.
                     (let drain ()
                       (let (message (thread-receive 0 #f))
                         (when message
                           (if (state-request? message)
                             (completion-error! (state-request-reply message)
                               (session-failure "ASCENT actor Session closed"))
                             (gerbil-ascent-match-envelope! message
                               (['request channel authority operation args]
                                (if (eq? operation 'close)
                                  (set! closing (cons channel closing))
                                  (reply! channel (vector #f (session-failure "ASCENT actor Session closed")))))
                               (else
                                (match message
                                  (['resident-exit worker failure] (forget-resident! worker failure))
                                  (else (void))))))
                           (drain))))
                     (stop-resident!)
                     (for-each (lambda (channel) (reply! channel (vector #t (void)))) closing))
                   (loop)))))))))
    (def (request operation . args)
      ;; A checker/getter running on this coordinator cannot synchronously
      ;; wait for the coordinator's own mailbox. Refuse before allocating a
      ;; reply endpoint so the surrounding operation can recover normally.
      (when (eq? (current-thread) owner)
        (error "ASCENT actor Session request from its owner"))
      ;; A fresh one-shot completion leaves both caller messages and their
      ;; selective-receive cursor untouched. Never reset or share this endpoint.
      (let* ((authority (current-ascent-execution-control))
             (reply (make-completion 'ascent-session-request))
             (outcome
              (begin
                (mutex-lock! gate)
                (if closed?
                  (begin
                    (mutex-unlock! gate)
                    (vector #f (session-failure "ASCENT actor Session closed")))
                  (begin
                    (gerbil-ascent-send-envelope! owner 'request reply authority operation args)
                    (mutex-unlock! gate)
                    (completion-wait! reply))))))
        (if (vector-ref outcome 0) (vector-ref outcome 1) (raise (vector-ref outcome 1)))))
    (def (request-state)
      (if (or (current-ascent-execution-control) (not (= (##current-vm-processor-count) 1)))
        (request 'state)
        (begin
          (when (eq? (current-thread) owner)
            (error "ASCENT actor Session request from its owner"))
          ;; An abandoned dynamic extent must not return its still-addressable
          ;; endpoint to the spare slot. The standard protection is one-shot.
          (let* ((previous (vector-ref state-spare 0))
                 (message
                  (if (and previous (eq? previous (vector-cas! state-spare 0 #f previous)))
                    previous (make-state-request (make-completion 'ascent-session-state))))
                 (reply (state-request-reply message))
                 (consumed? #f))
            (with-unwind-protect
              (lambda ()
                (mutex-lock! gate)
                (when closed?
                  (mutex-unlock! gate)
                  (error "ASCENT actor Session closed"))
                (thread-send owner message)
                (mutex-unlock! gate)
                (let (value (completion-wait! reply))
                  (set! consumed? #t)
                  value))
              (lambda ()
                (declare (not interrupts-enabled))
                (when consumed?
                  (set! consumed? #f)
                  (completion-reset! reply)
                  (vector-cas! state-spare 0 message #f))))))))
    (validate GerbilAscentSessionContract
              (.o (:: @ Session.)
                  (.append-source! (lambda (name row) (request 'append name row)))
                  (.source-replacement (lambda (name rows) (request 'replace name rows)))
                  (.source-replacements
                   (lambda (replacements (accept-result #f))
                     (unless (or (not accept-result) (procedure? accept-result))
                       (error "invalid ASCENT replacement acceptance procedure"))
                     (if accept-result
                       (request 'replace-and-run replacements accept-result)
                       (request 'replace-many replacements))))
                  (.run (lambda () (request 'run)))
                  (.run-timeout
                   (lambda (duration)
                     (unless (and (exact-integer? duration) (>= duration 0))
                       (error "invalid ASCENT timeout in nanoseconds" duration))
                     (request 'run duration)))
                  (.edge-edit
                   (lambda (expected name operation left right)
                     (request 'edit-edge expected name operation left right)))
                  (.cancel! (lambda () (request 'cancel)))
                  (.last-completed (lambda () (request 'result)))
                  (.state request-state)
                  (.close! (lambda () (request 'close) (thread-join! owner)))))))

;; The completed Result is the edit's version token. A successful call
;; returns the next completed Result, with its own source and witnesses.
(def (gerbil-ascent-session-edit-edge! session expected name operation left right)
  ((.ref session '.edge-edit) expected name operation left right))

(def (gerbil-ascent-session-cancel! session) ((.ref session '.cancel!)))
(def (gerbil-ascent-session-last-completed session) ((.ref session '.last-completed)))
(def (gerbil-ascent-session-state session) ((.ref session '.state)))
(def (gerbil-ascent-session-close! session) ((.ref session '.close!)))
