;;; -*- Gerbil -*-
;;; SPDX-FileCopyrightText: 2026 tao3k team and Contributors
;;; SPDX-License-Identifier: Apache-2.0 AND LGPL-2.1-or-later

;;; Diagnostic profiles only. Existing Case and SS budgets are unchanged.
(import (only-in :std/test check-equal? test-suite)
        (only-in :std/time/precise current-time-precise
                 PreciseTime-seconds PreciseTime-nseconds)
        (only-in :clan/poo/object .o .ref)
        (only-in :core/observability/testing-case poo-flow-test-case/with)
        (only-in :gerbil-ascent/t/performance/ascent-ss-profile ascent-ss-profile)
        (only-in :gerbil-ascent/t/qualification/ascent-rule-program-fixture
                 ascent-rule-fixture-program)
        (only-in :gerbil-ascent/t/qualification/ascent-index-program-fixture
                 ascent-index-fixture-program)
        (only-in :gerbil-ascent/program/evaluate gerbil-ascent-evaluate-program))
(export ascent-clock-memory-probe-test)

(def +poll-counters+
  (.o (:: @ ascent-ss-profile) identity: 'ascent/probe-poll-counters
      collect-before-sample?: #f))
(def +collect-counters+
  (.o (:: @ ascent-ss-profile) identity: 'ascent/probe-collect-counters
      collect-before-sample?: #t))

(def (wall-nanos)
  (let (now (current-time-precise))
    (+ (* (PreciseTime-seconds now) 1000000000) (PreciseTime-nseconds now))))

(def (timed label call repetitions)
  (let ((jiffy-start (current-jiffy)) (wall-start (wall-nanos)) (result #f))
    (for-each (lambda (_) (set! result (call))) (iota repetitions))
    (let ((jiffy-end (current-jiffy)) (wall-end (wall-nanos)))
      (displayln "CLOCK-PHASE " label " repetitions=" repetitions
                 " jiffy-ns=" (quotient (* (- jiffy-end jiffy-start) 1000000000)
                                        (* repetitions (jiffies-per-second)))
                 " precise-wall-ns=" (quotient (- wall-end wall-start) repetitions))
      (force-output)
      result)))

(def (probe label)
  (displayln "PROBE-BEGIN " label)
  (force-output)
  (for-each
   (lambda (sample)
     (let* ((program
             (timed (list label 'mixed-construction sample)
                    (lambda ()
                      (ascent-rule-fixture-program
                       '((1 2 "a") (2 3 "b") (3 3 "c") (1 2 "a")))) 1))
            (result
             (timed (list label 'mixed-solve sample)
                    (lambda () (gerbil-ascent-evaluate-program program)) 1)))
       (check-equal? (length ((.ref result 'rows-of) 'reach)) 4)))
   (iota 4))
  (let (program (ascent-index-fixture-program))
    ;; Warm declaration plans first; both clocks cover the same solver calls.
    (gerbil-ascent-evaluate-program program)
    (for-each
     (lambda (sample)
       (let (result
             (timed (list label 'indexed-warm-solve sample)
                    (lambda () (gerbil-ascent-evaluate-program program)) 128))
         (check-equal? (length ((.ref result 'rows-of) 'two-hop)) 49)))
     (iota 4)))
  (displayln "PROBE-END " label)
  (force-output))

(##gc-report-set! #t)

(def ascent-clock-memory-probe-test
  (test-suite "ASCENT timing and memory sampling diagnostic"
    (poo-flow-test-case/with +poll-counters+ "counter polling with both clocks"
      (probe 'poll-only))
    (poo-flow-test-case/with +collect-counters+ "forced collections with both clocks"
      (probe 'forced-collection))))
