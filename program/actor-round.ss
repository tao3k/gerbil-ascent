;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(import (only-in :gerbil-ascent/core/positive-plan gerbil-ascent-pure-positive-plan?)
        (only-in :gerbil-ascent/table/storage gerbil-ascent-canonical-set-storage-provider?
                 gerbil-ascent-canonical-uf-storage-provider?)
        (only-in :gerbil-ascent/table/provider gerbil-ascent-canonical-hash-index-provider?))
(export gerbil-ascent-run-actor-round! gerbil-ascent-actor-round-eligible?)

;; gerbil-ascent-actor-round-eligible?
;; : (forall (r s i l f) (-> [r] (Vector s) (Vector i) (Vector l) (Vector f) Boolean))
;; : (-> AdmittedRulePlans StorageProviders IndexProviders LatticeJoins FieldCheckers Boolean)
;; | doc m%
;;     Admit parallel computation only for pure plans and private canonical Set or frozen UF
;;     storage/index receivers, without lattice or user field callbacks. The
;;     evaluator still owns worker options and the private source/frontier cut.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-actor-round-eligible? rules storages indexes joins fields)
;;     ;; => #t only when each computation/Provider permits actor execution
;;     ```
;;   %
(def (gerbil-ascent-actor-round-eligible? rules storages indexes joins fields)
  (and (andmap (lambda (rule) (gerbil-ascent-pure-positive-plan? (vector-ref rule 5))) rules)
       (andmap (lambda (provider) (or (gerbil-ascent-canonical-set-storage-provider? provider)
                                    (gerbil-ascent-canonical-uf-storage-provider? provider)))
               (vector->list storages))
       (andmap gerbil-ascent-canonical-hash-index-provider? (vector->list indexes))
       (andmap not (vector->list joins))
       (andmap not (vector->list fields))))

;;; A worker owns one task and at most one 32-row batch awaiting owner credit.
;;; Workers and their joining monitors live for one round and are reused only
;;; after task completion. The coordinator alone admits tasks and merges rows.
;;; Failure stops admission and drains assigned tasks before joining the pool.
;; run-task
;; : (forall (task atom row) (-> Thread RoundKey task (Execute task atom row) TaskOutcome))
;; : (-> Thread RoundKey Task Execute (Or Symbol (Pair Symbol Any)))
;; | doc m%
;;     A fresh batch and checkpoint window belong to this assignment. Share
;;     one continuation so both task failure and refused credit unwind dynamic
;;     cleanup without another capture; refusal bypasses task exception handlers.
;;
;;     # Examples
;;
;;     ```scheme
;;     (run-task owner key task execute)
;;     ;; => (finished . candidates), transferring the bounded final tail
;;     ```
;;   %
(def (run-task owner key task execute)
  ;; Share one continuation between exception handling and refused credit.
  ;; Refused credit exits even if execute installs its own exception handler.
  (call/cc
   (lambda (stop)
    (with-exception-handler (lambda (exception) (stop (cons 'failed exception)))
      (lambda ()
         (let ((batch []) (size 0) (ticks 0))
           (def (request! kind payload)
             (thread-send owner [kind key (current-thread) task payload])
             (unless (eq? (thread-receive) 'credit) (stop 'stopped)))
           (def (flush!)
             (unless (zero? size)
               (request! 'batch (reverse batch))
               (set! ticks 0)
               (set! batch []) (set! size 0)))
           (def (emit! atom row)
             (set! batch (cons (cons atom row) batch))
             (set! size (+ size 1))
             (when (= size 32) (flush!)))
           (def (checkpoint!)
             (set! ticks (+ ticks 1))
             (when (= ticks 64)
               (set! ticks 0) (request! 'checkpoint #f)))
           (execute task emit! checkpoint!)
           ;; Execution has ended: transfer the bounded tail with completion.
           ;; The worker waits for its next assignment instead of another credit.
           (cons 'finished (reverse batch))))))))

;; gerbil-ascent-run-actor-round!
;; : (forall (task atom row) (-> RoundKey (List task) PositiveInteger (Execute task atom row) (Merge atom row) Cancel (Ready task) (Completed task) Void))
;; : (-> RoundKey (List Task) PositiveInteger Execute Merge Cancel Ready Completed Void)
;; | doc m%
;;     Execute ready tasks with at most jobs workers. Execute receives a task,
;;     emit! and checkpoint!; merge and completion callbacks run only on the
;;     coordinator. Ready may prepare private state transferred at admission.
;;     Reuse follows task completion; return follows joining the entire pool.
;;     Cancellation or callback failure refuses credit, drains assigned tasks
;;     and raises the first exception. Caller task spines are never mutated.
;;
;;     # Examples
;;
;;     ```scheme
;;     (gerbil-ascent-run-actor-round! key tasks jobs execute merge)
;;     ;; => #!void after every assigned task and pool worker has finished
;;     ```
;;   %
(def (gerbil-ascent-run-actor-round! key tasks jobs execute merge (canceled? (lambda () #f))
                                     (ready? (lambda (_) #t))
                                     (completed! (lambda (_) (void))))
  (unless (and (exact-integer? jobs) (> jobs 0))
    (error "invalid ASCENT worker capacity" jobs))
  (let (result
        (thread-join!
         (spawn/name 'ascent-round-owner
          (lambda ()
            (with-catch (lambda (exception) (cons 'failed exception))
              (lambda ()
                (let ((owner (current-thread))
                      ;; The sentinel and spine belong to this coordinator alone.
                      (pending (cons #f (map values tasks)))
                      (assigned (make-hash-table-eq))
                      (active (make-hash-table-eq)) (active-count 0)
                      (workers []) (idle []) (awaiting #f) (failed? #f) (failure #f))
                  (def (stop! exception)
                    (unless failed? (set! failure exception) (set! failed? #t))
                    (set-cdr! pending []))
                  (def (take-ready!)
                    (let scan ((previous pending) (rest (cdr pending)))
                      (cond
                       ((null? rest) #f)
                       ((hash-get assigned (car rest))
                        (set-cdr! previous (cdr rest))
                        (scan previous (cdr rest)))
                       ((ready? (car rest))
                        (let (task (car rest))
                          (when task
                            (set-cdr! previous (cdr rest))
                            (hash-put! assigned task #t))
                          task))
                       (else (scan rest (cdr rest))))))
                  (def (make-worker!)
                    (let* ((worker
                            (spawn/name 'ascent-round-worker
                             (lambda ()
                               (let loop ()
                                 (match (thread-receive)
                                   (['task task]
                                    (let (result (run-task owner key task execute))
                                      (thread-send owner ['done key (current-thread) task result]))
                                    (loop))
                                   ('stop 'finished))))))
                           (monitor
                            (spawn/name 'ascent-round-monitor
                             (lambda ()
                               (let (result (with-catch (lambda (exception) (cons 'failed exception))
                                               (lambda () (thread-join! worker))))
                                 (thread-send owner ['exited key worker #f result]))))))
                      (set! workers (cons (cons worker monitor) workers))
                      worker))
                  (def (start! task)
                    (let (worker (if (pair? idle)
                                   (let (worker (car idle)) (set! idle (cdr idle)) worker)
                                   (make-worker!)))
                      (hash-put! active worker task)
                      (set! active-count (+ active-count 1))
                      (thread-send worker ['task task])))
                  ;; Recovery refuses the outstanding credit before resuming
                  ;; the drain loop. Successful iterations capture no continuation.
                  (def (run!)
                    (with-catch
                     (lambda (exception)
                       (stop! exception)
                       (when awaiting
                         (thread-send awaiting 'stop)
                         (set! awaiting #f))
                       (run!))
                     (lambda ()
                       (let loop ()
                         (unless failed?
                           (when (canceled?) (error "ASCENT actor round canceled"))
                           (let admit ()
                             (when (and (pair? (cdr pending)) (< active-count jobs))
                               (let (task (take-ready!))
                                 (when task (start! task) (admit))))))
                         (unless (zero? active-count)
                           (match (thread-receive)
                             ([kind received-key worker task payload]
                              (when (eq? received-key key)
                                (let (assignment (hash-get active worker))
                                  (cond
                                   ((eq? kind 'exited)
                                    (when assignment
                                      (hash-remove! active worker)
                                      (set! active-count (- active-count 1)))
                                    (if (and (pair? payload) (eq? (car payload) 'failed))
                                      (stop! (cdr payload))
                                      (error "ASCENT worker exited before pool shutdown")))
                                   ((and assignment (eq? task assignment))
                                    (case kind
                                      ((batch checkpoint)
                                       (set! awaiting worker)
                                       (unless failed?
                                         (when (canceled?) (error "ASCENT actor round canceled"))
                                         (when (eq? kind 'batch)
                                           (for-each (lambda (candidate) (merge (car candidate) (cdr candidate))) payload)))
                                       (thread-send worker (if failed? 'stop 'credit))
                                       (set! awaiting #f))
                                      ((done)
                                       (hash-remove! active worker)
                                       (set! active-count (- active-count 1))
                                       (set! idle (cons worker idle))
                                       (if (and (pair? payload) (eq? (car payload) 'failed))
                                         (stop! (cdr payload))
                                         (unless failed?
                                           (when (and (pair? payload) (eq? (car payload) 'finished))
                                             (unless (null? (cdr payload))
                                               (when (canceled?) (error "ASCENT actor round canceled"))
                                               (for-each (lambda (candidate) (merge (car candidate) (cdr candidate)))
                                                         (cdr payload))))
                                           (completed! task))))))))))
                             (else (void)))
                           (loop))))))
                  (try
                   (run!)
                   (cond (failed? (raise failure))
                         ((pair? (cdr pending)) (error "ASCENT ready task dependency deadlock")))
                   (finally
                    (for-each (lambda (entry) (thread-send (car entry) 'stop)) workers)
                    (for-each (lambda (entry) (thread-join! (cdr entry))) workers))))))))))
    (if (and (pair? result) (eq? (car result) 'failed))
      (raise (cdr result)) result)))
