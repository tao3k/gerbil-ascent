;;; -*- Gerbil -*-
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Mechanism controls. Only production-state windows measure Session throughput.
(import :std/test
        (only-in :std/sync/completion make-completion completion-post! completion-wait!)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation
                 gerbil-ascent-variable gerbil-ascent-atom gerbil-ascent-rule)
        (only-in :gerbil-ascent/program/actor-session
                 gerbil-ascent-open-actor-session gerbil-ascent-session-state
                 gerbil-ascent-session-close!))
(export actor-state-mechanism-test)

(def count 1000000)
(def frequency
  (let (buffer (make-u64vector 1 0))
    (##get-monotonic-time-frequency! buffer 0)
    (let (value (u64vector-ref buffer 0))
      (unless (> value 0) (error "missing monotonic clock frequency"))
      value)))

(def (tick)
  (let (buffer (make-u64vector 1 0))
    (##get-monotonic-time! buffer 0)
    (u64vector-ref buffer 0)))

(def (elapsed start)
  (quotient (* (- (tick) start) 1000000000) frequency))

(def (emit value)
  (display "ACTOR-STATE-MECHANISM ") (write value) (newline) (force-output))

(def (observe phase retained operation)
  ;; No clock, logging or statistics query inside operation's million-call loop.
  ;; This component window supplies throughput, not latency samples or P95.
  (emit (list (cons 'event 'window-start) (cons 'phase phase) (cons 'retained-facts retained)))
  (let* ((before (##process-statistics))
         (cpu (cpu-time))
         (start (tick))
         (completed (operation))
         (wall (elapsed start))
         (cpu-seconds (- (cpu-time) cpu))
         (after (##process-statistics))
         (collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
         (allocation (- (f64vector-ref after 7) (f64vector-ref before 7))))
    (check completed => count)
    (emit (list (cons 'event 'window-finished) (cons 'phase phase)
                (cons 'retained-facts retained) (cons 'verified-completions completed)
                (cons 'latency-samples 0) (cons 'wall-ns wall) (cons 'cpu-seconds cpu-seconds)
                (cons 'completions-per-second (/ (* completed 1000000000.) wall))
                (cons 'natural-collections collections)
                (cons 'gc-wall-seconds (- (f64vector-ref after 5) (f64vector-ref before 5)))
                (cons 'gc-cpu-seconds
                  (+ (- (f64vector-ref after 3) (f64vector-ref before 3))
                     (- (f64vector-ref after 4) (f64vector-ref before 4))))
                (cons 'raw-allocation-counter-delta allocation)
                (cons 'allocation-bytes (and (zero? collections) (>= allocation 0) allocation))))))

(def (repeat operation)
  (let loop ((index 0))
    (if (= index count) index
      (begin (operation) (loop (+ index 1))))))

(def (controls retained session)
  (let ((expected '(0 idle)) (samples (make-f64vector count 0.)))
    (observe 'verification-loop retained
      (lambda () (repeat (lambda () (unless (equal? expected '(0 idle)) (error "invalid state"))))))
    (observe 'clock-and-sample-loop retained
      (lambda ()
        (let loop ((index 0))
          (if (= index count) index
            (let ((start (tick)))
              (unless (equal? expected '(0 idle)) (error "invalid state"))
              (f64vector-set! samples index (exact->inexact (elapsed start)))
              (loop (+ index 1)))))))
    (observe 'same-thread-fresh-completion retained
      (lambda ()
        (repeat
          (lambda ()
            (let (completion (make-completion 'ascent-state-component))
              (completion-post! completion expected)
              (unless (equal? (completion-wait! completion) '(0 idle))
                (error "incorrect Completion value")))))))
    (thread-send (current-thread) 'caller-mailbox-marker)
    (observe 'production-state-window-only retained
      (lambda ()
        (repeat (lambda ()
                  (unless (equal? (gerbil-ascent-session-state session) '(0 idle))
                    (error "incorrect production Session state"))))))
    (check (thread-receive) => 'caller-mailbox-marker)))

(def (profile retained)
  (check (##current-vm-processor-count) => 1)
  (emit (list (cons 'event 'prepare-start) (cons 'retained-facts retained)))
  (let* ((rows (map (lambda (id) (list (* id 2) (+ (* id 2) 1))) (iota retained)))
         (x (gerbil-ascent-variable 'x))
         (y (gerbil-ascent-variable 'y))
         (program (gerbil-ascent-program
                    (list (gerbil-ascent-relation 'edge 2 rows)
                          (gerbil-ascent-relation 'reach 2 []))
                    (list (gerbil-ascent-rule
                            (list (gerbil-ascent-atom 'reach (list x y)))
                            (list (gerbil-ascent-atom 'edge (list x y)))))
                    (max 1 retained) (max 1 retained) (max 1 (* 2 retained))))
         (session (gerbil-ascent-open-actor-session program workers: 1)))
    (try
      ;; No forced collection or warmup before any component window.
      (controls retained session)
      (finally (gerbil-ascent-session-close! session)))))

(def actor-state-mechanism-test
  (test-suite "single-VM Session state mechanism controls"
    (test-case "empty Session, same million-call component windows" (profile 0))
    (test-case "million-row Session, same million-call component windows" (profile count))))
