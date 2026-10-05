;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(export gerbil-ascent-run-actor-round!)

;;; Each task has one worker and one joining monitor. A worker can own at most
;;; one 32-row batch awaiting credit. Only this private coordinator calls merge.
;;; Failure/cancellation stops admission, refuses subsequent batches and joins
;;; every assigned worker before returning or raising the original exception.
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
      (let ((owner (current-thread)) (pending tasks) (active []) (failure #f))
        (def (stop! exception)
          (unless failure (set! failure exception))
          (set! pending []))
        (def (start! task)
          (let* ((worker
                   (spawn/name 'ascent-round-worker
                    (lambda ()
                      (with-catch (lambda (exception) (cons 'failed exception))
                       (lambda ()
                      (call/cc
                       (lambda (stop)
                         (let ((batch []) (size 0) (ticks 0))
                           (def (request! kind payload)
                             (thread-send owner [kind key (current-thread) task payload])
                             (unless (eq? (thread-receive) 'credit) (stop 'stopped)))
                           (def (flush!)
                             (unless (zero? size)
                               (request! 'batch (reverse batch))
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
                           (flush!) 'finished))))))))
                 (monitor
                   (spawn/name 'ascent-round-monitor
                    (lambda ()
                      (let (result (with-catch (lambda (exception) (cons 'failed exception))
                                              (lambda () (thread-join! worker))))
                        (thread-send owner ['terminal key worker task result]))))))
            (set! active (cons (list worker monitor task) active))))
        (let loop ()
          (unless failure
            (with-catch stop!
              (lambda () (when (canceled?) (error "ASCENT actor round canceled")))))
          (unless failure
            (with-catch stop! (lambda ()
            (let admit ()
              (when (and (pair? pending) (< (length active) jobs))
                (let (task (find ready? pending))
                  (when task
                    (set! pending (filter (lambda (next) (not (eq? task next))) pending))
                    (start! task) (admit))))))))
          (if (null? active)
            (if failure (raise failure)
              (if (null? pending) (void) (error "ASCENT ready task dependency deadlock")))
            (begin
              (match (thread-receive)
                ([kind received-key worker task payload]
                 (let (assignment (assq worker active))
                   (when (and assignment (eq? received-key key) (eq? task (caddr assignment)))
                     (case kind
                       ((batch checkpoint)
                        (unless failure
                          (with-catch stop!
                            (lambda ()
                              (when (canceled?) (error "ASCENT actor round canceled"))
                              (when (eq? kind 'batch)
                                (for-each (lambda (candidate) (merge (car candidate) (cdr candidate))) payload)))))
                        (thread-send worker (if failure 'stop 'credit)))
                       ((terminal)
                        (thread-join! (cadr assignment))
                        (set! active (filter (lambda (entry) (not (eq? (car entry) worker))) active))
                        (if (and (pair? payload) (eq? (car payload) 'failed))
                          (stop! (cdr payload))
                          (unless failure (with-catch stop! (lambda () (completed! task))))))))))
                (else (void)))
              (loop)))))))))))
    (if (and (pair? result) (eq? (car result) 'failed))
      (raise (cdr result)) result)))
