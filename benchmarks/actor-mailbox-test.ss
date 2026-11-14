;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Single-VM components, not a Rust bridge or rule-evaluation benchmark.
(import :std/test
        (only-in :std/time/precise current-time-precise PreciseTime-seconds PreciseTime-nseconds)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation)
        (only-in :gerbil-ascent/program/actor-session
                 gerbil-ascent-open-actor-session gerbil-ascent-session-state
                 gerbil-ascent-session-close!))
(export actor-mailbox-test)

(def (nanoseconds)
  (let (time (current-time-precise))
    (+ (* (PreciseTime-seconds time) 1000000000) (PreciseTime-nseconds time))))

(def actor-mailbox-test
  (test-suite "Single VM Actor components"
    (test-case "one million ordered mailbox messages with receiver drain"
      (check (##current-vm-processor-count) => 1)
      (let* ((count 1000000)
             (receiver
               (spawn
                 (lambda ()
                   (let loop ((next 0))
                     (if (= next count) next
                       (let (message (thread-receive))
                         (unless (= message next)
                           (error "Actor mailbox order differs" next message))
                         (loop (+ next 1))))))))
             (start (nanoseconds)))
        (let loop ((next 0))
          (unless (= next count)
            (thread-send receiver next)
            (loop (+ next 1))))
        (check (thread-join! receiver) => count)
        (let (elapsed (- (nanoseconds) start))
          (display "ACTOR-MAILBOX ")
          (write (list (cons 'unit 'one-way-fixnum-message)
                       (cons 'messages count) (cons 'elapsed-ns elapsed)
                       (cons 'messages-per-second (/ (* count 1000000000.) elapsed))))
          (newline))))
    (test-case "ten thousand public Session state request replies"
      (check (##current-vm-processor-count) => 1)
      (let* ((program (gerbil-ascent-program
                       (list (gerbil-ascent-relation 'edge 1 [])) [] 1000 1000 1000))
             (opening (nanoseconds))
             (session (gerbil-ascent-open-actor-session program workers: 1))
             (open-ns (- (nanoseconds) opening))
             (count 10000)
             (samples (make-f64vector count 0.)))
        (try
          ;; Normalize once, never between individual requests. No formatting
          ;; or output occurs inside a request interval or the aggregate loop.
          (##gc)
          (thread-send (current-thread) 'caller-mailbox-marker)
          (let ((before (##process-statistics)) (start (nanoseconds)))
            (let loop ((index 0))
              (unless (= index count)
                (let* ((request-start (nanoseconds))
                       (result (gerbil-ascent-session-state session))
                       (elapsed (- (nanoseconds) request-start)))
                  (unless (equal? result '(0 idle))
                    (error "Actor Session state differs" index result))
                  (f64vector-set! samples index (exact->inexact elapsed)))
                (loop (+ index 1))))
            (let* ((elapsed (- (nanoseconds) start))
                   (after (##process-statistics))
                   (ordered (list-sort < (f64vector->list samples)))
                   (p95 (list-ref ordered 9499)))
              (check (thread-receive) => 'caller-mailbox-marker)
              (display "ACTOR-SESSION ")
              (write (list (cons 'unit 'public-session-state-request-reply)
                           (cons 'requests count) (cons 'open-ns open-ns)
                           (cons 'first-request-ns (f64vector-ref samples 0))
                           (cons 'aggregate-ns elapsed)
                           (cons 'requests-per-second (/ (* count 1000000000.) elapsed))
                           (cons 'p50-ns (list-ref ordered 4999))
                           (cons 'p95-ns p95) (cons 'max-ns (list-ref ordered 9999))
                           (cons 'collections (- (f64vector-ref after 6) (f64vector-ref before 6)))))
              (newline)
              (check (< p95 100000000) => #t)))
          (finally (gerbil-ascent-session-close! session)))))))
