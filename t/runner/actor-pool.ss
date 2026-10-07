;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
(export run-actor-pool!)

;;; One invocation owns its private mailbox. At most jobs tasks and jobs output
;;; lines are outstanding: a worker must receive credit before reading again.
;;; First failure cancels pending admission; assigned children drain under their
;;; own progress/deadline supervisor. Only the coordinator writes shared stdout.
(def (run-actor-pool! tasks jobs execute (output displayln))
  ;; The caller's actor mailbox can contain unrelated protocol messages.
  ;; A fresh coordinator isolates this invocation, including nested pools.
  (thread-join! (spawn/name 'native-test-coordinator
                  (lambda () (coordinate! tasks jobs execute output)))))

(def (coordinate! tasks jobs execute output)
  (unless (and (integer? jobs) (> jobs 0)) (error "invalid actor pool capacity" jobs))
  (let ((owner (current-thread)) (pending tasks) (active []) (status 0))
    (def (start! task)
      (let* ((worker
              (spawn/name 'native-test-worker
                (lambda ()
                  (execute task
                    (lambda (line)
                      (thread-send owner ['line (current-thread) task line])
                      (unless (eq? (thread-receive) 'credit)
                        (error "invalid native test output credit")))))))
             (monitor
              (spawn/name 'native-test-monitor
                (lambda ()
                  (let (result (try (thread-join! worker)
                                    (catch (exception) 70)))
                    (thread-send owner ['done worker task result]))))))
        (set! active (cons (cons worker monitor) active))))
    (let loop ()
      (when (zero? status)
        (let admit ()
          (when (and (pair? pending) (< (length active) jobs))
            (let (task (car pending))
              (set! pending (cdr pending))
              (start! task))
            (admit))))
      (if (null? active)
        status
        (begin
          (match (thread-receive)
            (['line worker task line]
             (unless (assq worker active) (error "unassigned native test output" task))
             ;; Return credit even when the output sink raises; otherwise the
             ;; worker could remain stuck holding a child pipe indefinitely.
             (try (output line) (force-output)
                  (catch (exception) (when (zero? status) (set! status 70)) (set! pending []))
                  (finally (thread-send worker 'credit))))
            (['done worker task result]
             (let (entry (assq worker active))
               (unless entry (error "duplicate or unassigned native test completion" task))
               (thread-join! (cdr entry))
               (set! active (filter (lambda (entry) (not (eq? (car entry) worker))) active))
               (unless (and (integer? result) (<= 0 result 255)) (set! result 70))
               (when (and (zero? status) (not (zero? result)))
                 (set! status result)
                 (set! pending []))))
            (else (error "invalid native test pool message")))
          (loop))))))
