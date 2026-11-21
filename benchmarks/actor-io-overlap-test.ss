;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later
;;; Public Session state progress while a Gerbil Actor waits on an OS pipe.
(import :std/test
        (only-in :std/os/pipe pipe)
        (only-in :std/time/timeout timeout->deadline)
        (only-in :std/os/device device-wait-input! device-read device-write
                 device-close OSDevice-raw)
        (only-in :gerbil/runtime/thread spawn)
        (only-in :gerbil-ascent/program/func gerbil-ascent-program gerbil-ascent-relation)
        (only-in :gerbil-ascent/program/actor-session
                 gerbil-ascent-open-actor-session gerbil-ascent-session-state
                 gerbil-ascent-session-close!))
(export actor-io-overlap-test actor-io-reference-test)

(def (waiting-on-input? reader input)
  (let (state (thread-state reader))
    (and (thread-state-waiting? state)
         (eq? (thread-state-waiting-for state) (OSDevice-raw input)))))

(def (measure-state-requests session after-work)
  (let* ((count 1000000)
         (sample-count 1000)
         (samples (make-f64vector sample-count 0.))
         (clock (make-u64vector 1 0)))
    (##get-monotonic-time-frequency! clock 0)
    (let (frequency (u64vector-ref clock 0))
      (unless (> frequency 0) (error "missing monotonic clock frequency"))
      (def (tick)
        (##get-monotonic-time! clock 0)
        (u64vector-ref clock 0))
      (def (verified-state!)
        (unless (equal? (gerbil-ascent-session-state session) '(0 idle))
          (error "unexpected Session state")))
      (let ((cpu (cpu-time)) (before (##process-statistics)) (start (tick)))
        (let loop ((i 0) (sample 0))
          (unless (= i count)
            (if (= i (* sample (quotient count sample-count)))
              (let (begin (tick))
                (verified-state!)
                (f64vector-set! samples sample
                  (/ (* 1000000000. (- (tick) begin)) frequency))
                (loop (+ i 1) (+ sample 1)))
              (begin
                (verified-state!)
                (loop (+ i 1) sample)))))
        (let* ((elapsed (/ (- (tick) start) (exact->inexact frequency)))
               (cpu-elapsed (- (cpu-time) cpu))
               (after (##process-statistics))
               (collections (- (f64vector-ref after 6) (f64vector-ref before 6)))
               (gc-wall (- (f64vector-ref after 5) (f64vector-ref before 5)))
               (io-pending? (after-work))
               (ordered (list-sort < (f64vector->list samples))))
          (display "ACTOR-IO ")
          (write (list (cons 'verified-replies count) (cons 'samples sample-count)
                       (cons 'vm-processors (##current-vm-processor-count))
                       (cons 'reader-still-pending io-pending?)
                       (cons 'wall-seconds elapsed) (cons 'cpu-seconds cpu-elapsed)
                       (cons 'requests-per-second (/ count elapsed))
                       (cons 'p50-ns (list-ref ordered 499))
                       (cons 'p95-ns (list-ref ordered 949))
                       (cons 'sample-max-ns (list-ref ordered 999))
                       (cons 'collections collections) (cons 'gc-wall-seconds gc-wall)))
          (newline))))))

(def (with-session measure)
  (check (##current-vm-processor-count) => 1)
  (let* ((program (gerbil-ascent-program
                    (list (gerbil-ascent-relation 'edge 1 [])) [] 1000 1000 1000))
         (session (gerbil-ascent-open-actor-session program workers: 1)))
    (try (measure session)
      (finally (gerbil-ascent-session-close! session)))))

(def actor-io-reference-test
  (test-suite "Single VM Session state reference"
    (test-case "verified state requests"
      (with-session (lambda (session) (measure-state-requests session (lambda () #f)))))))

(def actor-io-overlap-test
  (test-suite "Single VM Session progress during OS I/O wait"
    (test-case "state replies complete before a pending pipe read is released"
      (with-session
        (lambda (session)
          (let-values (((input output) (pipe)))
            (let* ((buffer (make-u8vector 1))
                   (reader (spawn
                             (lambda ()
                               (device-wait-input! input (timeout->deadline 80))
                               (device-read input buffer 0 1)))))
              (try
                (let wait-for-reader ()
                  (let (state (thread-state reader))
                    (cond
                      ((waiting-on-input? reader input) (void))
                      ((or (thread-state-normally-terminated? state)
                           (thread-state-abnormally-terminated? state))
                       (error "pipe reader ended before data was sent"))
                      (else (thread-yield!) (wait-for-reader)))))
                (measure-state-requests session
                  (lambda ()
                    (unless (waiting-on-input? reader input)
                      (error "pipe reader resumed before data was sent"))
                    #t))
                (check (device-write output #u8(91) 0 1) => 1)
                (check (thread-join! reader) => 1)
                (check (u8vector-ref buffer 0) => 91)
                (finally
                  (device-close output)
                  (try (thread-join! reader)
                    (finally (device-close input))))))))))))
