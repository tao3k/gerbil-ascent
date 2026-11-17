;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import :gerbil/runtime/gambit
        (only-in :gerbil-ascent/core/actor-envelope
                 gerbil-ascent-send-envelope! gerbil-ascent-match-envelope!)
        (only-in :gerbil-ascent/core/execution-control
                 current-ascent-execution-control ascent-execution-checkpoint! ascent-accept-publication!)
        (only-in "source-cut.ss" gerbil-ascent-make-source-cut
                 gerbil-ascent-source-cut-rows gerbil-ascent-source-cut-update
                 gerbil-ascent-source-cut-scalar?)
        (only-in "update-selection.ss" gerbil-ascent-update-eligible?)
        (only-in :clan/poo/object .o .ref)
        (only-in :clan/poo/type validate)
        (only-in "types.ss" GerbilAscentSessionContract gerbil-ascent-canonical-actor-inputs?
                 gerbil-ascent-projection-tree-current?)
        (only-in "evaluate.ss" gerbil-ascent-make-engine gerbil-ascent-make-engine-state)
        (only-in "engine-state.ss" engine-state-schema engine-state-analysis)
        (only-in "positive-components.ss" gerbil-ascent-component-mode?))
(export gerbil-ascent-open-actor-session gerbil-ascent-session-cancel!
        gerbil-ascent-session-last-completed gerbil-ascent-session-close!
        gerbil-ascent-session-state)

(defstruct actor-run (epoch token worker monitor reply authority sources accept-result) final: #t)
(defstruct actor-engine (run token) final: #t)

(def Session. (.ref GerbilAscentSessionContract 'proto))

(def (session-failure message)
  (with-catch (lambda (failure) failure) (lambda () (error message))))

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
  (unless (and (exact-integer? workers) (> workers 0))
    (error "invalid ASCENT actor Session capacity" workers))
  (let* ((admitted (gerbil-ascent-make-engine-state program))
         (schema (engine-state-schema admitted))
         (analysis (engine-state-analysis admitted)))
    (cond
     ((gerbil-ascent-component-mode? #f workers #t analysis schema)
      (make-actor-session program workers schema analysis))
     (required? (error "ASCENT actor Session requires pure positive Set rules"))
     (else #f))))

(def (make-actor-session program workers schema analysis)
  (let* ((relations (.ref program 'relations))
         (input-limit (.ref program 'max-input-facts))
         (positions (vector-ref schema 4)) (arities (vector-ref schema 2))
         (initial (gerbil-ascent-make-source-cut positions arities
                    (map (lambda (relation) (cons (.ref relation 'name) (.ref relation 'rows))) relations)))
         (gate (make-mutex 'ascent-session-lifecycle)) (closed? #f)
         (owner
          (parameterize ((current-ascent-execution-control #f))
           (spawn/name 'ascent-session-owner
           (lambda ()
             (let ((pending initial) (committed initial) (published #f) (retained #f)
                   (snapshot-source #f) (snapshot-relations #f)
                   (source-indexes (and (= workers 1) (make-vector (vector-length arities) #f)))
                   (generation 0) (running #f) (closing []))
               (def (reply! channel value) (thread-send channel value))
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
                   (let (token (actor-run-token running))
                     (mutex-lock! (vector-ref token 0))
                     (vector-set! token 1 #t)
                     (mutex-unlock! (vector-ref token 0)))))
               (def (update! replacements append?)
                 (when running (error "ASCENT actor Session source update while running"))
                 (let (next (gerbil-ascent-source-cut-update pending positions arities replacements append? input-limit))
                   (set! pending next)
                   (set! retained #f)
                   (set! snapshot-source #f) (set! snapshot-relations #f)
                   (set! generation (+ generation 1)) (void)))
               ;; Only the owner performs final acceptance and publication.
               ;; A worker cannot freeze caller cancellation before this point.
               (def (finish! epoch worker outcome)
                 (when (and running (= epoch (actor-run-epoch running))
                            (eq? worker (actor-run-worker running)))
                   (thread-join! (actor-run-monitor running))
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
                           (set! published (vector-ref outcome 1)))
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
               (def (evaluate-cut cut sources owned? previous token duration authority)
                 (with-catch (lambda (failure) (vector #f failure))
                   (lambda ()
                     (parameterize
                         ((current-ascent-execution-control
                           (and authority
                                (lambda (work facts)
                                  (authority (if (= work -1) 0 work) facts)))))
                       (ascent-execution-checkpoint!)
                       ;; Eligibility may inspect source rows, so the worker does it.
                       (let* ((retain? (and (= workers 1) owned?
                                            (gerbil-ascent-projection-tree-current? program)
                                            (gerbil-ascent-source-cut-scalar? sources)
                                            (gerbil-ascent-update-eligible? program)))
                              (candidate (or (and retain? previous)
                                             (make-actor-engine #f (vector #f)))))
                         (def (canceled?)
                           (let (active (vector-ref (actor-engine-token candidate) 0))
                             (and active
                                  (begin
                                    (mutex-lock! (vector-ref active 0))
                                    (let (canceled (vector-ref active 1))
                                      (mutex-unlock! (vector-ref active 0))
                                      canceled)))))
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
                           (lambda () (vector-set! (actor-engine-token candidate) 0 #f))))))))
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
                          (token (vector (make-mutex) #f))
                          (session-owner (current-thread))
                          (worker
                           (spawn/name 'ascent-session-evaluation
                             (lambda ()
                               (evaluate-cut cut sources owned? previous token duration authority))))
                          (monitor
                           (spawn/name 'ascent-session-monitor
                             (lambda ()
                               (let (outcome
                                      (with-catch (lambda (failure) (vector #f failure))
                                        (lambda () (thread-join! worker))))
                                 (thread-send session-owner ['terminal epoch worker outcome]))))))
                     (set! running
                       (make-actor-run epoch token worker monitor channel authority sources accept-result)))))
               (def (dispatch-request! channel authority operation args)
                 (with-catch (lambda (failure) (reply! channel (vector #f failure)))
                   (lambda ()
                     (parameterize ((current-ascent-execution-control authority))
                       (case operation
                         ((run) (start-run! channel authority (if (null? args) #f (car args))))
                         ((replace-and-run)
                          (start-run! channel authority #f (cadr args) (car args)))
                         ((append) (update! (list (cons (car args) (list (cadr args)))) #t) (reply! channel (vector #t (void))))
                         ((replace) (update! (list (cons (car args) (cadr args))) #f) (reply! channel (vector #t (void))))
                         ((replace-many) (update! (car args) #f) (reply! channel (vector #t (void))))
                         ((cancel) (mark-canceled!) (reply! channel (vector #t (if running 'draining 'idle))))
                         ((result) (reply! channel (vector #t published)))
                         ((state)
                          (reply! channel
                            (vector #t
                              (list generation
                                (if running
                                  (if (= generation (actor-run-epoch running)) 'running 'draining)
                                  'idle)))))
                         ((close) (mark-canceled!) (set! closing (cons channel closing))))))))
               (def (dispatch-message! message)
                 (gerbil-ascent-match-envelope! message
                   (['request channel authority operation args]
                    (dispatch-request! channel authority operation args))
                   (else
                     (match message
                       (['terminal epoch worker outcome] (finish! epoch worker outcome))))))
               (let loop ()
                 (dispatch-message! (thread-receive))
                 (if (and (pair? closing) (not running))
                   (begin
                     (mutex-lock! gate) (set! closed? #t) (mutex-unlock! gate)
                     ;; No requests accepted after closed? is set. Drain requests
                     ;; already admitted through gate before terminating owner.
                     (let drain ()
                       (gerbil-ascent-match-envelope! (thread-receive 0 #f)
                         (['request channel authority operation args]
                          (begin
                            (if (eq? operation 'close) (set! closing (cons channel closing))
                                (reply! channel (vector #f (session-failure "ASCENT actor Session closed"))))
                            (drain))) (else (void))))
                     (for-each (lambda (channel) (reply! channel (vector #t (void)))) closing))
                   (loop)))))))))
    (def (request operation . args)
      ;; A checker/getter running on this coordinator cannot synchronously
      ;; wait for the coordinator's own mailbox. Refuse before allocating a
      ;; reply Actor so the surrounding operation can recover normally.
      (when (eq? (current-thread) owner)
        (error "ASCENT actor Session request from its owner"))
      ;; A private reply actor leaves the caller's mailbox untouched.
      (let* ((authority (current-ascent-execution-control))
             (outcome
              (thread-join!
               (spawn/name 'ascent-session-request
                (lambda ()
                  (mutex-lock! gate)
                  (if closed?
                    (begin (mutex-unlock! gate) (vector #f (session-failure "ASCENT actor Session closed")))
                    (begin
                      (gerbil-ascent-send-envelope! owner 'request (current-thread) authority operation args)
                      (mutex-unlock! gate)
                      (thread-receive))))))))
        (if (vector-ref outcome 0) (vector-ref outcome 1) (raise (vector-ref outcome 1)))))
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
                  (.cancel! (lambda () (request 'cancel)))
                  (.last-completed (lambda () (request 'result)))
                  (.state (lambda () (request 'state)))
                  (.close! (lambda () (request 'close) (thread-join! owner)))))))

(def (gerbil-ascent-session-cancel! session) ((.ref session '.cancel!)))
(def (gerbil-ascent-session-last-completed session) ((.ref session '.last-completed)))
(def (gerbil-ascent-session-state session) ((.ref session '.state)))
(def (gerbil-ascent-session-close! session) ((.ref session '.close!)))
